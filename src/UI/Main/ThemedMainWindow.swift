//
//  ThemedMainWindow.swift
//  NeuralSDR2
//
//  The high-fidelity themed window that wraps the app experience
//

import SwiftUI

public struct ThemedMainWindow: View {

    public init() {}
    @EnvironmentObject var appState: AppState
    @StateObject private var themeManager = ThemeManager()
    @State private var gain: Double = 35.0
    @State private var squelchThreshold: Double = -90.0
    @State private var squelchEnabled: Bool = false
    @State private var agcEnabled: Bool = true
    
    public var body: some View {
        ZStack {
            // 1. Base Chassis Material
        themeManager.properties.primarySurface
        .edgesIgnoringSafeArea(.all)
            
            // 2. Layout
            VStack(spacing: 0) {
                // Header / Toolbar
                HStack {
                    Text("NeuralSDR2")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(themeManager.properties.textColor)
                        .padding()
                    
                    Spacer()
                    
                    // Theme Switcher
                    Picker("Theme", selection: $themeManager.currentTheme) {
                        ForEach(HardwareTheme.allCases, id: \.self) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 300)
                    .padding()
                }
                .background(themeManager.properties.accentMaterial)
                
                // Main Body
                HStack(spacing: 0) {
                    // Sidebar
                    MainSidebar()
                        .frame(width: 250)
                        .background(themeManager.properties.accentMaterial)
                    
                    Divider()
                    
                    // Main Display with theme-specific effects
                    ZStack {
                        if themeManager.currentTheme == .military {
                            CombinedDisplayView()
                                .modifier(CRTDisplayEffect())
                        } else if themeManager.currentTheme == .vintage {
                            CombinedDisplayView()
                                .overlay(
                                    // Simulated acrylic lens
                                    RadialGradient(gradient: Gradient(colors: [.white.opacity(0.1), .clear]), center: .center, startRadius: 100, endRadius: 600)
                                )
                        } else {
                            CombinedDisplayView()
                        }
                    }
                    .background(themeManager.properties.displayBackground)
                    .cornerRadius(8)
                    .padding(10)
                    
                    Divider()
                    
            // Inspector Panel
            MainInspector(gain: $gain, squelchThreshold: $squelchThreshold, squelchEnabled: $squelchEnabled, agcEnabled: $agcEnabled)
                        .frame(width: 280)
                        .background(themeManager.properties.accentMaterial)
                }
                
                // Status Bar
                MainStatusBar()
                    .background(themeManager.properties.accentMaterial)
            }
        }
        .environmentObject(themeManager)
    }
}

public extension View {
    func edgesSDRCuts() -> some View {
        self.edgesIgnoringSafeArea(.all)
    }
}
