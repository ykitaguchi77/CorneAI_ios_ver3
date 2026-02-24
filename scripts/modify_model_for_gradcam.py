#!/usr/bin/env python3
"""
Modify last.mlmodel to expose intermediate feature maps for GradCAM,
and export detection head 1x1 Conv weights.

Usage:
    python scripts/modify_model_for_gradcam.py

Inputs:
    CorneAI_ios_ver3/last.mlmodel

Outputs:
    CorneAI_ios_ver3/last_cam.mlmodel  (model with intermediate feature map outputs)
    CorneAI_ios_ver3/cam_weights.json  (detection head weights per class)

Requirements:
    pip install coremltools numpy
"""

import coremltools as ct
import json
import numpy as np
import sys
import os

# Paths
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.join(SCRIPT_DIR, "..")
SRC_DIR = os.path.join(PROJECT_DIR, "CorneAI_ios_ver3")
MODEL_PATH = os.path.join(SRC_DIR, "last.mlmodel")
OUTPUT_MODEL_PATH = os.path.join(SRC_DIR, "last_cam.mlmodel")
OUTPUT_WEIGHTS_PATH = os.path.join(SRC_DIR, "cam_weights.json")

# Model structure (verified from model inspection)
FEATURE_MAPS = [
    {
        "name": "input.177",
        "output_name": "feature_p3",
        "channels": 128,
        "spatial": [80, 80],
    },
    {
        "name": "input.199",
        "output_name": "feature_p4",
        "channels": 256,
        "spatial": [40, 40],
    },
    {
        "name": "input",
        "output_name": "feature_p5",
        "channels": 512,
        "spatial": [20, 20],
    },
]

NUM_CLASSES = 9
NUM_ANCHORS = 3
ATTRS_PER_ANCHOR = 5 + NUM_CLASSES  # 14 = x,y,w,h,obj + 9 classes
CLASSES = [
    "infection", "normal", "non-infection", "scar", "tumor",
    "deposit", "APAC", "lens-opacity", "bullous",
]


def find_nn_spec(spec):
    """Find the neural network spec, handling pipeline models."""
    model_type = spec.WhichOneof("Type")

    if model_type == "pipeline":
        for i, sub_model in enumerate(spec.pipeline.models):
            sub_type = sub_model.WhichOneof("Type")
            if sub_type == "neuralNetwork":
                print(f"  Found neuralNetwork at pipeline index {i}")
                return sub_model.neuralNetwork, i
            elif sub_type == "neuralNetworkClassifier":
                print(f"  Found neuralNetworkClassifier at pipeline index {i}")
                return sub_model.neuralNetworkClassifier, i
        return None, None
    elif model_type == "neuralNetwork":
        return spec.neuralNetwork, None
    elif model_type == "neuralNetworkClassifier":
        return spec.neuralNetworkClassifier, None
    else:
        return None, None


def find_detection_head(nn_spec, feature_input_name, expected_channels):
    """Find the 1x1 Conv detection head layer for a given feature map."""
    for layer in nn_spec.layers:
        if feature_input_name not in layer.input:
            continue
        if layer.WhichOneof("layer") != "convolution":
            continue
        conv = layer.convolution
        if (conv.kernelSize[0] == 1 and conv.kernelSize[1] == 1
                and conv.outputChannels == NUM_ANCHORS * ATTRS_PER_ANCHOR):
            return layer
    return None


def extract_class_weights(head_layer, channels):
    """Extract per-class CAM weights from a detection head's 1x1 Conv."""
    conv = head_layer.convolution
    raw_weights = np.array(conv.weights.floatValue)

    # Shape: [outputChannels, inputChannels] for 1x1 conv
    # = [NUM_ANCHORS * ATTRS_PER_ANCHOR, channels]
    weight_matrix = raw_weights.reshape(NUM_ANCHORS * ATTRS_PER_ANCHOR, channels)

    class_weights = {}
    for c in range(NUM_CLASSES):
        w = np.zeros(channels)
        for a in range(NUM_ANCHORS):
            # Skip x,y,w,h,obj (5 values) per anchor
            idx = a * ATTRS_PER_ANCHOR + 5 + c
            w += weight_matrix[idx, :]
        w /= NUM_ANCHORS  # average over anchors
        class_weights[str(c)] = w.tolist()

    return class_weights


