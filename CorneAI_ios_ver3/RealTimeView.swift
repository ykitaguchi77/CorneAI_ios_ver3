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

    // GradCAM
    @State private var isGradCAMEnabled: Bool = false
    @State private var gradcamImage: UIImage? = nil
    private let gradcamComputer: GradCAMComputer? = GradCAMComputer()

    @Environment(\.verticalSizeClass) var verticalSizeClass

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                landscapeLayout
            } else {
                portraitLayout
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
        .onChange(of: verticalSizeClass) { newValue in
            if newValue == .compact {
                videoCapture.updateOrientation(.landscapeRight)
            } else {
                videoCapture.updateOrientation(.portrait)
            }
        }
    }

    // MARK: - Portrait Layout (元のまま)
    var portraitLayout: some View {
        VStack {
            ZStack {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()

                    if isGradCAMEnabled {
                        GradCAMOverlayView(heatmap: gradcamImage)
                    }
                }
            }

            if image != nil {
                Text("\(inferenceResult)")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.bottom)
                    .onAppear(perform: startInferenceTimer)
            }

            if image != nil {
                HStack {
                    Button("screenshot"){
                        self.screenImage = UIApplication.shared.windows[0].rootViewController?.view!.getImage(rect: self.rect)
                        UIImageWriteToSavedPhotosAlbum(screenImage!, nil, nil, nil)
                    }
                    .font(.largeTitle)

                    Spacer()

                    gradcamToggleButton
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Landscape Layout
    var landscapeLayout: some View {
        HStack(spacing: 0) {
            // 左: GradCAMマージ画像(カメラ+ヒートマップ)
            ZStack {
                if isGradCAMEnabled, let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                    GradCAMOverlayView(heatmap: gradcamImage)
                } else {
                    Color.gray.opacity(0.15)
                        .overlay(
                            VStack(spacing: 2) {
                                Text("GradCAM").font(.caption).foregroundColor(.gray)
                                Text("OFF").font(.caption2).foregroundColor(.gray)
                            }
                        )
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipped()
            .padding(.leading, 4)

            // 中央: 素のカメラ映像
            ZStack {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipped()
            .onAppear(perform: startInferenceTimer)
            .padding(.horizontal, 4)

            // 右: Prediction + ボタン
            VStack(alignment: .leading, spacing: 6) {
                Text(inferenceResult)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(nil)

                Spacer()

                HStack(spacing: 8) {
                    gradcamToggleButton

                    Button(action: {
                        self.screenImage = UIApplication.shared.windows[0].rootViewController?.view!.getImage(rect: self.rect)
                        UIImageWriteToSavedPhotosAlbum(screenImage!, nil, nil, nil)
                    }) {
                        Image(systemName: "camera.fill")
                            .font(.title3)
                            .padding(6)
                            .background(Color.blue.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.trailing, 8)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Shared Components
    var gradcamToggleButton: some View {
        Button(action: {
            isGradCAMEnabled.toggle()
            if !isGradCAMEnabled {
                gradcamImage = nil
            }
        }) {
            Text("GradCAM")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isGradCAMEnabled ? Color.red.opacity(0.6) : Color.gray.opacity(0.4))
                .foregroundColor(.white)
                .cornerRadius(8)
        }
    }

    func UIImageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let imageRect = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
            let context = CIContext()
            if let image = context.createCGImage(ciImage, from: imageRect) {
                let cropped = image.cropToSquare()
                return UIImage(cgImage: cropped)
            }
        }
        return nil
    }

    func startInferenceTimer() {
        timer?.invalidate()

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            guard let currentImage = image else { return }

            if isGradCAMEnabled, let computer = gradcamComputer {
                if let result = computer.classifyWithCAM(image: currentImage) {
                    inferenceResult = result.confidenceText
                    gradcamImage = result.heatmap
                }
            } else {
                inferenceResult = Yolov5Interference(image: currentImage).classify().0
                gradcamImage = nil
            }
        }
    }
}
