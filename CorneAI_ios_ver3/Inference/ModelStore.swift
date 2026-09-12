//
//  ModelStore.swift
//  CorneAI_ios_ver3
//
//  Core ML モデルをアプリ全体で 1 回だけロードして共有する。
//  View や推論オブジェクトがモデルを所有すると、View の再生成や推論のたびに
//  27MB のモデルロード(数百 ms + CPU バースト)が走るため、ここに集約する。
//

import CoreML
import os

enum ModelStore {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CorneAI", category: "ModelStore")

    /// 分類モデル(last)。初回アクセス時に 1 回だけロードされ、以降プロセス終了まで保持する。
    /// static let は swift_once で初期化されるためスレッド安全。
    static let classifier: CornealClassifier? = {
        log.info("Loading last.mlmodel")
        guard let model = try? last(configuration: MLModelConfiguration()) else {
            log.error("Failed to load last.mlmodel")
            return nil
        }
        return CornealClassifier(model: model)
    }()

    private static let gradCAMLock = NSLock()
    private static var gradCAMComputer: GradCAMComputer?
    private static var gradCAMLoadAttempted = false

    /// GradCAM 用モデル(last_cam)。GradCAM を初めてオンにしたときにロードし、以降保持する
    /// (オフにしても解放しない: 再オン時の待ち時間とロードの CPU コストを避けるため)。
    /// ロードに数百 ms かかるので推論スレッドから呼ぶこと。
    static func gradCAM() -> GradCAMComputer? {
        gradCAMLock.lock()
        defer { gradCAMLock.unlock() }
        if gradCAMComputer == nil && !gradCAMLoadAttempted {
            gradCAMLoadAttempted = true   // 失敗時に tick ごとの再ロードを繰り返さない
            log.info("Loading last_cam.mlmodel")
            gradCAMComputer = GradCAMComputer()
            if gradCAMComputer == nil {
                log.error("Failed to load last_cam.mlmodel")
            }
        }
        return gradCAMComputer
    }
}
