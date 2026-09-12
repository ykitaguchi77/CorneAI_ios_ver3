//
//  CornealClassifier.swift
//  CorneAI_ios_ver3
//
//  last モデルによる分類。旧 Yolov5Interference の後継。
//  モデルは ModelStore が 1 回だけロードして注入するため、このクラス自体は軽量に生成できる。
//

import CoreML
import UIKit

final class CornealClassifier {
    static let inputSize = CGSize(width: 640, height: 640)
    private let model: last

    init(model: last) {
        self.model = model
    }

    /// 旧 Yolov5Interference.classify() と同じ前処理(resizeImageTo → convertToBuffer)・後処理。
    /// 入力画像が同じなら出力も同じになる。
    func classify(image: UIImage) -> (confidence: String, coordinates: [Double]) {
        guard let resized = image.resizeImageTo(size: Self.inputSize),
              let buffer = resized.convertToBuffer(),
              let output = try? model.prediction(image: buffer, iouThreshold: 0.45, confidenceThreshold: 0.3) else {
            return (ClassificationFormatter.noDetectionMessage, [0, 0, 0, 0])
        }
        return (ClassificationFormatter.confidenceText(from: output.confidence),
                ClassificationFormatter.coordinates(from: output.coordinates))
    }
}
