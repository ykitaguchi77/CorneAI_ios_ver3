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
    var handler: ((CMSampleBuffer) -> Void)?

    override init() {
        super.init()
        setup()
    }

    func setup() {
        captureSession.beginConfiguration()
        let device = defaultCamera() //使用するカメラは後のfuncで定義
//        let device = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back)
        
        guard
            let deviceInput = try? AVCaptureDeviceInput(device: device!),
            captureSession.canAddInput(deviceInput)
            else { return }
        captureSession.addInput(deviceInput)
        
        

        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "mydispatchqueue"))
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


    
    func run(_ handler: @escaping (CMSampleBuffer) -> Void)  {
        if !captureSession.isRunning {
            self.handler = handler
            DispatchQueue.global(qos: .background).async {
                self.captureSession.startRunning()
            }

        }
    }

    func stop() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
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


