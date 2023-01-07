//
//  UploadView.swift
//  CorneAI_ios_ver2
//
//  Created by Yoshiyuki Kitaguchi on 2023/01/01.
//

import SwiftUI
import CoreML

struct UploadView: View {
    @ObservedObject var user: User
    @State private var image: UIImage?
    @State var showingImagePicker = false
    @State var sourceType:  UIImagePickerController.SourceType = .camera
    @State var currentIndex: Int = 0
    @State var samplePhotos = ["infection", "normal", "non-infection", "scar", "tumor", "deposit", "APAC", "lens-opacity", "bullous"]
    @State var result: (String, [Double]) = ("", [0,0,0,0]) //confidence, coordinate
    let model = try? last(configuration: MLModelConfiguration())
    
    @State private var rect: CGRect = .zero //スクリーンショット用
    @State var screenImage: UIImage? = nil //スクリーンショット用
    
    
    var body: some View {
        GeometryReader{geometry in
            VStack {
                if image == nil{
                    Image(user.samplePhotos[currentIndex], bundle: .main)
                        .resizable()
                        .frame(width: geometry.size.width*0.9, height: geometry.size.width*0.65)
                } else {
                    if let uiImage = image {
                        Image(uiImage: image!.cropSquare(image: uiImage))
                            .resizable()
                            .frame(width: geometry.size.width*0.9, height: geometry.size.width*0.9)
                    }
                }
                Spacer().frame(height: 32)
                
                
                
                HStack{
                    Button(action: {
                        sourceType = .camera
                        showingImagePicker = true /*またはself.show.toggle() */
                    }) {
                        HStack{
                            Image(systemName: "camera")
                            Text("Take Photo")
                        }
                        .foregroundColor(Color.white)
                        .font(Font.largeTitle)
                    }
                    .frame(minWidth:0, maxWidth:CGFloat.infinity, minHeight: 50)
                    .background(Color.black)
                    .padding()
                    
                    Button(action: {
                        sourceType = .photoLibrary
                        showingImagePicker = true /*またはself.show.toggle() */
                        
                    }) {
                        HStack{
                            Image(systemName: "folder")
                            Text("Up")
                        }
                        .foregroundColor(Color.white)
                        .font(Font.largeTitle)
                    }
                    .frame(minWidth:0, maxWidth:200, minHeight: 50)
                    .background(Color.black)
                    .padding()
                }
                    
                HStack{
                    Button(action: {
                        if self.currentIndex < self.samplePhotos.count - 1 {
                            self.currentIndex = self.currentIndex + 1
                        } else {
                            self.currentIndex = 0
                        }
                    }){
                        Text("sample")
                    }
                    .padding()
                    .foregroundColor(Color.white)
                    .background(Color.gray)
                    
                    //Interference
                    Button(action: {
                        if image == nil{
                            let yolov5Interference = Yolov5Interference(image: UIImage(imageLiteralResourceName: samplePhotos[currentIndex]))
                            result = yolov5Interference.classify()
                        } else {
                            let yolov5Interference = Yolov5Interference(image: image!)
                            result = yolov5Interference.classify()
                        }
                        
                    }){
                        Text("classify")
                    }
                    .padding()
                    .foregroundColor(Color.white)
                    .background(Color.green)
                    

                    Button(action: {
                        if image != nil{
                            let rotatedImage = image!.rotatedBy(degree: 270)
                            image = rotatedImage
                            print("rotated!")
                            //countUp(rotate: rotate)
                        }
                    }
                    ) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(Color.white)
                            .font(Font.largeTitle)
                    }
                    .frame(minWidth:0, maxWidth:geometry.size.width*0.25, minHeight: 50)
                    .background(Color.black)
                    .padding()
                    
                }
                
                //show results
                Text("\(result.0)")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.bottom)
                
                //screenshot button
                if image != nil {
                    Button("screenshot"){
                        //classifyImage(image: image!)
                        self.screenImage = UIApplication.shared.windows[0].rootViewController?.view!.getImage(rect: self.rect) //ここがうまくいっていない
                        UIImageWriteToSavedPhotosAlbum(screenImage!, nil, nil, nil)
                        //print("screenshot done!")
                    }
                }
                
                
            }.sheet(isPresented: $showingImagePicker) {
                ImagePicker(sourceType: self.$sourceType, selectedImage: $image)
        }
        }
        .background(RectangleGetter(rect: $rect))
    }
}



