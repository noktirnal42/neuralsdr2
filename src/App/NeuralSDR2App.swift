//
//  NeuralSDR2App.swift
//  NeuralSDR2 - Professional SDR for macOS
//
//  Main application entry point with full DSP integration
//

import SwiftUI

@main
struct NeuralSDR2App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1200, minHeight: 800)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("SDR") {
                Button("Start") {
                    appState.startSDR()
                }
                .keyboardShortcut("s", modifiers: .command)
                
                Button("Stop") {
                    appState.stopSDR()
                }
                .keyboardShortcut("e", modifiers: .command)
                
                Divider()
                
                Button("Scan Devices") {
                    appState.scanForDevices()
                }
            }
            CommandMenu("View") {
                Button("Spectrum Only") {
                    appState.displayMode = .spectrum
                }
                Button("Waterfall Only") {
                    appState.displayMode = .waterfall
                }
                Button("Combined") {
                    appState.displayMode = .combined
                }
                Divider()
                Button("3D Earth") {
                    // TODO: Open 3D Earth view
                }
            }
            CommandMenu("Demodulator") {
                ForEach(DemodulatorType.allCases, id: \.self) { mode in
                    Button(mode.rawValue) {
                        appState.setMode(mode)
                    }
                    .keyboardShortcut(mode.shortcut)
                }
            }
        }
    }
}

// MARK: - App State

class AppState: ObservableObject {
    @Published var isRunning = false
    @Published var deviceInfo: RTLSDRDeviceInfo?
    @Published var devices: [RTLSDRDeviceInfo] = []
    @Published var frequency: Double = 1090_000_000  // 1090 MHz default
    @Published var sampleRate: Double = 2_048_000
    @Published var displayMode: DisplayMode = .combined
    @Published var currentMode: DemodulatorType = .NFM
    @Published var signalLevel: Float = -120.0
    @Published var spectrumData: [Float] = []
    @Published var statusMessage = "Ready"
    @Published var bandwidth: Double = 15000
    
    var rtlDevice: RTLSDRDevice?
    var dspPipeline: DSPPipeline?
    var audioEngine: AudioOutputEngine?
    var spectrumAnalyzer: SpectrumAnalyzer?
    
    enum DisplayMode {
        case spectrum
        case waterfall
        case combined
    }
    
    init() {
        setupAudio()
        scanForDevices()
        setupSpectrumAnalyzer()
    }
    
    private func setupAudio() {
        do {
            audioEngine = AudioOutputEngine()
            try audioEngine?.initialize(sampleRate: 48000, channels: 2, bufferSize: 512)
        } catch {
            statusMessage = "Audio init error: \(error.localizedDescription)"
        }
    }
    
    private func setupSpectrumAnalyzer() {
        spectrumAnalyzer = SpectrumAnalyzer(fftSize: 2048, sampleRate: sampleRate, centerFrequency: frequency)
    }
    
    func scanForDevices() {
        devices = RTLSDRDevice.enumerateDevices()
        if devices.count > 0 {
            deviceInfo = devices.first
            statusMessage = "Found \(devices.count) RTL-SDR device(s)"
        } else {
            deviceInfo = nil
            statusMessage = "No RTL-SDR devices found"
        }
    }
    
    func startSDR() {
        guard deviceInfo != nil else {
            statusMessage = "No device selected"
            return
        }
        
        do {
            // Open RTL-SDR device
            rtlDevice = RTLSDRDevice()
            try rtlDevice?.open(index: 0)
            
            var config = RTLSDRConfig()
            config.centerFrequency = frequency
            config.sampleRate = sampleRate
            
            try rtlDevice?.configure(config)
            
            // Setup DSP pipeline
            dspPipeline = DSPPipeline(sampleRate: sampleRate, centerFrequency: frequency)
            dspPipeline?.setDemodulator(currentMode)
            
            // Setup spectrum callback
            dspPipeline?.onSpectrumUpdate { [weak self] spectrum in
                DispatchQueue.main.async {
                    self?.spectrumData = spectrum
                    self?.updateSignalLevel(spectrum: spectrum)
                }
            }
            
            // Setup audio callback
            dspPipeline?.onAudioOutput { [weak self] audio in
                self?.audioEngine?.queueSamples(audio)
            }
            
            // Start audio engine
            try audioEngine?.start()
            
            // Start RTL-SDR streaming
            try rtlDevice?.startStreaming { [weak self] samples in
                self?.dspPipeline?.process(samples: samples)
            }
            
            isRunning = true
            statusMessage = "Running: \(currentMode.rawValue) at \(formatFrequency(frequency))"
            
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
            isRunning = false
        }
    }
    
    func stopSDR() {
        rtlDevice?.stopStreaming()
        rtlDevice?.close()
        rtlDevice = nil
        
        audioEngine?.stop()
        audioEngine?.clearBuffer()
        
        isRunning = false
        statusMessage = "Stopped"
        spectrumData = []
    }
    
    func setFrequency(_ newFrequency: Double) {
        frequency = newFrequency
        if isRunning {
            do {
                var config = RTLSDRConfig()
                config.centerFrequency = frequency
                try rtlDevice?.configure(config)
                dspPipeline?.centerFrequency = frequency
                statusMessage = "Tuned to \(formatFrequency(frequency))"
            } catch {
                statusMessage = "Tune error: \(error.localizedDescription)"
            }
        }
    }
    
    func setMode(_ mode: DemodulatorType) {
        currentMode = mode
        dspPipeline?.setDemodulator(mode)
        statusMessage = "Mode: \(mode.rawValue)"
    }
    
    func setBandwidth(_ bw: Double) {
        bandwidth = bw
        dspPipeline?.setBandwidth(bw)
    }
    
    private func updateSignalLevel(spectrum: [Float]) {
        // Calculate average power as signal level
        if !spectrum.isEmpty {
            let avgPower = spectrum.reduce(0, +) / Float(spectrum.count)
            signalLevel = avgPower
        }
    }
    
    private func formatFrequency(_ freq: Double) -> String {
        if freq >= 1_000_000_000 {
            return String(format: "%.3f GHz", freq / 1_000_000_000)
        } else if freq >= 1_000_000 {
            return String(format: "%.3f MHz", freq / 1_000_000)
        } else if freq >= 1_000 {
            return String(format: "%.3f kHz", freq / 1_000)
        } else {
            return "\(Int(freq)) Hz"
        }
    }
}

// MARK: - Demodulator Shortcuts

extension DemodulatorType {
    var shortcut: KeyEquivalent {
        switch self {
        case .AM: return KeyEquivalent("a")
        case .NFM: return KeyEquivalent("f")
        case .WFM: return KeyEquivalent("w")
        case .USB: return KeyEquivalent("u")
        case .LSB: return KeyEquivalent("l")
        case .CW: return KeyEquivalent("c")
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        print("NeuralSDR2 launched - Debug mode")
        #else
        print("NeuralSDR2 launched")
        #endif
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup handled by deinitializers
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
