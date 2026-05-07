//
// SpectrumAnalyzer.swift
// NeuralSDR2
//
// FFT-based spectrum analyzer
// Provides real-time spectrum display data
//

import Foundation
import Accelerate
import simd
import Metal

/// Spectrum analyzer using FFT
public class SpectrumAnalyzer {
private var fftSetup: FFTSetup
private var fftSize: Int
private var log2n: vDSP_Length
private var window: [Float]
private var windowPowerNormalization: Float
private var realBuffer: [Float]
private var imagBuffer: [Float]
private var rawPower: [Float]
private var dbPower: [Float]
private var shiftedDBPower: [Float]
private var sampleRate: Double
private var centerFrequency: Double

private var cachedFrequencyAxis: [Double] = []
private var cachedAxisSampleRate: Double = 0
private var cachedAxisCenterFreq: Double = 0

// Averaging
private var averageBuffer: [Float]?
private var maxHoldBuffer: [Float]?
private var minHoldBuffer: [Float]?
private var averagingCount = 0

// GPU acceleration
private var metalFFT: MetalFFT?
private var useGPU: Bool

public enum WindowType {
case rectangular
case hamming
case hann
case blackmanHarris
}

public init(fftSize: Int = 2048, sampleRate: Double = 2_048_000, centerFrequency: Double = 1090_000_000, windowType: WindowType = .hann, useGPU: Bool = true) {
self.fftSize = fftSize
self.sampleRate = sampleRate
self.centerFrequency = centerFrequency
self.useGPU = useGPU

// Setup FFT - log2n must be vDSP_Length (which is UInt)
let log2 = vDSP_Length(log2(Double(fftSize)))
self.log2n = log2
fftSetup = vDSP_create_fftsetup(log2, FFTRadix(kFFTRadix2))!

// Create window
self.window = SpectrumAnalyzer.createWindow(type: windowType, size: fftSize)
self.windowPowerNormalization = max(
    self.window.reduce(0) { $0 + ($1 * $1) } / Float(max(fftSize, 1)),
    1e-12
)

// Buffers
realBuffer = [Float](repeating: 0, count: fftSize)
imagBuffer = [Float](repeating: 0, count: fftSize)
rawPower = [Float](repeating: 0, count: fftSize)
dbPower = [Float](repeating: 0, count: fftSize)
shiftedDBPower = [Float](repeating: 0, count: fftSize)

// Try Metal FFT if requested
if useGPU {
    metalFFT = MetalFFT(fftSize: fftSize, sampleRate: sampleRate, centerFrequency: centerFrequency)
}
}

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

/// Process a buffer of complex samples and return spectrum in dB
public func process(_ samples: [ComplexFloat]) -> [Float] {
// Use Metal FFT if available
if let metal = metalFFT {
    let result = metal.process(samples: samples)
    if !result.isEmpty {
        if averageBuffer != nil {
            applyAveraging(result)
            return averageBuffer!
        }
        return result
    }
}

let count = min(samples.count, fftSize)

// Apply window and separate into real/imag buffers
for i in 0..<count {
realBuffer[i] = samples[i].real * window[i]
imagBuffer[i] = samples[i].imag * window[i]
}

// Zero-pad if necessary
for i in count..<fftSize {
realBuffer[i] = 0
imagBuffer[i] = 0
}

// Create split-complex structure for vDSP FFT using withUnsafeMutableBufferPointer
// to ensure pointers outlive the DSPSplitComplex initialization
return realBuffer.withUnsafeMutableBufferPointer { realPtr in
imagBuffer.withUnsafeMutableBufferPointer { imagPtr in
var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)

// Perform forward in-place FFT
vDSP_fft_zip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

// Compute power for every FFT bin so the UI can render a full centered IQ spectrum.
for i in 0..<fftSize {
    let real = splitComplex.realp[i]
    let imag = splitComplex.imagp[i]
    rawPower[i] = (real * real) + (imag * imag)
}

// Normalize magnitude-squared by FFT size and window power, then convert power to dB.
// vDSP_vdbcon with formula=0 computes 10*log10(source/ref) for power values.
var normalization = Float(fftSize * fftSize) * windowPowerNormalization
vDSP_vsdiv(rawPower, 1, &normalization, &rawPower, 1, vDSP_Length(fftSize))
var zeroRef: Float = 1.0
vDSP_vdbcon(rawPower, 1, &zeroRef, &dbPower, 1, vDSP_Length(fftSize), 0)

let halfSize = fftSize / 2
for i in 0..<fftSize {
    let shiftedIndex = (i + halfSize) % fftSize
    let value = dbPower[shiftedIndex]
    if !value.isFinite {
        shiftedDBPower[i] = -140.0
    } else {
        shiftedDBPower[i] = min(max(value, -140.0), 10.0)
    }
}

// Apply averaging if enabled
if averageBuffer != nil {
applyAveraging(shiftedDBPower)
return averageBuffer!
}
return shiftedDBPower
}
}
}

    /// Get frequency axis in Hz
    public func getFrequencyAxis() -> [Double] {
        if cachedFrequencyAxis.isEmpty || cachedAxisSampleRate != sampleRate || cachedAxisCenterFreq != centerFrequency {
            let binWidth = sampleRate / Double(fftSize)
            let startFrequency = centerFrequency - (sampleRate / 2.0)
            cachedFrequencyAxis = (0..<fftSize).map { i in
                startFrequency + (Double(i) * binWidth)
            }
            cachedAxisSampleRate = sampleRate
            cachedAxisCenterFreq = centerFrequency
        }
        return cachedFrequencyAxis
    }

