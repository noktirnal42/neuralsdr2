//
//  NeuralSDR2App.swift
//  NeuralSDR2 - Professional SDR for macOS
//
//  Main application entry point
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
    @Published var currentMode: DemodulatorMode = .NFM
    @Published var signalLevel: Float = -120.0
    @Published var statusMessage = "Ready"
    
    var rtlDevice: RTLSDRDevice?
    
    enum DisplayMode {
        case spectrum
        case waterfall
        case combined
    }
    
    enum DemodulatorMode: String {
        case AM = "AM"
        case NFM = "NFM"
        case WFM = "WFM"
        case USB = "USB"
        case LSB = "LSB"
        case CW = "CW"
    }
    
    init() {
        scanForDevices()
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
            rtlDevice = RTLSDRDevice()
            try rtlDevice?.open(index: 0)
            
            var config = RTLSDRConfig()
            config.centerFrequency = frequency
            config.sampleRate = sampleRate
            
            try rtlDevice?.configure(config)
            
            try rtlDevice?.startStreaming { [weak self] samples in
                self?.handleSamples(samples)
            }
            
            isRunning = true
            statusMessage = "Running at \(formatFrequency(frequency))"
            
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
            isRunning = false
        }
    }
    
    func stopSDR() {
        rtlDevice?.stopStreaming()
        rtlDevice?.close()
        rtlDevice = nil
        isRunning = false
        statusMessage = "Stopped"
    }
    
    func setFrequency(_ newFrequency: Double) {
        frequency = newFrequency
        if isRunning {
            do {
                try rtlDevice?.configure(RTLSDRConfig())
                statusMessage = "Tuned to \(formatFrequency(frequency))"
            } catch {
                statusMessage = "Tune error: \(error.localizedDescription)"
            }
        }
    }
    
    private func handleSamples(_ samples: [ComplexFloat]) {
        // Process samples - calculate signal level for demo
        if !samples.isEmpty {
            let avgPower = samples.map { $0.magnitudeSquared }.reduce(0, +) / Float(samples.count)
            signalLevel = 10 * log10(avgPower) - 127.0  // dBFS approximation
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
        // Clean up SDR device
        if let appState = NSApp.windows.first?.contentViewController as? ContentView {
            // Cleanup handled by deinitializers
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
