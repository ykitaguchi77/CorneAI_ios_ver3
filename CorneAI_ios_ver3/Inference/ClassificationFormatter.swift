//
//  ClassificationFormatter.swift
//  CorneAI_ios_ver3
//
//  モデル出力(MLMultiArray)を表示用文字列・座標配列へ変換する。
//  ロジックは旧 Yolov5Interference(InterferenceExtension.swift)から変更せずに移設したもの。
//  RealTime / Upload / GradCAM の全経路で共有し、出力の食い違いを防ぐ。
//

import CoreML

enum ClassificationFormatter {
    static let classes = ["infection", "normal", "non-infection", "scar", "tumor", "deposit", "APAC", "lens-opacity", "bullous"]
    static let noDetectionMessage = "no cornea detected \n \n"

    /// 上位3クラスを "class = xx.xx%" 形式で改行区切りにする(旧 convertToClass と同一)
    static func confidenceText(from mlMultiArray: MLMultiArray) -> String {
        // Init our output array
        var array: [Double] = []
        var dict: [String:String] = [:]
        // Get length
        let length = mlMultiArray.count
        if length == 9 {   //0でないことの確認、および時々処理の問題で18になりエラーになるのでチェック
            // Set content of multi array to our out put array
            for i in 0...length - 1 {
                array.append(Double(truncating: mlMultiArray[[0,NSNumber(value: i)]]))
            }

            //select Top3 indices and value
            for i in 0 ... length - 1 {
                dict.updateValue(String(format: "%.2f", array[i]), forKey: classes[i])
            }

            //sort array in ascending order and slice the top3
            let sortData = dict.sorted{ $0.1 > $1.1 } .map { $0 }[0...2]

            //output the result as string
            let message = sortData.map { (key, value) in
                "\(key) = \(String(format: "%.2f", Double(value)! * 100))%"
            }.joined(separator: "\n")
            return message

        } else {
            return noDetectionMessage
        }
    }

    /// 座標配列(旧 convertToCoordinates と同一)
    static func coordinates(from mlMultiArray: MLMultiArray) -> [Double] {
        // Init our output array
        var array: [Double] = []
        // Get length
        let length = mlMultiArray.count
        // Set content of multi array to our out put array
        if length != 0 {
            // Set content of multi array to our out put array
            for i in 0...length - 1 {
                array.append(Double(truncating: mlMultiArray[[0,NSNumber(value: i)]]))
            }} else {
                array = [0,0,0,0]
            }
            return array
    }

    /// 最大 confidence のクラス index(旧 findTopClassIndex と同一)。検出なしのときは -1
    static func topClassIndex(from mlMultiArray: MLMultiArray) -> Int {
        let length = mlMultiArray.count
        guard length == 9 else { return -1 }

        var topIndex = 0
        var topValue: Double = -1
        for i in 0..<length {
            let val = Double(truncating: mlMultiArray[[0, NSNumber(value: i)]])
            if val > topValue {
                topValue = val
                topIndex = i
            }
        }
        return topIndex
    }
}
