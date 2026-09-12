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
    @ObservedObject var user: User

    // カメラ・モデル・推論ループは engine が所有する。
    // @StateObject なので View がツリーに載ったときに 1 回だけ生成され、
    // ContentView の再描画(NavigationLink の destination 再評価)では作り直されない。
    @StateObject private var engine = RealTimeInferenceEngine()

    @State private var rect: CGRect = .zero //スクリーンショット用
    @State var screenImage: UIImage? = nil //スクリーンショット用

    // GradCAM
    @AppStorage("isGradCAMAvailable") private var isGradCAMAvailable: Bool = false //設定画面で切り替え(デフォルトは無効)
    @State private var isGradCAMEnabled: Bool = false

    @Environment(\.verticalSizeClass) var verticalSizeClass

    // 旧コードの `image` / `inferenceResult` / `gradcamImage` に対応
    private var image: UIImage? { engine.previewImage }
    private var inferenceResult: String { engine.resultText }
    private var gradcamImage: UIImage? { engine.heatmap }

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                landscapeLayout
            } else {
                portraitLayout
            }
        }
        .onAppear{
            //設定でGradCAMが無効なら、前回のオン状態を解除しておく
            if !isGradCAMAvailable {
                isGradCAMEnabled = false
            }
            engine.isGradCAMEnabled = isGradCAMEnabled
            engine.camera.updateOrientation(verticalSizeClass == .compact ? .landscapeRight : .portrait)
            engine.start()
        }
        .onDisappear {
            engine.stop()
        }
        .background(RectangleGetter(rect: $rect))
        .onChange(of: isGradCAMEnabled) { newValue in
            engine.isGradCAMEnabled = newValue
        }
        .onChange(of: verticalSizeClass) { newValue in
            if newValue == .compact {
                engine.camera.updateOrientation(.landscapeRight)
            } else {
                engine.camera.updateOrientation(.portrait)
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
            }

            if image != nil {
                HStack {
                    Button("screenshot"){
                        self.screenImage = UIApplication.shared.windows[0].rootViewController?.view!.getImage(rect: self.rect)
                        UIImageWriteToSavedPhotosAlbum(screenImage!, nil, nil, nil)
                    }
                    .font(.largeTitle)

                    Spacer()

                    if isGradCAMAvailable {
                        gradcamToggleButton
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Landscape Layout
    var landscapeLayout: some View {
        HStack(spacing: 0) {
            // 左: GradCAMマージ画像(カメラ+ヒートマップ)  ※設定で無効時は非表示
            if isGradCAMAvailable {
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
            }

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
                    if isGradCAMAvailable {
                        gradcamToggleButton
                    }

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
            isGradCAMEnabled.toggle()   // OFF 時のヒートマップ消去は engine 側で行う
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

}
