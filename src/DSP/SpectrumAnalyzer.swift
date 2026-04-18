//
//  SpectrumAnalyzer.swift
//  NeuralSDR2
//
//  FFT-based spectrum analyzer
//  Provides real-time spectrum display data
//

import Foundation
import Accelerate
import simd

/// Spectrum analyzer using FFT
public class SpectrumAnalyzer {
    private var fftSetup: FFTSetup
    private var fftSize: Int
    private var log2Size: Int32
    private var window: [Float]
    private var realBuffer: [Float]
    private var imagBuffer: [Float]
    private var magnitudeBuffer: [Float]
    private var powerBuffer: [Float]
    private var sampleRate: Double
    private var centerFrequency: Double
    
    // Averaging
    private var averageBuffer: [Float]?
    private var maxHoldBuffer: [Float]?
    private var minHoldBuffer: [Float]?
    private var averagingCount = 0
    
    public enum WindowType {
        case rectangular
        case hamming
        case hann
        case blackmanHarris
    }
    
    public init(fftSize: Int = 2048, sampleRate: Double = 2_048_000, centerFrequency: Double = 1090_000_000, windowType: WindowType = .hann) {
        self.fftSize = fftSize
        self.sampleRate = sampleRate
        self.centerFrequency = centerFrequency
        
        // Setup FFT
        log2Size = Int32(log2(Double(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2Size, FFTRadix(kFFTRadix2))!
        
        // Create window
        self.window = createWindow(type: windowType, size: fftSize)
        
        // Buffers
        realBuffer = [Float](repeating: 0, count: fftSize)
        imagBuffer = [Float](repeating: 0, count: fftSize)
        magnitudeBuffer = [Float](repeating: 0, count: fftSize / 2 + 1)
        powerBuffer = [Float](repeating: 0, count: fftSize / 2 + 1)
    }
    
    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }
    
    /// Process a buffer of complex samples and return spectrum
    public func process(_ samples: [ComplexFloat]) -> [Float] {
        let count = min(samples.count, fftSize)
        
        // Apply window and convert to split-complex format
        for i in 0..<count {
            realBuffer[i] = samples[i].real * window[i]
            imagBuffer[i] = samples[i].imag * window[i]
        }
        
        // Zero-pad if necessary
        for i in count..<fftSize {
            realBuffer[i] = 0
            imagBuffer[i] = 0
        }
        
        // Create split-complex structure
        var splitComplex = DSPComplex(real: &realBuffer, imaginary: &imagBuffer, count: fftSize)
        
        // Perform FFT
        vDSP_fft_zip(fftSetup, &splitComplex, 1, log2Size, FFTDirection(1))
        
        // Calculate magnitude
        var magnitudes = [Float](repeating: 0, count: fftSize / 2 + 1)
        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, fftSize / 2)
        
        // Convert to dB
        var dbPower = [Float](repeating: 0, count: magnitudes.count)
        vDSP_dbcon(magnitudes, 1, &dbPower, 1, magnitudes.count, 0)
        
        // Apply averaging if enabled
        if let _ = averageBuffer {
            applyAveraging(dbPower)
            return averageBuffer!
        }
        
        return dbPower
    }
    
    /// Get frequency axis in Hz
    public func getFrequencyAxis() -> [Double] {
        let binWidth = sampleRate / Double(fftSize)
        let centerBin = Double(fftSize) / 2.0
        
        var frequencies: [Double] = []
        for i in 0..<(fftSize / 2 + 1) {
            let binOffset = Double(i) - centerBin
            let freq = centerFrequency + binOffset * binWidth
            frequencies.append(freq)
        }
        
        return frequencies
    }
    
    /// Get magnitude for a specific frequency
    public func getMagnitude(at frequency: Double, from spectrum: [Float]) -> Float? {
        let binWidth = sampleRate / Double(fftSize)
        let centerBin = Double(fftSize) / 2.0
        let targetBin = Int((frequency - centerFrequency) / binWidth + centerBin)
        
        guard targetBin >= 0 && targetBin < spectrum.count else {
            return nil
        }
        
        return spectrum[targetBin]
    }
    
    private func createWindow(type: WindowType, size: Int) -> [Float] {
        var window = [Float](repeating: 0, count: size)
        
        switch type {
        case .rectangular:
            window = [Float](repeating: 1, count: size)
            
        case .hamming:
            vDSP_hamm(&window, 1, size)
            
        case .hann:
            vDSP_hann_window(&window, vDSP_Length(size), Int32(1))
            
        case .blackmanHarris:
            vDSP_blackmanHarris(&window, 1, size)
        }
        
        return window
    }
    
    private func applyAveraging(_ dbPower: [Float]) {
        if averageBuffer == nil {
            averageBuffer = [Float](repeating: 0, count: dbPower.count)
            maxHoldBuffer = [Float](repeating: -100, count: dbPower.count)
            minHoldBuffer = [Float](repeating: 100, count: dbPower.count)
        }
        
        // Running average
        let alpha = 0.1
        for i in 0..<dbPower.count {
            averageBuffer![i] = alpha * dbPower[i] + (1.0 - alpha) * averageBuffer![i]
            maxHoldBuffer![i] = max(maxHoldBuffer![i], dbPower[i])
            minHoldBuffer![i] = min(minHoldBuffer![i], dbPower[i])
        }
        
        averagingCount += 1
    }
    
    public func reset() {
        averagingCount = 0
        if averageBuffer != nil {
            averageBuffer = [Float](repeating: 0, count: averageBuffer!.count)
            maxHoldBuffer = [Float](repeating: -100, count: averageBuffer!.count)
            minHoldBuffer = [Float](repeating: 100, count: averageBuffer!.count)
        }
    }
}

// MARK: - Waterfall Data

/// Manages waterfall display data
public class WaterfallData {
    private var data: [[Float]]
    private var currentIndex = 0
    private let height: Int
    private let width: Int
    
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.data = [[Float]](repeating: [Float](repeating: 0, count: width), count: height)
    }
    
    /// Add new spectrum line to waterfall
    public func addLine(_ spectrum: [Float]) {
        // Resize if necessary
        let resizedSpectrum = resize(spectrum, to: width)
        
        // Insert at current index (scrolling)
        data[currentIndex] = resizedSpectrum
        currentIndex = (currentIndex + 1) % height
    }
    
    /// Get waterfall data as 2D array
    public func getData() -> [[Float]] {
        return data
    }
    
    /// Get current display start index
    public func getCurrentIndex() -> Int {
        return currentIndex
    }
    
    private func resize(_ array: [Float], to size: Int) -> [Float] {
        if array.count == size {
            return array
        }
        
        var resized = [Float](repeating: 0, count: size)
        let ratio = Float(array.count) / Float(size)
        
        for i in 0..<size {
            let srcIndex = Int(Float(i) * ratio)
            resized[i] = array[min(srcIndex, array.count - 1)]
        }
        
        return resized
    }
}
