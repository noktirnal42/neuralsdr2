//
//  ControlPanel.swift
//  NeuralSDR2
//
//  Control panel components for bandwidth, gain, squelch, etc.
//

import SwiftUI

// MARK: - Bandwidth Control

struct BandwidthControl: View {
    @Binding var bandwidth: Double
    var mode: DemodulatorType
    
    var recommendedRanges: [(min: Double, max: Double, step: Double)] {
        switch mode {
        case .AM:
            return [(3000, 12000, 1000)]
        case .NFM:
            return [(5000, 25000, 500)]
        case .WFM:
            return [(150000, 250000, 5000)]
        case .USB, .LSB:
            return [(500, 3000, 100)]
        case .CW:
            return [(100, 1000, 50)]
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Filter Bandwidth")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(formatBandwidth(bandwidth))
                    .font(.system(size: 11, monospaced: true))
                    .foregroundColor(.secondary)
            }
            
            Picker("Bandwidth", selection: $bandwidth) {
                ForEach(generatePresets(), id: \.self) { bw in
                    Text(formatBandwidth(bw)).tag(bw)
                }
            }
            .pickerStyle(.segmented)
            
            Slider(value: Binding(
                get: { bandwidth },
                set: { newValue in
                    bandwidth = newValue
                }
            ), in: recommendedRanges.first!.min...recommendedRanges.first!.max)
                .controlSize(.small)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func generatePresets() -> [Double] {
        let range = recommendedRanges.first!
        var presets: [Double] = []
        var current = range.min
        while current <= range.max {
            presets.append(current)
            current += range.step
        }
        return presets
    }
    
    private func formatBandwidth(_ bw: Double) -> String {
        if bw >= 1000 {
            return String(format: "%.1f kHz", bw / 1000)
        } else {
            return String(format: "%.0f Hz", bw)
        }
    }
}

// MARK: - Gain Control

struct GainControl: View {
    @Binding var gain: Double
    var maxGain: Double = 50.0
    var agcEnabled: Bool
    var onAGCToggle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RF Gain")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(String(format: "%.1f dB", gain))
                    .font(.system(size: 11, monospaced: true))
                    .foregroundColor(.secondary)
                
                Toggle("AGC", isOn: Binding(
                    get: { agcEnabled },
                    set: { _ in onAGCToggle() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            
            Slider(value: Binding(
                get: { gain },
                set: { newValue in
                    gain = newValue
                }
            ), in: 0...maxGain)
                .disabled(agcEnabled)
                .controlSize(.small)
            
            HStack {
                Text("0")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.0f", maxGain))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Squelch Control

struct SquelchControl: View {
    @Binding var threshold: Double
    @Binding var enabled: Bool
    var mode: SquelchMode
    
    enum SquelchMode {
        case noise
        case tone
        case disabled
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Squelch")
                    .font(.system(size: 11, weight: .semibold))
                
                Toggle("Enabled", isOn: $enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                
                Spacer()
                
                Text(String(format: "%.1f dB", threshold))
                    .font(.system(size: 11, monospaced: true))
                    .foregroundColor(enabled ? .green : .secondary)
            }
            
            if enabled {
                Slider(value: Binding(
                    get: { threshold },
                    set: { newValue in
                        threshold = newValue
                    }
                ), in: -120...0)
                    .controlSize(.small)
                
                HStack {
                    Text("-120 dB")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("0 dB")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .opacity(enabled ? 1.0 : 0.7)
    }
}

// MARK: - Frequency Entry

struct FrequencyEntry: View {
    @Binding var frequency: Double
    var onFrequencyChange: (Double) -> Void
    
    @State private var tempFreq: String = ""
    
    var body: some View {
        HStack(spacing: 8) {
            Text("Frequency:")
                .font(.system(size: 11, weight: .semibold))
            
            TextField("MHz", text: $tempFreq)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .onSubmit {
                    parseAndSetFrequency(tempFreq)
                }
            
            Menu("Bands") {
                Button("FM Broadcast (88-108 MHz)") {
                    onFrequencyChange(100_000_000)
                }
                Button("Air Band (108-137 MHz)") {
                    onFrequencyChange(125_000_000)
                }
                Button("2m Ham (144-148 MHz)") {
                    onFrequencyChange(145_000_000)
                }
                Button("70cm Ham (420-450 MHz)") {
                    onFrequencyChange(435_000_000)
                }
                Button("ADS-B (1090 MHz)") {
                    onFrequencyChange(1_090_000_000)
                }
            }
            .menuStyle(.borderlessButton)
        }
        .onAppear {
            tempFreq = String(format: "%.3f", frequency / 1_000_000)
        }
    }
    
    private func parseAndSetFrequency(_ input: String) {
        var value: Double?
        
        // Try parsing with unit suffix
        if input.lowercased().contains("ghz") {
            value = Double(input.replacingOccurrences(of: "ghz", with: "", options: .caseInsensitive))?.map { $0 * 1_000_000_000 }
        } else if input.lowercased().contains("mhz") {
            value = Double(input.replacingOccurrences(of: "mhz", with: "", options: .caseInsensitive))?.map { $0 * 1_000_000 }
        } else if input.lowercased().contains("khz") {
            value = Double(input.replacingOccurrences(of: "khz", with: "", options: .caseInsensitive))?.map { $0 * 1_000 }
        } else if input.lowercased().contains("hz") {
            value = Double(input.replacingOccurrences(of: "hz", with: "", options: .caseInsensitive))
        } else {
            // Assume MHz if no unit
            value = Double(input)?.map { $0 * 1_000_000 }
        }
        
        if let freq = value {
            onFrequencyChange(freq)
        }
    }
}

// MARK: - Mode Selector

struct ModeSelector: View {
    @Binding var currentMode: DemodulatorType
    var onModeChange: (DemodulatorType) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Demodulator")
                .font(.system(size: 11, weight: .semibold))
            
            HStack(spacing: 4) {
                ForEach(DemodulatorType.allCases, id: \.self) { mode in
                    Button(mode.rawValue) {
                        onModeChange(mode)
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(currentMode == mode ? .white : .primary)
                    .background(currentMode == mode ? Color.blue : Color.clear)
                    .cornerRadius(4)
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Signal Meter

struct SignalMeter: View {
    var level: Float  // dBm
    var squelchThreshold: Double = -120
    var squelchEnabled: Bool = false
    
    var body: some View {
        HStack(spacing: 2) {
            Text("S")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
            
            ForEach(0..<10) { i in
                Rectangle()
                    .fill(colorForLevel(level: level, index: i))
                    .frame(width: 4, height: 14)
            }
            
            Text(String(format: "%+.0f", level))
                .font(.system(size: 9, monospaced: true))
                .foregroundColor(.secondary)
        }
        .padding(4)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(4)
    }
    
    private func colorForLevel(level: Float, index: Int) -> Color {
        let threshold: Float = -120 + Float(index) * 10
        
        if squelchEnabled && level < squelchThreshold {
            return Color.gray.opacity(0.3)
        }
        
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
    VStack(spacing: 16) {
        BandwidthControl(bandwidth: Binding.constant(2400), mode: .USB)
        GainControl(gain: Binding.constant(35), agcEnabled: false, onAGCToggle: {})
        SquelchControl(threshold: Binding.constant(-90), enabled: Binding.constant(true), mode: .noise)
        FrequencyEntry(frequency: Binding.constant(1090_000_000), onFrequencyChange: {})
        ModeSelector(currentMode: Binding.constant(.NFM), onModeChange: {})
        SignalMeter(level: -65)
    }
    .padding()
    .frame(width: 400)
}
