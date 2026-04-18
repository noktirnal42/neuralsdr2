//
//  SpectrumMarkers.swift
//  NeuralSDR2
//
//  Marker system for spectrum display
//

import Foundation

/// Marker types
public enum MarkerType {
    case normal       // Regular marker
    case delta        // Delta marker (relative)
    case peak         // Peak marker (auto-find)
    case bandwidth    // Bandwidth measurement (-3dB, -6dB, etc.)
}

/// Spectrum marker
public struct SpectrumMarker: Identifiable {
    public let id: UUID
    public var type: MarkerType
    public var frequency: Double      // Hz
    public var amplitude: Float       // dB
    public var deltaFrequency: Double // Hz (for delta markers)
    public var deltaAmplitude: Float  // dB (for delta markers)
    public var label: String
    public var isActive: Bool
    
    public init(
        id: UUID = UUID(),
        type: MarkerType = .normal,
        frequency: Double = 0,
        amplitude: Float = -100,
        deltaFrequency: Double = 0,
        deltaAmplitude: Float = 0,
        label: String = "",
        isActive: Bool = true
    ) {
        self.id = id
        self.type = type
        self.frequency = frequency
        self.amplitude = amplitude
        self.deltaFrequency = deltaFrequency
        self.deltaAmplitude = deltaAmplitude
        self.label = label
        self.isActive = isActive
    }
}

/// Manages spectrum markers
public class MarkerManager {
    private var markers: [SpectrumMarker] = []
    private var activeMarkerIndex: Int = 0
    private var showAllMarkers: Bool = true
    
    /// Add a new marker
    public func addMarker(at frequency: Double, amplitude: Float) -> SpectrumMarker {
        let marker = SpectrumMarker(
            frequency: frequency,
            amplitude: amplitude,
            label: formatFrequency(frequency)
        )
        markers.append(marker)
        return marker
    }
    
    /// Add delta marker relative to reference
    public func addDeltaMarker(reference: SpectrumMarker, at frequency: Double, amplitude: Float) -> SpectrumMarker {
        let marker = SpectrumMarker(
            type: .delta,
            frequency: frequency,
            amplitude: amplitude,
            deltaFrequency: frequency - reference.frequency,
            deltaAmplitude: amplitude - reference.amplitude,
            label: String(format: "Δ%.1f kHz", (frequency - reference.frequency) / 1000)
        )
        markers.append(marker)
        return marker
    }
    
    /// Find peak and create marker
    public func findPeak(in spectrum: [Float], frequencyAxis: [Double], range: ClosedRange<Double>?) -> SpectrumMarker? {
        guard !spectrum.isEmpty else { return nil }
        
        var startIndex = 0
        var endIndex = spectrum.count - 1
        
        // Limit search range if specified
        if let range = range, let freqAxis = frequencyAxis.first {
            if let startFreq = frequencyAxis.firstIndex(where: { $0 >= range.lowerBound }) {
                startIndex = startFreq
            }
            if let endFreq = frequencyAxis.lastIndex(where: { $0 <= range.upperBound }) {
                endIndex = endFreq
            }
        }
        
        guard startIndex < endIndex else { return nil }
        
        // Find maximum
        var maxIndex = startIndex
        var maxValue = spectrum[startIndex]
        
        for i in (startIndex + 1)..<endIndex {
            if spectrum[i] > maxValue {
                maxValue = spectrum[i]
                maxIndex = i
            }
        }
        
        let marker = SpectrumMarker(
            type: .peak,
            frequency: frequencyAxis[maxIndex],
            amplitude: maxValue,
            label: "Peak"
        )
        
        return marker
    }
    
    /// Measure bandwidth at specified dB down from peak
    public func measureBandwidth(in spectrum: [Float], frequencyAxis: [Double], peakIndex: Int, dbDown: Float = -3.0) -> (centerFreq: Double, bandwidth: Double, leftFreq: Double, rightFreq: Double)? {
        guard peakIndex < spectrum.count else { return nil }
        
        let peakAmplitude = spectrum[peakIndex]
        let threshold = peakAmplitude + dbDown
        
        // Find left -3dB point
        var leftIndex = peakIndex
        while leftIndex > 0 && spectrum[leftIndex] > threshold {
            leftIndex -= 1
        }
        
        // Find right -3dB point
        var rightIndex = peakIndex
        while rightIndex < spectrum.count - 1 && spectrum[rightIndex] > threshold {
            rightIndex += 1
        }
        
        guard leftIndex < rightIndex else { return nil }
        
        let leftFreq = frequencyAxis[leftIndex]
        let rightFreq = frequencyAxis[rightIndex]
        let centerFreq = (leftFreq + rightFreq) / 2.0
        let bandwidth = rightFreq - leftFreq
        
        return (centerFreq, bandwidth, leftFreq, rightFreq)
    }
    
