//
//  UIImageExtension.swift
//  PtosisApp
//
//  Created by Yoshiyuki Kitaguchi on 2021/12/07.
//
import SwiftUI
 
extension UIImage {
    func resize(size _size: CGSize) -> UIImage? {
        let widthRatio = _size.width / size.width
        let heightRatio = _size.height / size.height
        let ratio = widthRatio < heightRatio ? widthRatio : heightRatio
 
        let resizedSize = CGSize(width: size.width * ratio, height: size.height * ratio)
 
        // UIGraphicsBeginImageContextWithOptions(resizedSize, false, 0.0) // 変更
        UIGraphicsBeginImageContext(resizedSize)
        draw(in: CGRect(origin: .zero, size: resizedSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
 
        return resizedImage
    }
    
    func resizeFill(size _size: CGSize) -> UIImage? {
        let widthRatio = _size.width / size.width
        let heightRatio = _size.height / size.height
        let ratio = widthRatio > heightRatio ? widthRatio : heightRatio
 
        let resizedSize = CGSize(width: size.width * ratio, height: size.height * ratio)
 
        // UIGraphicsBeginImageContextWithOptions(resizedSize, false, 0.0) // 変更
        UIGraphicsBeginImageContext(resizedSize)
        draw(in: CGRect(origin: .zero, size: resizedSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
 
        return resizedImage
    }
    
    func crop(to rect: CGRect) -> UIImage? {
        let croppingRect: CGRect = imageOrientation.isLandscape ? rect.switched : rect
        guard let cgImage: CGImage = self.cgImage?.cropping(to: croppingRect) else { return nil }
        let cropped: UIImage = UIImage(cgImage: cgImage, scale: scale, orientation: imageOrientation)
        return cropped
    }
    
    func rotatedBy(degree: CGFloat, isCropped: Bool = true) -> UIImage {
        let radian = -degree * CGFloat.pi / 180
        var rotatedRect = CGRect(origin: .zero, size: self.size)
        if !isCropped {
            rotatedRect = rotatedRect.applying(CGAffineTransform(rotationAngle: radian))
        }
        UIGraphicsBeginImageContext(rotatedRect.size)
        let context = UIGraphicsGetCurrentContext()!
        context.translateBy(x: rotatedRect.size.width / 2, y: rotatedRect.size.height / 2)
        context.scaleBy(x: 1.0, y: -1.0)
 
        context.rotate(by: radian)
        context.draw(self.cgImage!, in: CGRect(x: -(self.size.width / 2), y: -(self.size.height / 2), width: self.size.width, height: self.size.height))
 
        let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return rotatedImage
    }
    
    func rotatedBy(orientation: UIImage.Orientation, isCropped: Bool = true) -> UIImage {
        var image = self
        switch orientation{
        case UIImage.Orientation.up:
            image = self.rotatedBy(degree: 0, isCropped: isCropped)
        case UIImage.Orientation.down:
            image = self.rotatedBy(degree: 180, isCropped: isCropped)
        case UIImage.Orientation.left:
            image = self.rotatedBy(degree: -90, isCropped: isCropped)
        case UIImage.Orientation.right:
            image = self.rotatedBy(degree: 90, isCropped: isCropped)
        default:
            print("rotated uiimage unknown orientation")
            break
        }
        return image
    }
    
    func flipVertical() -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        let imageRef = self.cgImage
        let context = UIGraphicsGetCurrentContext()
        context?.translateBy(x: 0, y:  0)
        context?.scaleBy(x: 1.0, y: 1.0)
        context?.draw(imageRef!, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        let flipHorizontalImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return flipHorizontalImage!
    }
    
    func flipHorizontal() -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        let imageRef = self.cgImage
        let context = UIGraphicsGetCurrentContext()
        context?.translateBy(x: size.width, y:  size.height)
        context?.scaleBy(x: -1.0, y: -1.0)
        context?.draw(imageRef!, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        let flipHorizontalImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return flipHorizontalImage!
    }
    
    func cropSquare(image:UIImage) -> UIImage {
        let cgImage = image.cgImage
        return UIImage(cgImage: cgImage!.cropToSquare())
    }
}
 
extension UIImage.Orientation {
    /// 画像が横向きであるか
    var isLandscape: Bool {
        switch self {
        case .up, .down, .upMirrored, .downMirrored:
            return false
        case .left, .right, .leftMirrored, .rightMirrored:
            return true
        default:
            return false
        }
    }
}
 
 
extension CGImage {
    var data: Data? {
        guard let mutableData = CFDataCreateMutable(nil, 0),
            let destination = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, self, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }
    
    func cropToSquare() -> CGImage {
        let rectlength = min(self.width, self.height)
        //最後に回転させるので縦横が逆になる
        let left = (self.width - rectlength) / 2
        //let left = 0
        let top = (self.height - rectlength) / 2
        let croppingRect = CGRect(x: left, y: top, width: rectlength, height: rectlength)
        let croppedImage = self.cropping(to: croppingRect)!
        return croppedImage
    }
}
 
 
func getImageOrientation() -> UIImage.Orientation{
    var imageOrientation = UIImage.Orientation.up
        
    switch UIApplication.shared.windows.first?.windowScene?.interfaceOrientation{
    case .portrait:
        imageOrientation = UIImage.Orientation.right
    case .portraitUpsideDown:
        imageOrientation = UIImage.Orientation.left
    case .landscapeLeft:
        imageOrientation = UIImage.Orientation.down
    case .landscapeRight:
        imageOrientation = UIImage.Orientation.up
    default:
        print("taken image unknown orientation")
        break
    }
    
    return imageOrientation
}
 
extension CGRect {
    /// 反転させたサイズを返す
    var switched: CGRect {
        return CGRect(x: minY, y: minX, width: height, height: width)
    }
}
 
public func GetImageStack(images: [UIImage], shorterSide: CGFloat) -> some View {
        let padding: CGFloat = 10.0
        let imageLength = shorterSide / 3 + padding * 2
        let colCount = Int(shorterSide / imageLength)
        let rowCount = Int(ceil(Float(images.count) / Float(colCount)))
        return VStack(alignment: .leading) {
            ForEach(0..<rowCount){
                i in
                HStack{
                    ForEach(0..<colCount){
                        j in
                        if (i * colCount + j < images.count){
                            let image = images[i * colCount + j]
                            Image(uiImage: image).resizable().frame(width: imageLength*2.4, height: imageLength*2.4).padding(padding)
                        }
                    }
                }
            }
        }
        .border(Color.black)
    }
 
 
public func GetShorterSide(screenSize: CGSize) -> CGFloat{
    let shorterSide = (screenSize.width < screenSize.height) ? screenSize.width : screenSize.height
    return shorterSide
}
 
