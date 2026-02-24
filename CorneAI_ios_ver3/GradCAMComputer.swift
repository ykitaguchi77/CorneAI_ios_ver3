//
//  GradCAMComputer.swift
//  CorneAI_ios_ver3
//
//  Core CAM (Class Activation Map) computation engine.
//  Uses the modified last_cam model to extract intermediate feature maps,
//  then computes class-discriminative heatmaps using precomputed 1x1 Conv weights.
//
//  Performance: ~30-60ms total (model forward + vDSP weighted sum + colormap)
//  well within the 500ms inference timer budget.
//

import CoreML
import UIKit
import Accelerate

struct GradCAMResult {
    let classIndex: Int
    let confidenceText: String
    let heatmap: UIImage?
}

class GradCAMComputer {
    private let camModel: MLModel
    private let weights: GradCAMWeights
    private let inputSize = CGSize(width: 640, height: 640)
    // Use P3 resolution (80x80) as the target heatmap size before upsampling
    private let targetH = 80
    private let targetW = 80

    init?() {
        guard let weights = GradCAMWeights() else {
            print("[GradCAM] Failed to load cam_weights.json")
            return nil
        }
        self.weights = weights

        let config = MLModelConfiguration()
        guard let modelURL = Bundle.main.url(forResource: "last_cam", withExtension: "mlmodelc"),
              let model = try? MLModel(contentsOf: modelURL, configuration: config) else {
            print("[GradCAM] Failed to load last_cam model")
            return nil
        }
        self.camModel = model
    }

    /// Single inference pass that returns both classification result and GradCAM heatmap.
    func classifyWithCAM(image: UIImage) -> GradCAMResult? {
        guard let resized = image.resizeImageTo(size: inputSize),
              let buffer = resized.convertToBuffer() else {
            return nil
        }

        // Run prediction on the CAM model
        guard let input = try? MLDictionaryFeatureProvider(dictionary: [
            "image": MLFeatureValue(pixelBuffer: buffer),
            "iouThreshold": MLFeatureValue(double: 0.45),
            "confidenceThreshold": MLFeatureValue(double: 0.3)
        ]),
              let output = try? camModel.prediction(from: input) else {
            return nil
        }

        // Extract classification result
        guard let confidenceArray = output.featureValue(for: "confidence")?.multiArrayValue else {
            return nil
        }

        let length = confidenceArray.count
        guard length == 9 else {
            return GradCAMResult(
                classIndex: -1,
                confidenceText: "no cornea detected \n \n",
                heatmap: nil
            )
        }

        // Parse confidences and find top class
        var array: [Double] = []
        var topIndex = 0
        var topValue: Double = -1
        for i in 0..<length {
            let val = Double(truncating: confidenceArray[[0, NSNumber(value: i)]])
            array.append(val)
            if val > topValue {
                topValue = val
                topIndex = i
            }
        }

        // Format confidence string (matching Yolov5Interference format)
        let classes = weights.classes
        var dict: [String: String] = [:]
        for i in 0..<length {
            dict[classes[i]] = String(format: "%.2f", array[i])
        }
        let sortData = dict.sorted { $0.1 > $1.1 }.map { $0 }[0...2]
        let confidenceText = sortData.map { (key, value) in
            "\(key) = \(String(format: "%.2f", Double(value)! * 100))%"
        }.joined(separator: "\n")

        // Extract bounding box for masking (normalized [0,1] coords: cx, cy, w, h)
        var bbox: CGRect? = nil
        if let coordsArray = output.featureValue(for: "coordinates")?.multiArrayValue,
           coordsArray.count >= 4 {
            let cx = Double(truncating: coordsArray[[0, 0]])
            let cy = Double(truncating: coordsArray[[0, 1]])
            let bw = Double(truncating: coordsArray[[0, 2]])
            let bh = Double(truncating: coordsArray[[0, 3]])
            bbox = CGRect(x: cx - bw / 2, y: cy - bh / 2, width: bw, height: bh)
        }

        // Compute CAM heatmap for top-1 class, masked to bbox
        let heatmap = computeHeatmapFromOutput(output: output, classIndex: topIndex,
                                                bbox: bbox, imageSize: image.size)

        return GradCAMResult(
            classIndex: topIndex,
            confidenceText: confidenceText,
            heatmap: heatmap
        )
    }

