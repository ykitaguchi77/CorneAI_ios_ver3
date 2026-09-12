//
//  GradCAMOverlayView.swift
//  CorneAI_ios_ver3
//
//  SwiftUI component that overlays a GradCAM heatmap on the camera feed.
//

import SwiftUI

struct GradCAMOverlayView: View {
    let heatmap: UIImage?

    var body: some View {
        if let heatmap = heatmap {
            Image(uiImage: heatmap)
                .resizable()
                .interpolation(.high)   // 80x80 のヒートマップを滑らかに拡大する
                .scaledToFit()
                .allowsHitTesting(false)
        }
    }
}
