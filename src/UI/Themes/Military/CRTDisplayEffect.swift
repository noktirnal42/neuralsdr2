//
//  CRTDisplayEffect.swift
//  NeuralSDR2
//
//  Metal post-processing for military CRT displays
//

import SwiftUI
import MetalKit

public struct CRTDisplayEffect: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .drawingGroup() // Render to a buffer first
            .overlay(
                ZStack {
                    // Scanlines
                    Rectangle()
                        .fill(LinearGradient(
                            gradient: Gradient(colors: [.clear, .black.opacity(0.2), .clear]),
                            startPoint: .top, endPoint: .bottom
                        ))
                        .background(ScanlineOverlay())
                    
                    // Vignette / Curved edges
                    RadialGradient(
                        gradient: Gradient(colors: [.clear, .black.opacity(0.4)]),
                        center: .center,
                        startRadius: 200,
                        endRadius: 500
                    )
                    
                    // Phosphor Glow
                    Color.green.opacity(0.05)
                        .blendMode(.screen)
                }
            )
            .brightness(0.1)
            .contrast(1.2)
            .saturation(0) // Monochrome green
            .colorMultiply(.green)
    }
}

public struct ScanlineOverlay: View {
    public var body: some View {
        GeometryReader { geo in
            Path { path in
                let step: CGFloat = 4
                for y in stride(from: 0, to: geo.size.height, by: step) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }
            .stroke(Color.black.opacity(0.3), lineWidth: 1)
        }
    }
}

public extension View {
    func applyCRT() -> some View {
        self.modifier(CRTDisplayEffect())
    }
}
