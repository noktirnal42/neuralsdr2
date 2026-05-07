//
//  ThemeManager.swift
//  NeuralSDR2
//
//  Central orchestrator for "Virtual Hardware" themes
//

import SwiftUI

/// Available hardware themes
public enum HardwareTheme: String, CaseIterable {
    case vintage = "Vintage"   // 1960s Ham Radio
    case modern = "Modern"     // Contemporary Studio Gear
    case military = "Military" // Tactical Avionics
}

/// Theme-specific visual properties
public struct ThemeProperties {
    // Materials
    var primarySurface: AnyView
    var accentMaterial: AnyView
    var displayBackground: Color
    var accentColor: Color
    var textColor: Color
    
    // Lighting & Effects
    var glowColor: Color
    var shadowColor: Color
    var displayEffect: DisplayEffect
    
    public enum DisplayEffect {
        case analogIncandescent // Warm amber glow, curved glass
        case oledPrecision      // Perfect blacks, crisp cyan
        case crtPhosphor         // Green bloom, scanlines, barrel distortion
    }
}

/// Global manager for UI themes
public class ThemeManager: ObservableObject {
    @Published public var currentTheme: HardwareTheme = .modern
    
    public init() {}
    
    /// Returns the active properties for the current theme
    public var properties: ThemeProperties {
        switch currentTheme {
        case .vintage:
            return vintageProperties
        case .modern:
            return modernProperties
        case .military:
            return militaryProperties
        }
    }
    
    // MARK: - Vintage Properties
    private var vintageProperties: ThemeProperties {
        ThemeProperties(
            primarySurface: AnyView(BrushedAluminumMaterial()),
            accentMaterial: AnyView(WalnutWoodMaterial()),
            displayBackground: Color(red: 0.15, green: 0.10, blue: 0.08),
            accentColor: Color(red: 1.0, green: 0.7, blue: 0.0),
            textColor: Color(red: 0.96, green: 0.92, blue: 0.85),
            glowColor: Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.5),
            shadowColor: Color.black.opacity(0.6),
            displayEffect: .analogIncandescent
        )
    }

    // MARK: - Modern Properties
    private var modernProperties: ThemeProperties {
        ThemeProperties(
            primarySurface: AnyView(MatteBlackMaterial()),
            accentMaterial: AnyView(AnodizedAluminumMaterial()),
            displayBackground: Color(red: 0.05, green: 0.05, blue: 0.1),
            accentColor: Color(red: 0.0, green: 1.0, blue: 1.0),
            textColor: .white,
            glowColor: Color.cyan.opacity(0.4),
            shadowColor: Color.black.opacity(0.8),
            displayEffect: .oledPrecision
        )
    }

    // MARK: - Military Properties
    private var militaryProperties: ThemeProperties {
        ThemeProperties(
            primarySurface: AnyView(OliveDrabMaterial()),
            accentMaterial: AnyView(RuggedSteelMaterial()),
            displayBackground: Color(red: 0.02, green: 0.1, blue: 0.02),
            accentColor: Color(red: 0.0, green: 1.0, blue: 0.0),
            textColor: Color(red: 0.0, green: 1.0, blue: 0.0),
            glowColor: Color.green.opacity(0.3),
            shadowColor: Color.black.opacity(0.9),
            displayEffect: .crtPhosphor
        )
    }
}

// MARK: - Material Implementations (Visual Simulations)

public struct BrushedAluminumMaterial: View {
    public var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [Color(white: 0.7), Color(white: 0.9), Color(white: 0.7)]), startPoint: .top, endPoint: .bottom)
            // Simulate horizontal brushing with a noise overlay
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .blendMode(.overlay)
                .mask(NoiseTextureView())
        }
    }
}

public struct WalnutWoodMaterial: View {
    public var body: some View {
        ZStack {
            Color(red: 0.2, green: 0.1, blue: 0.05)
            // Simulated wood grain via linear gradients and noise
            LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0.3), Color.clear, Color.black.opacity(0.3)]), startPoint: .leading, endPoint: .trailing)
        }
    }
}

public struct MatteBlackMaterial: View {
    public var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.1)
            // Micro-sandblasted texture
            Rectangle()
                .fill(Color.white.opacity(0.02))
                .blendMode(.overlay)
                .mask(NoiseTextureView())
        }
    }
}

public struct OliveDrabMaterial: View {
    public var body: some View {
        ZStack {
            Color(red: 0.22, green: 0.23, blue: 0.15)
            // Flat paint texture
            Rectangle()
                .fill(Color.black.opacity(0.1))
                .mask(NoiseTextureView())
        }
    }
}

public struct AnodizedAluminumMaterial: View {
    public var body: some View {
        LinearGradient(gradient: Gradient(colors: [Color.gray, Color.white, Color.gray]), startPoint: .top, endPoint: .bottom)
    }
}

public struct RuggedSteelMaterial: View {
    public var body: some View {
        Color(red: 0.2, green: 0.2, blue: 0.2)
    }
}

public struct NoiseTextureView: View {
    public var body: some View {
        Canvas { context, size in
            for _ in 0..<1000 {
                let x = CGFloat.random(in: 0...size.width)
                let y = CGFloat.random(in: 0...size.height)
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.white))
            }
        }
    }
}
