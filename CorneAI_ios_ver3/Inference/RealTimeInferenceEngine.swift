//
//  RealTimeInferenceEngine.swift
//  CorneAI_ios_ver3
//
//  RealTimeView のカメラ → 推論 → 結果表示を、View の寿命に紐づけて管理する。
//
//  以前は Timer(メインスレッド)が 0.5 秒ごとに Yolov5Interference を生成していたため
//    - tick ごとにモデルを再ロード
//    - Core ML 推論と CoreGraphics 前処理がメインスレッドを塞ぐ
//    - onDisappear で止まらず、画面を離れても推論が続く
//  という問題があった。ここでは
//    - モデルは ModelStore の共有インスタンスを使う
//    - 推論は InferenceWorker(actor)で直列にバックグラウンド実行
//    - 逐次 Task ループなので前回の推論が終わるまで次を始めない(溜まらない・重ならない)
//    - stop() で Task をキャンセルしカメラを止める
//

import SwiftUI
import AVFoundation
import CoreImage
import os

@MainActor
final class RealTimeInferenceEngine: ObservableObject {
    @Published private(set) var previewImage: UIImage?
    @Published private(set) var resultText: String = ""
    @Published private(set) var heatmap: UIImage?

    /// GradCAM の ON/OFF。OFF にしたらヒートマップは即座に消す(旧 gradcamToggleButton と同じ)
    var isGradCAMEnabled = false {
        didSet {
            if !isGradCAMEnabled { heatmap = nil }
        }
    }

    /// 結果を更新する周期(旧 Timer と同じ 0.5 秒)
    let interval: Duration = .milliseconds(500)

    let camera = VideoCapture()
    private let worker = InferenceWorker()
    private let latestFrame = LatestFrameBox()
    private var loop: Task<Void, Never>?
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CorneAI", category: "RealTime")

    /// カメラと推論ループを開始する。回転や onAppear の再発火で呼ばれても二重起動しない。
    func start() {
        guard loop == nil else { return }

        let latestFrame = self.latestFrame
        camera.run { [weak self] sampleBuffer in
            // カメラのキュー上で実行される
            guard let image = FrameConverter.squareImage(from: sampleBuffer) else { return }
            latestFrame.set(image)
            Task { @MainActor [weak self] in
                self?.previewImage = image
            }
        }

        loop = Task { [weak self] in
            await self?.runLoop()
        }
        Self.log.info("loop started")
    }

    /// 推論ループとカメラを止める。画面を離れた後は一切の処理が走らない。
    func stop() {
        loop?.cancel()
        loop = nil
        camera.stop()
        latestFrame.clear()
        Self.log.info("loop stopped")
    }

    private func runLoop() async {
        let clock = ContinuousClock()
        var next = clock.now
        while !Task.isCancelled {
            next += interval

            // 前回の tick 以降に新しいフレームが来ていなければ何もしない(カメラ停止中など)
            if let image = latestFrame.take() {
                let output = await worker.infer(image: image, wantHeatmap: isGradCAMEnabled)
                if Task.isCancelled { break }
                // 旧実装と同じく、GradCAM が nil を返したときは前回の表示を維持する
                if let output {
                    resultText = output.text
                    heatmap = isGradCAMEnabled ? output.heatmap : nil
                }
            }

            // 推論が interval を超えた場合は待たずに次へ進む(遅れを溜め込まない)
            try? await clock.sleep(until: max(next, clock.now))
        }
    }
}

// MARK: - InferenceWorker

/// Core ML 推論を直列にバックグラウンドで実行する。
/// actor なので last / last_cam の推論が同時に走ることはない。
actor InferenceWorker {
    struct Output {
        let text: String
        let heatmap: UIImage?
    }

    /// 旧 startInferenceTimer の tick 本体と同じ分岐。
    /// - GradCAM ON かつモデルあり: classifyWithCAM(nil なら nil を返し、表示は更新しない)
    /// - それ以外: 通常分類(ヒートマップなし)
    func infer(image: UIImage, wantHeatmap: Bool) -> Output? {
        if wantHeatmap, let computer = ModelStore.gradCAM() {   // 初回はここで last_cam をロード(メイン外)
            guard let result = computer.classifyWithCAM(image: image) else { return nil }
            return Output(text: result.confidenceText, heatmap: result.heatmap)
        }
        guard let classifier = ModelStore.classifier else {
            return Output(text: ClassificationFormatter.noDetectionMessage, heatmap: nil)
        }
        return Output(text: classifier.classify(image: image).confidence, heatmap: nil)
    }
}

// MARK: - LatestFrameBox

/// カメラキューから書き、推論ループから読む「最新フレーム 1 枚」の入れ物。
final class LatestFrameBox: @unchecked Sendable {
    private let lock = NSLock()
    private var image: UIImage?

    func set(_ image: UIImage) {
        lock.lock()
        self.image = image
        lock.unlock()
    }

    /// 取り出すと空になる。同じフレームを二度推論しない。
    func take() -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        let taken = image
        image = nil
        return taken
    }

    func clear() {
        lock.lock()
        image = nil
        lock.unlock()
    }
}

// MARK: - FrameConverter

enum FrameConverter {
    /// CIContext は生成コストが高い(Metal パイプライン構築)ので 1 個を使い回す。
    /// 以前はフレームごと(30fps)に生成しており、最大の電力消費源だった。CIContext はスレッド安全。
    private static let ciContext = CIContext()

    /// カメラフレームを正方形にクロップした UIImage にする(旧 UIImageFromSampleBuffer と同じ出力)
    static func squareImage(from sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let imageRect = CGRect(x: 0, y: 0,
                               width: CVPixelBufferGetWidth(pixelBuffer),
                               height: CVPixelBufferGetHeight(pixelBuffer))
        guard let cgImage = ciContext.createCGImage(ciImage, from: imageRect) else { return nil }
        return UIImage(cgImage: cgImage.cropToSquare())
    }
}
