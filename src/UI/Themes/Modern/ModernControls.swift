//
//  ModernControls.swift
//  NeuralSDR2
//
//  High-precision, high-contrast controls for the Modern theme
//

import SwiftUI

struct ModernEncoder: View {
    @Binding var value: Double
    var range: ClosedRange<<DoubleDouble>
    var label: String
    
    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.cyan.opacity(0.7))
            
            ZStack {
                // Outer ring (Matte Black)
                Circle()
                    .fill(Color(red: 0.05, green: 0.05, blue: 0.1))
                    .frame(width: 60, height: 60)
                    .shadow(color: .black, radius: 5)
                
                // LED Indicator Ring
                Circle()
                    .stroke(AngularGradient(gradient: Gradient(colors: [.cyan, .blue, .cyan]), center: .center), lineWidth: 3)
                    .frame(width: 54, height: 54)
                    .blur(radius: 1)
                    .rotationEffect(.degrees(calculateRotation()))
                
                // Inner Dial (Anodized Aluminum)
                Circle()
                    .fill(LinearGradient(gradient: Gradient(colors: [.gray, .white, .gray]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.2), lineWidth: 1)
                    )
                
                // Indicator Dot
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 4, height: 4)
                    .offset(y: -20)
                    .rotationEffect(.degrees(calculateRotation()))
                    .shadow(color: .cyan, radius: 2)
            }
        }
    }
    
    private func calculateRotation() -> Double {
        let normalized = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return (normalized * 360) - 180
    }
}

struct ModernButton: View {
    var label: String
    var isActive: Bool
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(isActive ? .white : .gray)
                .frame(width: 60, height: 30)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isActive ? Color.cyan.opacity(0.3) : Color.black.opacity(0.5))
                        
                        if isActive {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.cyan, lineWidth: 1)
                                .blur(radius: 1)
                        }
                    }
                )
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

struct ModernOLEDDisplay: View {
    var content: AnyView
    
    var body: some View {
        ZStack {
            Color.black
            
            content
                .foregroundColor(.white)
                .padding()
                .background(
                    // Subtle glass reflection
                    LinearGradient(gradient: Gradient(colors: [Color.white.opacity(0.05), Color.clear]), startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black, radius: 10)
    }
}