public func updateSampleRate(_ rate: Double) {
sampleRate = rate
metalFFT?.updateSampleRate(rate)
}

public func updateCenterFrequency(_ freq: Double) {
centerFrequency = freq
metalFFT?.updateCenterFrequency(freq)
}

    /// Get magnitude for a specific frequency
    public func getMagnitude(at frequency: Double, from spectrum: [Float]) -> Float? {
        let binWidth = sampleRate / Double(fftSize)
        let startFrequency = centerFrequency - (sampleRate / 2.0)
        let targetBin = Int((frequency - startFrequency) / binWidth)

        guard targetBin >= 0 && targetBin < spectrum.count else {
            return nil
        }

        return spectrum[targetBin]
    }

    private static func createWindow(type: WindowType, size: Int) -> [Float] {
        var window = [Float](repeating: 0, count: size)

        switch type {
        case .rectangular:
            window = [Float](repeating: 1, count: size)

        case .hamming:
            vDSP_hamm_window(&window, vDSP_Length(size), 0)

        case .hann:
            vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))

        case .blackmanHarris:
            // 4-term Blackman-Harris window (not directly in vDSP, compute manually)
            let a0: Float = 0.35875
            let a1: Float = 0.48829
            let a2: Float = 0.14128
            let a3: Float = 0.01168
            let N = Float(size - 1)
            for i in 0..<size {
                let n = Float(i)
                window[i] = a0
                    - a1 * cos(2.0 * .pi * n / N)
                    + a2 * cos(4.0 * .pi * n / N)
                    - a3 * cos(6.0 * .pi * n / N)
            }
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
        let alpha: Float = 0.1
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

// MARK: - FFT Direction Constant

/// FFT forward direction constant matching vDSP convention
private let FFT_FORWARD: Int32 = 1

// MARK: - Waterfall Data

/// Manages waterfall display data
public class WaterfallData {
    private var data: [[Float]]
    private var currentIndex = 0
    private let height: Int
    private let width: Int
    private var resizedBuffer: [Float] = []

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

        if resizedBuffer.count < size {
            resizedBuffer = [Float](repeating: 0, count: size)
        }
        let ratio = Float(array.count) / Float(size)

        for i in 0..<size {
            let srcIndex = Int(Float(i) * ratio)
            resizedBuffer[i] = array[min(srcIndex, array.count - 1)]
        }

        return Array(resizedBuffer[0..<size])
    }
}
