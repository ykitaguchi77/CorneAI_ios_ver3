//
//  RealTimeView.swift
//  CorneAI_ios_ver2
//
//  Created by Yoshiyuki Kitaguchi on 2023/01/01.
//

import SwiftUI
import CoreML
import AVFoundation


struct RealTimeView: View {
    // define model
    let model = try? last(configuration: MLModelConfiguration())

    @ObservedObject var user: User
    @State private var image: UIImage?
    @State private var isStreaming: Bool = true
    @State var showAlert = false
    @State var samplePhotos = ["infection", "normal", "non-infection", "scar", "tumor", "deposit", "APAC", "lens-opacity", "bullous"]
    @State var result: (String, [Double]) = ("", [0,0,0,0]) //confidence, coordinate
    let videoCapture = VideoCapture()
    
    @State private var rect: CGRect = .zero //スクリーンショット用
    @State var screenImage: UIImage? = nil //スクリーンショット用
    @State var timer: Timer? //結果を0.5秒間隔で出力するためのタイマー
    @State var inferenceResult: String = ""

    
    var body: some View {
        VStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
            
            //show results
            if image != nil {
                Text("\(inferenceResult)")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.bottom)
                    .onAppear(perform: startInferenceTimer)
            }
//            if image != nil {
//                Text("\(Yolov5Interference(image: image!).classify().0)")
//                    .font(.title)
//                    .fontWeight(.bold)
//                    .padding(.bottom)
//            }
            
            //screenshot button
            if image != nil {
                Button("screenshot"){
                    //classifyImage(image: image!)
                    self.screenImage = UIApplication.shared.windows[0].rootViewController?.view!.getImage(rect: self.rect) //ここがうまくいっていない
                    UIImageWriteToSavedPhotosAlbum(screenImage!, nil, nil, nil)
                    //print("screenshot done!")
                }
                .font(.largeTitle)
            }
            

            
        }
        .onAppear{
            videoCapture.run { sampleBuffer in
                if let convertImage = UIImageFromSampleBuffer(sampleBuffer) {
                    DispatchQueue.main.async {
                        self.image = convertImage
                    }
                }
            }
        }
        .onDisappear(perform: videoCapture.stop)
        .background(RectangleGetter(rect: $rect))
    }

    func UIImageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let imageRect = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
            let context = CIContext()
            if let image = context.createCGImage(ciImage, from: imageRect) {
                let cropped = image.cropToSquare()
                //classifyImage(image: UIImage(cgImage: cropped))
                return UIImage(cgImage: cropped)
            }
        }
        return nil
    }
    

    func startInferenceTimer() {
        // もしすでにタイマーが起動していた場合は停止する
        timer?.invalidate()

        // 0.5秒ごとに推論を行うタイマーを起動する
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            inferenceResult = Yolov5Interference(image: image!).classify().0
        }
    }


//    private func classifyImage(image: UIImage) {
//        //let image = UIImage(named: "aaa")
//        guard let resizedImage = image.resizeImageTo(size:CGSize(width: 640, height: 640)),
//              let buffer = resizedImage.convertToBuffer() else {
//              return
//        }
//
//        print("aaa")
//
//        let output = try? model!.prediction(image: buffer, iouThreshold: 0.45, confidenceThreshold: 0.3)
//        let confidence = output?.confidence
//        let coordinates = output?.coordinates
//        print("confidence: \(String(describing: confidence)), coordinates: \(String(describing: coordinates))")
//
//
//        if let output = output {
//            let confidence = output.confidence
//            let coordinates = output.coordinates
//            print("confidence: \(confidence), coordinates: \(coordinates)")
//        }
//    }
}






