//
//  VideoCapture.swift
//  CorneAI_ios_ver3
//
//  Created by Yoshiyuki Kitaguchi on 2023/01/05.
//
import Foundation
import AVFoundation

class VideoCapture: NSObject {
    let captureSession = AVCaptureSession()
    private var handler: ((CMSampleBuffer) -> Void)?

    /// セッションの設定・開始・停止はすべてこのキュー上で行う。
    /// メインスレッドで startRunning/stopRunning すると UI が数百 ms 止まる。
    private let sessionQueue = DispatchQueue(label: "corneai.camera.session")
    /// フレーム配信用。推論結果の表示を待たせないよう userInitiated にする。
    private let frameQueue = DispatchQueue(label: "corneai.camera.frames", qos: .userInitiated)

    override init() {
        super.init()
        sessionQueue.async {
            self.setup()
        }
    }

    private func setup() {
        captureSession.beginConfiguration()
        let device = defaultCamera() //使用するカメラは後のfuncで定義
//        let device = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back)
        
        guard
            let deviceInput = try? AVCaptureDeviceInput(device: device!),
            captureSession.canAddInput(deviceInput)
            else { return }
        captureSession.addInput(deviceInput)
        
        

        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.setSampleBufferDelegate(self, queue: frameQueue)
        videoDataOutput.alwaysDiscardsLateVideoFrames = true

        guard captureSession.canAddOutput(videoDataOutput) else { return }
        captureSession.addOutput(videoDataOutput)

        // アウトプットの画像を縦向きに変更（標準は横）
        for connection in videoDataOutput.connections {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }

        captureSession.commitConfiguration()
    }


    
    func updateOrientation(_ orientation: AVCaptureVideoOrientation) {
        sessionQueue.async {
            for output in self.captureSession.outputs {
                for connection in output.connections {
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = orientation
                    }
                }
            }
        }
    }

    /// フレームごとに handler を呼ぶ(frameQueue 上で実行される)
    func run(_ handler: @escaping (CMSampleBuffer) -> Void)  {
        // handler は delegate と同じ frameQueue 上で読み書きしてデータ競合を避ける
        frameQueue.async { self.handler = handler }
        sessionQueue.async {
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
        frameQueue.async { self.handler = nil }
    }
    
    func defaultCamera() -> AVCaptureDevice? {
        if let device = AVCaptureDevice.default(.builtInUltraWideCamera,
                                                for: AVMediaType.video,
                                                position: .back) {
            print(device)
            return device
        } else if let device = AVCaptureDevice.default(.builtInDualCamera,
                            for: AVMediaType.video,
                            position: .back) {
            print(device)
            return device
        } else if let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                            for: AVMediaType.video,
                            position: .back) {
            print(device)
            return device
        } else if let device = AVCaptureDevice.default(.builtInTrueDepthCamera,
                                                       for: AVMediaType.video,
                                                       position: .front){
            print(device)
            return device
        } else {
            return nil
        }
    }
    

    func ledFlash(flg: Bool){
        let avDevice = AVCaptureDevice.default(for: AVMediaType.video)!
        if avDevice.hasTorch {
            do {
                // torch device lock on
                try avDevice.lockForConfiguration()
                
                if (flg){
                    // flash LED ON
                    avDevice.torchMode = AVCaptureDevice.TorchMode.on
                } else {
                    // flash LED OFF
                    avDevice.torchMode = AVCaptureDevice.TorchMode.off
                }
                // torch device unlock
                avDevice.unlockForConfiguration()
            } catch {
                print("Torch could not be used")
            }
        } else {
            print("Torch is not available")
        }
    }
    
}

extension VideoCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if let handler = handler {
            handler(sampleBuffer)
        }
    }
    
}


