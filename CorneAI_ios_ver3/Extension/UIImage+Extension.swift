//
//  UIImage+Extension.swift
//  CoreMLmeetsSwiftUI
//
//  Created by Moritz Philip Recke for Create with Swift on 10 February 2021.
//
 
import Foundation
import UIKit
 
extension UIImage {
    
    /// YOLOv5 標準の letterbox。アスペクト比を保って size に収め、余白を灰色(114,114,114)で埋める。
    /// 学習時と同じ前処理にすることで、視野を捨てず歪みも生じない。
    func letterboxed(to size: CGSize) -> UIImage? {

        let ratio = min(size.width / self.size.width, size.height / self.size.height)
        let newSize = CGSize(width: (self.size.width * ratio).rounded(),
                             height: (self.size.height * ratio).rounded())
        let origin = CGPoint(x: ((size.width - newSize.width) / 2).rounded(),
                             y: ((size.height - newSize.height) / 2).rounded())

        // scale は 1.0 を明示する。0.0 だとデバイススケール(3x)で描画され 1920x1920 を経由する
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        UIColor(red: 114.0/255.0, green: 114.0/255.0, blue: 114.0/255.0, alpha: 1.0).setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        self.draw(in: CGRect(origin: origin, size: newSize))
        let letterboxedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return letterboxedImage
    }

    func resizeImageTo(size: CGSize) -> UIImage? {
        
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        self.draw(in: CGRect(origin: CGPoint.zero, size: size))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return resizedImage
    }
    
     func convertToBuffer() -> CVPixelBuffer? {
        
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        var pixelBuffer: CVPixelBuffer?
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, Int(self.size.width),
            Int(self.size.height),
            kCVPixelFormatType_32ARGB,
            attributes,
            &pixelBuffer)
        
        guard (status == kCVReturnSuccess) else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        
        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer!)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        
        let context = CGContext(
            data: pixelData,
            width: Int(self.size.width),
            height: Int(self.size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!),
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        
        context?.translateBy(x: 0, y: self.size.height)
        context?.scaleBy(x: 1.0, y: -1.0)
        
        UIGraphicsPushContext(context!)
        self.draw(in: CGRect(x: 0, y: 0, width: self.size.width, height: self.size.height))
        UIGraphicsPopContext()
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        
        return pixelBuffer
    }
 
}
 
