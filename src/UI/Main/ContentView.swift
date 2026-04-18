//
//  ContentView.swift
//  NeuralSDR2
//
//  Main application view with spectrum display and controls
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var sidebarWidth: CGFloat = 250
    @State private var inspectorWidth: CGFloat = 280
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            ToolbarView()
            
            Divider()
            
            // Main content area
            HStack(spacing: 0) {
                // Sidebar
                SidebarView()
                    .frame(width: sidebarWidth)
                    .border(Color.gray.opacity(0.3))
                
                Divider()
                
                // Center - Main display
                MainDisplayView()
                    .frame(minWidth: 400)
                
                Divider()
                
                // Inspector panel
                InspectorView()
                    .frame(width: inspectorWidth)
                    .border(Color.gray.opacity(0.3))
            }
            
            Divider()
            
            // Status bar
            StatusBarView()
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Toolbar

struct ToolbarView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 16) {
            // Start/Stop button
            Button(action: {
                if appState.isRunning {
                    appState.stopSDR()
                } else {
                    appState.startSDR()
                }
            }) {
                Image(systemName: appState.isRunning ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                Text(appState.isRunning ? "Stop" : "Start")
            }
            .buttonStyle(.borderedProminent)
            
            Divider()
            
            // Frequency display and entry
            HStack {
                Text("Frequency:")
                    .font(.system(size: 11))
                
                TextField("MHz", value: Binding(
                    get: { appState.frequency / 1_000_000 },
                    set: { appState.setFrequency($0 * 1_000_000) }
                ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                
                Menu("Bands") {
                    Button("FM Broadcast") { appState.setFrequency(100_000_000) }
                    Button("Air Band") { appState.setFrequency(125_000_000) }
                    Button("2m Ham") { appState.setFrequency(145_000_000) }
                    Button("70cm Ham") { appState.setFrequency(435_000_000) }
                    Button("ADS-B") { appState.setFrequency(1_090_000_000) }
                }
            }
            
            Spacer()
            
            // Device info
            if let device = appState.deviceInfo {
                Label(device.name, systemImage: "usb")
                    .font(.caption)
            } else {
                Label("No Device", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedBand = "All Bands"
    
    let bands = ["All Bands", "HF", "VHF", "UHF", "FM Broadcast", "Air Band", "2m Ham", "70cm Ham", "ADS-B"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Bands")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            
            List(selection: $selectedBand) {
                ForEach(bands, id: \.self) { band in
                    Text(band)
                        .tag(band)
                }
            }
            .listStyle(.sidebar)
            
            Divider()
            
            Text("Bookmarks")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            
            List {
                Text("109.000 MHz - Air Band")
                Text("145.525 MHz - 2m FM")
                Text("435.800 MHz - 70cm FM")
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 200)
    }
}

// MARK: - Main Display

struct MainDisplayView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            switch appState.displayMode {
            case .spectrum:
                SpectrumDisplayView()
            case .waterfall:
                WaterfallDisplayView()
            case .combined:
                CombinedDisplayView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

// MARK: - Spectrum Display Placeholder

struct SpectrumDisplayView: View {
    @EnvironmentObject var appState: AppState
    @State private var spectrumData: [CGFloat] = []
    
    var body: some View {
        ZStack {
            Color.black
            
            if spectrumData.isEmpty {
                Text("Spectrum Display")
                    .foregroundColor(.white)
            } else {
                SpectrumPlot(data: spectrumData)
                    .foregroundColor(.green)
            }
        }
    }
}

struct SpectrumPlot: View {
    let data: [CGFloat]
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard !data.isEmpty else { return }
                
                let step = geometry.size.width / CGFloat(data.count - 1)
                let height = geometry.size.height
                
                path.move(to: CGPoint(x: 0, y: height - data[0] * height))
                
                for i in 1..<data.count {
                    let x = CGFloat(i) * step
                    let y = height - data[i] * height
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(Color.green, lineWidth: 2)
        }
    }
}

// MARK: - Waterfall Display Placeholder

struct WaterfallDisplayView: View {
    var body: some View {
        ZStack {
            Color.black
            Text("Waterfall Display")
                .foregroundColor(.white)
        }
    }
}

// MARK: - Combined Display

struct CombinedDisplayView: View {
    var body: some View {
        VStack(spacing: 2) {
            SpectrumDisplayView()
                .frame(height: 300)
            Divider()
            WaterfallDisplayView()
        }
    }
}

// MARK: - Inspector Panel

struct InspectorView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Mode selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Demodulator")
                        .font(.system(size: 11, weight: .semibold))
                    
                    Picker("Mode", selection: $appState.currentMode) {
                        ForAll(AppState.DemodulatorMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }
                
                Divider()
                
                // Filter settings
                VStack(alignment: .leading, spacing: 8) {
                    Text("Filter")
                        .font(.system(size: 11, weight: .semibold))
                    
                    HStack {
                        Text("Bandwidth:")
                        Spacer()
                        Text("2.4 kHz")
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: Binding(
                        get: { 2400.0 },
                        set: { _ in }
                    ), in: 100...50000)
                }
                
                Divider()
                
                // Gain control
                VStack(alignment: .leading, spacing: 8) {
                    Text("Gain")
                        .font(.system(size: 11, weight: .semibold))
                    
                    HStack {
                        Text("RF Gain:")
                        Slider(value: Binding(
                            get: { 45.0 },
                            set: { _ in }
                        ), in: 0...50)
                        Text("dB")
                            .foregroundColor(.secondary)
                    }
                    
                    Toggle("AGC", isOn: .constant(true))
                }
                
                Divider()
                
                // Squelch
                VStack(alignment: .leading, spacing: 8) {
                    Text("Squelch")
                        .font(.system(size: 11, weight: .semibold))
                    
                    HStack {
                        Text("Threshold:")
                        Slider(value: Binding(
                            get: { -100.0 },
                            set: { _ in }
                        ), in: -120...0)
                        Text("dB")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Status Bar

struct StatusBarView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 16) {
            // Status message
            Text(appState.statusMessage)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Spacer()
            
            // Signal level
            SMeterView(level: appState.signalLevel)
            
            Spacer()
            
            // Sample rate
            Text("\(formatSampleRate(appState.sampleRate))")
                .font(.system(size: 11, monospaced: true))
                .foregroundColor(.secondary)
            
            // Current frequency
            Text(formatFrequency(appState.frequency))
                .font(.system(size: 11, monospaced: true))
                .foregroundColor(.secondary)
            
            // Current mode
            Text(appState.currentMode.rawValue)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.blue)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func formatFrequency(_ freq: Double) -> String {
        if freq >= 1_000_000_000 {
            return String(format: "%.3f GHz", freq / 1_000_000_000)
        } else if freq >= 1_000_000 {
            return String(format: "%.3f MHz", freq / 1_000_000)
        } else {
            return String(format: "%.0f kHz", freq / 1_000)
        }
    }
    
    private func formatSampleRate(_ rate: Double) -> String {
        if rate >= 1_000_000 {
            return String(format: "%.2f MSps", rate / 1_000_000)
        } else {
            return String(format: "%.0f kSps", rate / 1_000)
        }
    }
}

// MARK: - S-Meter

struct SMeterView: View {
    let level: Float  // dBm
    @State private var animatedLevel: Float = -120.0
    
    var body: some View {
        HStack(spacing: 2) {
            Text("S")
                .font(.system(size: 10, weight: .bold))
            
            ForEach(0..<10) { i in
                Rectangle()
                    .fill(colorForLevel(level: animatedLevel, index: i))
                    .frame(width: 3, height: 12)
            }
            
            Text(String(format: "%+.0f dB", level))
                .font(.system(size: 9, monospaced: true))
                .foregroundColor(.secondary)
        }
        .onChange(of: level) { _, newValue in
            withAnimation(.easeOut(duration: 0.1)) {
                animatedLevel = newValue
            }
        }
    }
    
    private func colorForLevel(level: Float, index: Int) -> Color {
        let threshold: Float = -120 + Float(index) * 10
        if level >= threshold {
            if index < 6 {
                return .green
            } else if index < 8 {
                return .yellow
            } else {
                return .red
            }
        }
        return Color.gray.opacity(0.3)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(AppState())
}