    // MARK: - Private CAM Computation

    /// - Parameter bbox: Normalized [0,1] bounding box (x, y, w, h). If provided, heatmap is masked outside this region.
    private func computeHeatmapFromOutput(output: MLFeatureProvider, classIndex: Int,
                                           bbox: CGRect?, imageSize: CGSize) -> UIImage? {
        var combinedMap: [Float]? = nil

        for (scaleIdx, scaleConfig) in weights.scales.enumerated() {
            guard let featureArray = output.featureValue(for: scaleConfig.featureName)?.multiArrayValue else {
                continue
            }

            let w = weights.weights(forClass: classIndex, scale: scaleIdx)
            let h = scaleConfig.spatialH
            let fw = scaleConfig.spatialW
            let channels = scaleConfig.channels

            // Compute weighted sum across channels using vDSP
            let scaleMap = computeWeightedSum(featureArray: featureArray, weights: w,
                                              channels: channels, spatialH: h, spatialW: fw)

            // Upsample to target resolution if needed
            let upsampledMap: [Float]
            if h != targetH || fw != targetW {
                upsampledMap = bilinearUpsample(scaleMap, fromH: h, fromW: fw, toH: targetH, toW: targetW)
            } else {
                upsampledMap = scaleMap
            }

            // Accumulate across scales
            if combinedMap == nil {
                combinedMap = upsampledMap
            } else {
                vDSP_vadd(combinedMap!, 1, upsampledMap, 1, &combinedMap!, 1,
                          vDSP_Length(targetH * targetW))
            }
        }

        guard var cam = combinedMap else { return nil }

        // Apply bbox mask before normalization so dynamic range is maximized within bbox
        if let bbox = bbox {
            applyBBoxMask(&cam, bbox: bbox, width: targetW, height: targetH)
        }

        // ReLU: clamp negative values to 0
        var zero: Float = 0
        vDSP_vthres(cam, 1, &zero, &cam, 1, vDSP_Length(cam.count))

        // Normalize to [0, 1]
        var maxVal: Float = 0
        vDSP_maxv(cam, 1, &maxVal, vDSP_Length(cam.count))
        if maxVal > 0 {
            vDSP_vsdiv(cam, 1, &maxVal, &cam, 1, vDSP_Length(cam.count))
        }

        return createHeatmapImage(from: cam, width: targetW, height: targetH, imageSize: imageSize)
    }

    /// Zero out CAM values outside the bounding box.
    /// bbox is in normalized [0,1] coordinates (x, y, width, height).
    private func applyBBoxMask(_ cam: inout [Float], bbox: CGRect, width: Int, height: Int) {
        let x1 = Int(max(0, bbox.minX * CGFloat(width)))
        let y1 = Int(max(0, bbox.minY * CGFloat(height)))
        let x2 = Int(min(CGFloat(width), bbox.maxX * CGFloat(width)))
        let y2 = Int(min(CGFloat(height), bbox.maxY * CGFloat(height)))

        for y in 0..<height {
            for x in 0..<width {
                if y < y1 || y >= y2 || x < x1 || x >= x2 {
                    cam[y * width + x] = 0
                }
            }
        }
    }

