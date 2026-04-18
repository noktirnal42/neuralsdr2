//
//  MilitaryControls.swift
//  NeuralSDR2
//
//  Rugged tactical controls for the Military theme
//

import SwiftUI

struct MilitaryToggle: View {
    @Binding var isOn: Bool
    var label: String
    
    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(red: 0.7, green: 0.7, blue: 0.6))
            
            ZStack(alignment: .center) {
                // Switch Base
                Capsule()
                    .fill(Color(red: 0.2, green: 0.2, blue: 0.2))
                    .frame(width: 30, height: 60)
                
                // The "Bat-handle" switch
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(gradient: Gradient(colors: [.gray, .white, .gray]), startPoint: .leading, endPoint: .trailing))
                    .frame(width: 12, height: 30)
                    .offset(y: isOn ? -15 : 15)
                    .animation(.spring(), value: isOn)
                
                // Safety Cover (Red Flip Cover)
                if !isOn {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.red.opacity(0.6))
                        .frame(width: 34, height: 34)
                        .rotationEffect(.degrees(-45))
                        .offset(y: -10)
                        .opacity(0.8)
                }
            }
        }
    }
}

struct MilitaryRotary: View {
    @Binding var value: Double
    var range: ClosedRange<<DoubleDouble>
    var label: String
    
    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(red: 0.7, green: 0.7, blue: 0.6))
            
            ZStack {
                // Rugged Base
                Circle()
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.1))
                    .frame(width: 60, height: 60)
                
                // Deep Ridged Dial
                Circle()
                    .fill(Color(red: 0.3, green: 0.3, blue: 0.3))
                    .frame(width: 50, height: 50)
                    .overlay(
                        // Simulated deep ridges
                        ForEach(0..<<336) { i in
                            Rectangle()
                                .fill(Color.black.opacity(0.5))
                                .frame(width: 2, height: 10)
                                .offset(y: -20)
                                .rotationEffect(.degrees(Double(i * 10)))
                        }
                    )
                
                // Indicator
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: 10)
                    .offset(y: -20)
                    .rotationEffect(.degrees(calculateRotation()))
            }
        }
    }
    
    private func calculateRotation() -> Double {
        let normalized = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return (normalized * 360) - 180
    }
}

struct TacticalLabel: View {
    var text: String
    
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundColor(Color(red: 0.8, green: 0.8, blue: 0.7))
            .padding(4)
            .background(Color.black.opacity(0.3))
            .border(Color.gray.opacity(0.3), width: 1)
    }
}
