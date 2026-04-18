//
//  ThemedMainWindow.swift
//  NeuralSDR2
//
//  The high-fidelity themed window that wraps the app experience
//

import SwiftUI

struct ThemedMainWindow: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var themeManager = ThemeManager()
    
    var body: some View {
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
                    // Sidebar (Tied to theme)
                    MainSidebar()
                        .frame(width: 250)
                        .background(themeManager.properties.accentMaterial)
                    
                    Divider()
                    
                    // Main Display with theme-specific effects
                    ZStack {
                        if themeManager.currentTheme == .military {
                            // Apply CRT Effect for military
                            CombinedDisplayView()
                                .modifier(CRTDisplayEffect())
                        } else if themeManager.currentTheme == .vintage {
                            // Apply Curved Glass for vintage
                            CombinedDisplayView()
                                .overlay(
                                    // Simulated acrylic lens
                                    RadialGradient(gradient: Gradient(colors: [.white.opacity(0.1), .clear]), center: .center, startRadius: 100, endRadius: 600)
                                )
                        } else {
                            // Modern clean look
                            CombinedDisplayView()
                        }
                    }
                    .background(themeManager.properties.displayBackground)
                    .cornerRadius(8)
                    .padding(10)
                    
                    Divider()
                    
                    // Inspector Panel
                    MainInspector()
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
