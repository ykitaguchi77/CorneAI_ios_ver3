//
//  InterferenceExtension.swift
//  CorneAI_ios_ver2
//
//  Created by Yoshiyuki Kitaguchi on 2023/01/03.
//

import SwiftUI
import CoreML


class Yolov5Interference: ObservableObject {
    @Published var model = try? last(configuration: MLModelConfiguration())
    @Published var image: UIImage
    @Published var size = CGSize(width: 640, height: 640)
    @Published var classes = ["infection", "normal", "non-infection", "scar", "tumor", "deposit", "APAC", "lens-opacity", "bullous"]
    @Published var message = ""
    
    init(image: UIImage){
        self.image = image
    }
    
    func classify() -> (confidence: String, coordinates: [Double]){
        let resizedImage = self.image.resizeImageTo(size:size)
        let buffer = resizedImage!.convertToBuffer()
        
        let output = try? model!.prediction(image: buffer!, iouThreshold: 0.45, confidenceThreshold: 0.3)
        let confidence = convertToClass(from: output!.confidence)
        let coordinates = convertToCoordinates(from: output!.coordinates)
        //print("confidence: \(String(describing: confidence)), coordinates: \(String(describing: coordinates))")
        return (confidence, coordinates) //戻り値はtuple
    }
    
    func convertToClass(from mlMultiArray: MLMultiArray) -> String {
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
                dict.updateValue(String(array[i]), forKey: classes[i])
            }
            
            //sort array in ascending order and slice the top3
            let sortData = dict.sorted{ $0.1 > $1.1 } .map { $0 }[0...2]
            
            //output the result as string
            let message = sortData.map { (key, value) in
                "\(key) = \(String(format: "%.2f", Double(value)! * 100))%"
            }.joined(separator: "\n")
            return message
            
            } else {
                let message = "no cornea detected \n \n"
                return message
            }
    }
    
    func convertToCoordinates(from mlMultiArray: MLMultiArray) -> [Double] {
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
    
}