    /// Delete marker
    public func deleteMarker(_ marker: SpectrumMarker) {
        markers.removeAll { $0.id == marker.id }
    }
    
    /// Clear all markers
    public func clearMarkers() {
        markers.removeAll()
    }
    
    /// Get all markers
    public func getMarkers() -> [SpectrumMarker] {
        return markers
    }
    
    /// Set active marker
    public func setActiveMarker(index: Int) {
        guard index < markers.count else { return }
        activeMarkerIndex = index
    }
    
    /// Get active marker
    public func getActiveMarker() -> SpectrumMarker? {
        guard markers.count > 0 else { return nil }
        return markers[activeMarkerIndex]
    }
    
    /// Move to next marker
    public func nextMarker() -> SpectrumMarker? {
        guard markers.count > 0 else { return nil }
        activeMarkerIndex = (activeMarkerIndex + 1) % markers.count
        return markers[activeMarkerIndex]
    }
    
    /// Move to previous marker
    public func previousMarker() -> SpectrumMarker? {
        guard markers.count > 0 else { return nil }
        activeMarkerIndex = (activeMarkerIndex - 1 + markers.count) % markers.count
        return markers[activeMarkerIndex]
    }
    
    private func formatFrequency(_ freq: Double) -> String {
        if freq >= 1_000_000 {
            return String(format: "%.3f MHz", freq / 1_000_000)
        } else if freq >= 1_000 {
            return String(format: "%.1f kHz", freq / 1_000)
        } else {
            return String(format: "%.0f Hz", freq)
        }
    }
}

// MARK: - Frequency Manager

/// Manages frequency bookmarks and presets
public class FrequencyManager {
    private var bookmarks: [FrequencyBookmark] = []
    private var presets: [FrequencyPreset] = []
    
    public init() {
        loadBookmarks()
        loadPresets()
    }
    
    /// Add bookmark
    public func addBookmark(frequency: Double, name: String, mode: String) {
        let bookmark = FrequencyBookmark(
            id: UUID(),
            frequency: frequency,
            name: name,
            mode: mode
        )
        bookmarks.append(bookmark)
        saveBookmarks()
    }
    
    /// Delete bookmark
    public func deleteBookmark(_ bookmark: FrequencyBookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        saveBookmarks()
    }
    
    /// Get all bookmarks
    public func getBookmarks() -> [FrequencyBookmark] {
        return bookmarks.sorted { $0.frequency < $1.frequency }
    }
    
    /// Get preset bands
    public func getPresets() -> [FrequencyPreset] {
        return presets
    }
    
    private func loadBookmarks() {
        // Load from file/database
    }
    
    private func saveBookmarks() {
        // Save to file/database
    }
    
    private func loadPresets() {
        // Default preset bands
        presets = [
            FrequencyPreset(name: "FM Broadcast", start: 88_000_000, end: 108_000_000, step: 100_000),
            FrequencyPreset(name: "Air Band", start: 108_000_000, end: 137_000_000, step: 25_000),
            FrequencyPreset(name: "2m Ham", start: 144_000_000, end: 148_000_000, step: 5_000),
            FrequencyPreset(name: "70cm Ham", start: 420_000_000, end: 450_000_000, step: 5_000),
            FrequencyPreset(name: "ADS-B", start: 1_090_000_000, end: 1_090_000_000, step: 1_000_000)
        ]
    }
}

/// Frequency bookmark
public struct FrequencyBookmark: Identifiable {
    public let id: UUID
    public var frequency: Double
    public var name: String
    public var mode: String
    
    public init(id: UUID = UUID(), frequency: Double, name: String, mode: String = "NFM") {
        self.id = id
        self.frequency = frequency
        self.name = name
        self.mode = mode
    }
}

/// Frequency preset band
public struct FrequencyPreset {
    public let name: String
    public let start: Double
    public let end: Double
    public let step: Double
}
