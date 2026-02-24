//
//  GradCAMWeights.swift
//  CorneAI_ios_ver3
//
//  Loads precomputed detection head 1x1 Conv weights from cam_weights.json.
//  These weights are mathematically equivalent to GradCAM weights for 1x1 Conv layers.
//

import Foundation

struct GradCAMScaleConfig {
    let featureName: String
    let channels: Int
    let spatialH: Int
    let spatialW: Int
    let classWeights: [[Float]]  // [numClasses][channels]
}

class GradCAMWeights {
    let scales: [GradCAMScaleConfig]
    let classes: [String]

    init?() {
        guard let url = Bundle.main.url(forResource: "cam_weights", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scalesArray = json["scales"] as? [[String: Any]],
              let classNames = json["classes"] as? [String] else {
            return nil
        }

        self.classes = classNames
        var parsedScales: [GradCAMScaleConfig] = []

        for scaleDict in scalesArray {
            guard let featureName = scaleDict["feature_name"] as? String,
                  let channels = scaleDict["channels"] as? Int,
                  let spatial = scaleDict["spatial"] as? [Int],
                  spatial.count == 2,
                  let weightsDict = scaleDict["weights"] as? [String: [NSNumber]] else {
                continue
            }

            var classWeights: [[Float]] = []
            for c in 0..<classNames.count {
                if let w = weightsDict[String(c)] {
                    classWeights.append(w.map { $0.floatValue })
                } else {
                    classWeights.append([Float](repeating: 0, count: channels))
                }
            }

            parsedScales.append(GradCAMScaleConfig(
                featureName: featureName,
                channels: channels,
                spatialH: spatial[0],
                spatialW: spatial[1],
                classWeights: classWeights
            ))
        }

        guard !parsedScales.isEmpty else { return nil }
        self.scales = parsedScales
    }

    func weights(forClass classIndex: Int, scale scaleIndex: Int) -> [Float] {
        return scales[scaleIndex].classWeights[classIndex]
    }
}