def add_feature_outputs(nn_spec, spec, nn_index):
    """Add identity layers to expose intermediate feature maps as outputs."""
    for fm_info in FEATURE_MAPS:
        feature_name = fm_info["name"]
        output_name = fm_info["output_name"]
        channels = fm_info["channels"]
        h, w = fm_info["spatial"]

        # Add an identity layer (linear activation with alpha=1, beta=0)
        identity_layer = nn_spec.layers.add()
        identity_layer.name = f"cam_{output_name}"
        identity_layer.input.append(feature_name)
        identity_layer.output.append(output_name)
        identity_layer.activation.linear.alpha = 1.0
        identity_layer.activation.linear.beta = 0.0

        print(f"  Added identity layer: {feature_name} -> {output_name}")

    # Add to NN sub-model output description
    if nn_index is not None:
        sub_desc = spec.pipeline.models[nn_index].description
    else:
        sub_desc = spec.description

    for fm_info in FEATURE_MAPS:
        output = sub_desc.output.add()
        output.name = fm_info["output_name"]
        output.type.multiArrayType.shape.extend([
            fm_info["channels"], fm_info["spatial"][0], fm_info["spatial"][1]
        ])
        output.type.multiArrayType.dataType = 65600  # FLOAT32
        print(f"  Added NN output: {fm_info['output_name']} "
              f"shape=[{fm_info['channels']}, {fm_info['spatial'][0]}, {fm_info['spatial'][1]}]")

    # If pipeline, also add to pipeline-level output description
    if nn_index is not None:
        for fm_info in FEATURE_MAPS:
            output = spec.description.output.add()
            output.name = fm_info["output_name"]
            output.type.multiArrayType.shape.extend([
                fm_info["channels"], fm_info["spatial"][0], fm_info["spatial"][1]
            ])
            output.type.multiArrayType.dataType = 65600  # FLOAT32


def main():
    print(f"Loading model from {MODEL_PATH}...")
    if not os.path.exists(MODEL_PATH):
        print(f"ERROR: Model not found at {MODEL_PATH}")
        sys.exit(1)

    model = ct.models.MLModel(MODEL_PATH)
    spec = model.get_spec()

    model_type = spec.WhichOneof("Type")
    print(f"Model type: {model_type}")

    nn_spec, nn_index = find_nn_spec(spec)
    if nn_spec is None:
        print("ERROR: Could not find neural network in model")
        sys.exit(1)

    print(f"Total NN layers: {len(nn_spec.layers)}")

    # --- Step 1: Extract detection head weights ---
    print("\n=== Extracting detection head weights ===")
    cam_weights_data = {"scales": [], "classes": CLASSES}

    for fm_info in FEATURE_MAPS:
        feature_name = fm_info["name"]
        channels = fm_info["channels"]

        head_layer = find_detection_head(nn_spec, feature_name, channels)
        if head_layer is None:
            print(f"WARNING: Could not find detection head for {feature_name}")
            print("  Listing layers that use this input:")
            for layer in nn_spec.layers:
                if feature_name in layer.input:
                    print(f"    {layer.name}: type={layer.WhichOneof('layer')}, "
                          f"inputs={list(layer.input)}, outputs={list(layer.output)}")
            continue

        print(f"\nFound detection head for {feature_name}:")
        print(f"  Layer: {head_layer.name}")
        print(f"  Input channels: {head_layer.convolution.kernelChannels}")
        print(f"  Output channels: {head_layer.convolution.outputChannels}")

        class_weights = extract_class_weights(head_layer, channels)

        cam_weights_data["scales"].append({
            "feature_name": fm_info["output_name"],
            "original_name": feature_name,
            "channels": channels,
            "spatial": fm_info["spatial"],
            "weights": class_weights,
        })

    # Save weights
    print(f"\nSaving CAM weights to {OUTPUT_WEIGHTS_PATH}...")
    with open(OUTPUT_WEIGHTS_PATH, "w") as f:
        json.dump(cam_weights_data, f)
    print(f"  Saved {len(cam_weights_data['scales'])} scales")

    # --- Step 2: Add feature map outputs to model ---
    print("\n=== Adding intermediate feature map outputs ===")
    add_feature_outputs(nn_spec, spec, nn_index)

    # Save modified model
    print(f"\nSaving modified model to {OUTPUT_MODEL_PATH}...")
    ct.utils.save_spec(spec, OUTPUT_MODEL_PATH)
    print("Done!")

    # Verification
    print(f"\nVerification:")
    print(f"  cam_weights.json: {os.path.getsize(OUTPUT_WEIGHTS_PATH):,} bytes")
    print(f"  last_cam.mlmodel: {os.path.getsize(OUTPUT_MODEL_PATH):,} bytes")

    # Quick sanity check: reload and verify outputs
    print("\nReloading modified model to verify...")
    cam_model = ct.models.MLModel(OUTPUT_MODEL_PATH)
    cam_spec = cam_model.get_spec()
    print(f"  Pipeline outputs: {[o.name for o in cam_spec.description.output]}")


if __name__ == "__main__":
    main()
