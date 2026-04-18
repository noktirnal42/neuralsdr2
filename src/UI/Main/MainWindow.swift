//
//  MainWindow.swift
//  NeuralSDR2
//
//  Enhanced main window with integrated controls and displays
//

import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var appState: AppState
    @State private var sidebarCollapsed = false
    @State private var inspectorCollapsed = false
    @State private var gain: Double = 35.0
    @State private var squelchThreshold: Double = -90.0
    @State private var squelchEnabled = false
    @State private var agcEnabled = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            MainToolbar()
            
            Divider()
            
            // Main content
            HStack(spacing: 0) {
                // Sidebar
                if !sidebarCollapsed {
                    MainSidebar()
                        .frame(width: 250)
                        .border(Color.gray.opacity(0.3))
                }
                
                if !sidebarCollapsed {
                    Divider()
                }
                
                // Center - Main display area
                VStack(spacing: 2) {
                    // Display controls
                    DisplayControls()
                    
                    Divider()
                    
                    // Main display (spectrum/waterfall)
                    switch appState.displayMode {
                    case .spectrum:
                        SpectrumDisplayView()
                    case .waterfall:
                        WaterfallDisplayView()
                    case .combined:
                        CombinedDisplayView()
                    }
                }
                .frame(maxWidth: .infinity)
                
                if !inspectorCollapsed {
                    Divider()
                    
                    // Inspector panel
                    MainInspector(
                        gain: $gain,
                        squelchThreshold: $squelchThreshold,
                        squelchEnabled: $squelchEnabled,
                        agcEnabled: $agcEnabled
                    )
                    .frame(width: 280)
                    .border(Color.gray.opacity(0.3))
                }
            }
            
            Divider()
            
            // Status bar
            MainStatusBar()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Toolbar

struct MainToolbar: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 16) {
            // Start/Stop
            Button(action: toggleRunning) {
                Image(systemName: appState.isRunning ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                Text(appState.isRunning ? "Stop" : "Start")
            }
            .buttonStyle(.borderedProminent)
            .help(appState.isRunning ? "Stop (Cmd+E)" : "Start (Cmd+S)")
            
            Divider()
            
            // Frequency entry
            FrequencyEntry(
                frequency: Binding(
                    get: { appState.frequency },
                    set: { appState.setFrequency($0) }
                ),
                onFrequencyChange: { appState.setFrequency($0) }
            )
            
            // Band selector
            Menu("Bands") {
                Button("FM Broadcast") { appState.setFrequency(100_000_000) }
                Button("Air Band") { appState.setFrequency(125_000_000) }
                Button("2m Ham") { appState.setFrequency(145_000_000) }
                Button("70cm Ham") { appState.setFrequency(435_000_000) }
                Button("ADS-B") { appState.setFrequency(1_090_000_000) }
            }
            .menuStyle(.borderlessButton)
            
            Spacer()
            
            // Device info
            if let device = appState.deviceInfo {
                HStack(spacing: 4) {
                    Image(systemName: "usb")
                        .foregroundColor(.green)
                    Text(device.name)
                        .font(.caption)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                    Text("No Device")
                        .font(.caption)
                }
            }
            
            // Recording indicator
            if appState.isRunning {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.red.opacity(0.5), lineWidth: 2)
                    )
                    .animation(.pulse, value: appState.isRunning)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private func toggleRunning() {
        if appState.isRunning {
            appState.stopSDR()
        } else {
            appState.startSDR()
        }
    }
}

// MARK: - Sidebar

struct MainSidebar: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedBand = "All Bands"
    
    let bands = ["All Bands", "HF", "VHF", "UHF", "FM Broadcast", "Air Band", "2m Ham", "70cm Ham", "ADS-B"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Bands
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
            
            // Bookmarks
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
            
            Spacer()
            
            // Recent recordings
            Text("Recent")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            
            List {
                Text("ADS-B Recording")
                Text("NOAA-18 Pass")
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 200)
    }
}

// MARK: - Display Controls

struct DisplayControls: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 12) {
            // Display mode selector
            Picker("Display", selection: Binding(
                get: { appState.displayMode },
                set: { appState.displayMode = $0 }
            )) {
                Text("Spectrum").tag(AppState.DisplayMode.spectrum)
                Text("Waterfall").tag(AppState.DisplayMode.waterfall)
                Text("Combined").tag(AppState.DisplayMode.combined)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            
            Spacer()
            
            // Zoom controls
            Button(action: {}) {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom Out")
            
            Button(action: {}) {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom In")
            
            // Freeze waterfall
            Button(action: {}) {
                Image(systemName: "pause.fill")
            }
            .help("Freeze Waterfall")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Inspector Panel

struct MainInspector: View {
    @EnvironmentObject var appState: AppState
    @Binding var gain: Double
    @Binding var squelchThreshold: Double
    @Binding var squelchEnabled: Bool
    @Binding var agcEnabled: Bool
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Mode selector
                ModeSelector(
                    currentMode: Binding(
                        get: { appState.currentMode },
                        set: { appState.setMode($0) }
                    ),
                    onModeChange: { appState.setMode($0) }
                )
                
                // Bandwidth control
                BandwidthControl(
                    bandwidth: Binding(
                        get: { appState.bandwidth },
                        set: { appState.setBandwidth($0) }
                    ),
                    mode: appState.currentMode
                )
                
                // Gain control
                GainControl(
                    gain: $gain,
                    maxGain: 50.0,
                    agcEnabled: agcEnabled,
                    onAGCToggle: { agcEnabled.toggle() }
                )
                
                // Squelch control
                SquelchControl(
                    threshold: $squelchThreshold,
                    enabled: $squelchEnabled,
                    mode: .noise
                )
                
                Divider()
                
                // Statistics
                VStack(alignment: .leading, spacing: 4) {
                    Text("Statistics")
                        .font(.system(size: 11, weight: .semibold))
                    
                    HStack {
                        Text("Sample Rate:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(String(format: "%.2f", appState.sampleRate / 1_000_000)) MSps")
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                    
                    if let audioEngine = appState.audioEngine {
                        let stats = audioEngine.getStatistics()
                        HStack {
                            Text("Buffer Level:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(stats.bufferLevel) samples")
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Status Bar

struct MainStatusBar: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 16) {
            // Status message
            Text(appState.statusMessage)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Spacer()
            
            // Signal meter
            SignalMeter(
                level: appState.signalLevel,
                squelchThreshold: -90,
                squelchEnabled: false
            )
            
            Spacer()
            
            // Sample rate
            Text(String(format: "%.2f MSps", appState.sampleRate / 1_000_000))
                .font(.system(size: 11, monospaced: true))
                .foregroundColor(.secondary)
            
            // Frequency
            Text(formatFrequency(appState.frequency))
                .font(.system(size: 11, monospaced: true))
                .foregroundColor(.secondary)
            
            // Mode
            Text(appState.currentMode.rawValue)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.blue)
            
            // Recording indicator
            if appState.isRunning {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
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
}

// MARK: - Combined Display (Spectrum + Waterfall)

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

#Preview {
    MainWindow()
        .environmentObject(AppState())
        .frame(width: 1200, height: 800)
}
