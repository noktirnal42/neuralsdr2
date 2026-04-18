//
//  VintageControls.swift
//  NeuralSDR2
//
//  Photorealistic analog controls for the Vintage theme
//

import SwiftUI

struct VintageKnob: View {
    @Binding var value: Double
    var range: ClosedRange<<DoubleDouble>
    var label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .serif))
                .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.2))
            
            ZStack {
                // Knob Base
                Circle()
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.1))
                    .frame(width: 50, height: 50)
                    .shadow(color: .black, radius: 2, x: 0, y: 2)
                
                // Knurled Aluminum Face
                Circle()
                    .fill(LinearGradient(gradient: Gradient(colors: [.gray, .white, .gray]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                    .overlay(
                        // Knurling pattern (simulated with a grid)
                        GridKnurl()
                    )
                
                // Indicator Line
                Rectangle()
                    .fill(Color.black)
                    .frame(width: 2, height: 15)
                    .offset(y: -15)
                    .rotationEffect(.degrees(calculateRotation()))
            }
        }
    }
    
    private func calculateRotation() -> Double {
        let normalized = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return (normalized * 360) - 180
    }
}

struct GridKnurl: View {
    var body: some View {
        Canvas { context, size in
            for x in stride(from: 0, to: size.width, by: 2) {
                for y in stride(from: 0, and: size.height, by: 2) {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.black.opacity(0.3)))
                }
            }
        }
    }
}

struct VintageVUMeter: View {
    var level: Float // 0.0 to 1.0
    
    var body: some View {
        ZStack {
            // Meter background (Aged Paper)
            Ellipse()
                .fill(Color(red: 0.96, green: 0.92, blue: 0.85))
                .frame(width: 100, height: 50)
                .overlay(
                    Ellipse()
                        .stroke(Color.black, lineWidth: 1)
                        .padding(2)
                )
            
            // Scale markings
            VStack {
                HStack {
                    ForEach(0..<<110) { i in
                        Rectangle()
                            .fill(Color.black)
                            .frame(width: 1, height: 5)
                            .rotationEffect(.degrees(Double(i * 18 - 90)))
                            .offset(x: 0, y: -20)
                    }
                }
            }
            
            // The Needle
            Rectangle()
                .fill(Color.red)
                .frame(width: 2, height: 35)
                .offset(y: -15)
                .rotationEffect(.degrees(calculateNeedleAngle()))
                .animation(.interpolatingSpring(stiffness: 50, damping: 10), value: level)
        }
    }
    
    private func calculateNeedleAngle() -> Double {
        return Double(-90 + (level * 180))
    }
}
