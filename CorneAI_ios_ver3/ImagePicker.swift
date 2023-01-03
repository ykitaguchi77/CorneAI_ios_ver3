//
//  ImagePicker.swift
//  CorneaApp
//
//  Created by Yoshiyuki Kitaguchi on 2021/12/03.
//  https://tomato-develop.com/swiftui-how-to-use-camera-and-select-photos-from-library/
//
// movie acquision:
//https://hatsunem.hatenablog.com/entry/2018/12/04/004823
//https://off.tokyo/blog/how-to-access-info-plist/
//https://ichi.pro/swift-uiimagepickercontroller-250133769115456
//正方形動画撮影　https://superhahnah.com/swift-square-av-capture/
 
import SwiftUI
import UIKit
 
struct ImagePicker: UIViewControllerRepresentable {
    
    @Binding var sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) private var presentationMode
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<ImagePicker>) -> UIImagePickerController {
        
        let imagePicker = UIImagePickerController()
        imagePicker.allowsEditing = false
        imagePicker.sourceType = sourceType
        imagePicker.delegate = context.coordinator
        imagePicker.mediaTypes = ["public.image"]
        
        if self.sourceType == .camera{
            imagePicker.cameraCaptureMode = .photo
            imagePicker.videoQuality = .typeHigh
            imagePicker.cameraFlashMode = .on
            imagePicker.cameraDevice = .rear //or front
            let screenWidth = UIScreen.main.bounds.size.width
            imagePicker.cameraOverlayView = RectangleView(frame: CGRect(x: 0, y: screenWidth*0.28, width: screenWidth, height: screenWidth)) //overlay
        }
        else if self.sourceType == .photoLibrary{
            //imagePicker.sourceType = sourceType
        }
        
        return imagePicker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: UIViewControllerRepresentableContext<ImagePicker>) {
        
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }
    
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        
        var parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            
            let image = info[.originalImage] as? UIImage
            //let data = image!.pngData()
            
            // .cameraで撮影した時のみカメラロールに保存
            if parent.sourceType == .camera{
                UIImageWriteToSavedPhotosAlbum(image!, nil,nil,nil) //カメラロールに保存
            }
            
            let cgImage = image!.cgImage //CGImageに変換
            let cropped = cgImage!.cropToSquare()
            
            //imageOrientationに従って向きを補正
            let imageOrientation = getImageOrientation()
            let rawImage = UIImage(cgImage: cropped).rotatedBy(orientation: imageOrientation)
            parent.selectedImage = rawImage
            
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}


class RectangleView: UIView {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = UIColor.clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ rect: CGRect) {
        if let context = UIGraphicsGetCurrentContext() {
            context.setLineWidth(3.0)
            UIColor.red.set()
            
            let width = frame.size.width
            
            context.addRect(CGRect(origin:CGPoint(x:0, y:0), size: CGSize(width:width, height:width)))
            
            //Elllipse
            UIColor.blue.set()
            context.addEllipse(in: CGRect(x:width*3/10, y:width*30/96, width:width*2/5, height:width*2/5))
            
            context.strokePath()
        }
    }
}