    private func computeWeightedSum(featureArray: MLMultiArray, weights: [Float],
                                     channels: Int, spatialH: Int, spatialW: Int) -> [Float] {
        let spatialSize = spatialH * spatialW
        var result = [Float](repeating: 0, count: spatialSize)

        if featureArray.dataType == .float32 {
            // Fast path: direct pointer access with vDSP
            let ptr = featureArray.dataPointer.bindMemory(to: Float.self,
                                                           capacity: channels * spatialSize)
            for k in 0..<channels {
                var w = weights[k]
                // result += w * feature[k, :, :]
                vDSP_vsma(ptr + k * spatialSize, 1, &w, result, 1, &result, 1,
                          vDSP_Length(spatialSize))
            }
        } else {
            // Fallback: element-by-element access (handles Float16 and other types)
            for k in 0..<channels {
                let w = weights[k]
                let offset = k * spatialSize
                for i in 0..<spatialSize {
                    result[i] += w * featureArray[offset + i].floatValue
                }
            }
        }

        return result
    }

    // MARK: - Bilinear Upsampling

    private func bilinearUpsample(_ input: [Float], fromH: Int, fromW: Int,
                                   toH: Int, toW: Int) -> [Float] {
        var output = [Float](repeating: 0, count: toH * toW)
        let scaleH = Float(fromH) / Float(toH)
        let scaleW = Float(fromW) / Float(toW)

        for y in 0..<toH {
            for x in 0..<toW {
                let srcY = Float(y) * scaleH
                let srcX = Float(x) * scaleW

                let y0 = min(Int(srcY), fromH - 1)
                let y1 = min(y0 + 1, fromH - 1)
                let x0 = min(Int(srcX), fromW - 1)
                let x1 = min(x0 + 1, fromW - 1)

                let fy = srcY - Float(y0)
                let fx = srcX - Float(x0)

                output[y * toW + x] =
                    input[y0 * fromW + x0] * (1 - fy) * (1 - fx) +
                    input[y1 * fromW + x0] * fy * (1 - fx) +
                    input[y0 * fromW + x1] * (1 - fy) * fx +
                    input[y1 * fromW + x1] * fy * fx
            }
        }
        return output
    }

    // MARK: - JET Colormap & Image Generation

    private func createHeatmapImage(from cam: [Float], width: Int, height: Int, imageSize: CGSize) -> UIImage? {
        let pixelCount = width * height
        var pixelData = [UInt8](repeating: 0, count: pixelCount * 4)  // RGBA

        for i in 0..<pixelCount {
            let val = cam[i]
            let (rf, gf, bf) = jetColormapFloat(val)
            // Graduated alpha: transparent at low values, opaque at high
            let alphaF: Float = val > 0.05 ? min(1.0, val * 0.78 + 0.12) : 0
            // Premultiply RGB by alpha (required for premultipliedLast format)
            pixelData[i * 4 + 0] = UInt8(rf * alphaF * 255)
            pixelData[i * 4 + 1] = UInt8(gf * alphaF * 255)
            pixelData[i * 4 + 2] = UInt8(bf * alphaF * 255)
            pixelData[i * 4 + 3] = UInt8(alphaF * 255)
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
              let cgImage = context.makeImage() else {
            return nil
        }

        // Resize heatmap to match the original image size
        UIGraphicsBeginImageContextWithOptions(imageSize, false, 0)
        UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: imageSize))
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return result
    }

    /// JET colormap: blue (low) -> cyan -> green -> yellow -> red (high)
    /// Returns Float RGB in [0, 1] for premultiplied alpha compositing.
    private func jetColormapFloat(_ value: Float) -> (Float, Float, Float) {
        let v = max(0, min(1, value))
        var r: Float = 0, g: Float = 0, b: Float = 0

        if v < 0.125 {
            b = 0.5 + v * 4.0
        } else if v < 0.375 {
            b = 1.0
            g = (v - 0.125) * 4.0
        } else if v < 0.625 {
            g = 1.0
            b = 1.0 - (v - 0.375) * 4.0
            r = (v - 0.375) * 4.0
        } else if v < 0.875 {
            r = 1.0
            g = 1.0 - (v - 0.625) * 4.0
        } else {
            r = 1.0 - (v - 0.875) * 2.0
        }

        return (r, g, b)
    }
}
