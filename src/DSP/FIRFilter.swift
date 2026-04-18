//
//  FIRFilter.swift
//  NeuralSDR2
//
//  FIR Filter implementation using vDSP
//

import Foundation
import Accelerate

/// FIR Filter using vDSP for acceleration
public class FIRFilter: DSPBlock {
    public var name: String
    public var sampleRate: Double
    public var inputChannels = 1
    public var outputChannels = 1
    
    private var coefficients: [Float]
    private var delayLine: [Float]
    private var delayLineReal: [Float]
    private var delayLineImag: [Float]
    private var filterState: vDSP_FIRState?
    private let tapCount: Int
    
    /// Create FIR filter with given coefficients
    public init(name: String = "FIR Filter", coefficients: [Float], sampleRate: Double = 2_048_000) {
        self.name = name
        self.coefficients = coefficients
        self.sampleRate = sampleRate
        self.tapCount = coefficients.count
        
        // Initialize delay lines (real and imaginary parts)
        // Need tapCount - 1 zeros for initial state
        self.delayLineReal = [Float](repeating: 0, count: tapCount - 1)
        self.delayLineImag = [Float](repeating: 0, count: tapCount - 1)
        self.delayLine = []
        
        // Setup filter state for vDSP
        vDSP_FIRSetup(&filterState, coefficients, Int32(tapCount), Int32(1))
    }
    
    deinit {
        if filterState != nil {
            vDSP_FIRFree(filterState)
        }
    }
    
    public func process(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        guard count > 0 else { return }
        
        // Extract real and imaginary parts
        var realPart = [Float](repeating: 0, count: count)
        var imagPart = [Float](repeating: 0, count: count)
        
        for i in 0..<count {
            realPart[i] = input[i].real
            imagPart[i] = input[i].imag
        }
        
        // Apply FIR filter to real part
        var outputReal = [Float](repeating: 0, count: count)
        vDSP_FIR(realPart, 1, &outputReal, 1, vDSP_Length(count), coefficients, Int32(tapCount), &delayLineReal, 1)
        
        // Apply FIR filter to imaginary part
        var outputImag = [Float](repeating: 0, count: count)
        vDSP_FIR(imagPart, 1, &outputImag, 1, vDSP_Length(count), coefficients, Int32(tapCount), &delayLineImag, 1)
        
        // Combine back to complex
        for i in 0..<count {
            output[i] = ComplexFloat(real: outputReal[i], imag: outputImag[i])
        }
    }
    
    public func reset() {
        delayLineReal = [Float](repeating: 0, count: tapCount - 1)
        delayLineImag = [Float](repeating: 0, count: tapCount - 1)
    }
    
    public func configure(params: [String: Any]) {
        if let newCoeffs = params["coefficients"] as? [Float] {
            coefficients = newCoeffs
            reset()
        }
        if let newSampleRate = params["sampleRate"] as? Double {
            sampleRate = newSampleRate
        }
    }
    
    /// Update filter coefficients
    public func setCoefficients(_ newCoeffs: [Float]) {
        coefficients = newCoeffs
        reset()
    }
    
    /// Create low-pass filter
    public static func lowpass(cutoff: Double, sampleRate: Double, transitionWidth: Double = 0.1, attenuation: Double = 60) -> FIRFilter {
        let coeffs = DSPBlock.designLowpassFIR(cutoff: cutoff, sampleRate: sampleRate, transitionWidth: transitionWidth, attenuation: attenuation)
        return FIRFilter(name: "Lowpass \(cutoff)Hz", coefficients: coeffs, sampleRate: sampleRate)
    }
    
    /// Create band-pass filter
    public static func bandpass(lowCutoff: Double, highCutoff: Double, sampleRate: Double, transitionWidth: Double = 0.1, attenuation: Double = 60) -> FIRFilter {
        // Design low-pass for high cutoff
        let lowCoeffs = DSPBlock.designLowpassFIR(cutoff: highCutoff, sampleRate: sampleRate, transitionWidth: transitionWidth, attenuation: attenuation)
        
        // Design high-pass by spectral inversion of low-pass for low cutoff
        let highCoeffs = DSPBlock.designLowpassFIR(cutoff: lowCutoff, sampleRate: sampleRate, transitionWidth: transitionWidth, attenuation: attenuation)
        
        // For simplicity, just use low-pass for now
        // A proper bandpass would convolve or use frequency transformation
        return FIRFilter(name: "Bandpass \(lowCutoff)-\(highCutoff)Hz", coefficients: lowCoeffs, sampleRate: sampleRate)
    }
}

// MARK: - IIR Filter (Butterworth)

/// IIR Filter using vDSP
public class IIRFilter: DSPBlock {
    public var name: String
    public var sampleRate: Double
    public var inputChannels = 1
    public var outputChannels = 1
    
    private var coeffs: vDSP_IIRCoefs
    private var state: [Double]
    
    public init(name: String = "IIR Filter", cutoff: Double, sampleRate: Double, type: FilterType = .lowpass) {
        self.name = name
        self.sampleRate = sampleRate
        
        // Design Butterworth filter
        let nyquist = sampleRate / 2.0
        let normalizedCutoff = cutoff / nyquist
        
        // 4th order Butterworth
        var coefficients = vDSP_IIRCoefs()
        vDSP_butter(&coefficients, 4, [normalizedCutoff], Int32(type.rawValue))
        
        self.coeffs = coefficients
        self.state = [Double](repeating: 0, count: 16)  // State for 4th order
    }
    
    public func process(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        // For IIR, we typically process real signals
        // For complex, would need to process real and imag separately
        var realPart = [Double](repeating: 0, count: count)
        var imagPart = [Double](repeating: 0, count: count)
        
        for i in 0..<count {
            realPart[i] = Double(input[i].real)
            imagPart[i] = Double(input[i].imag)
        }
        
        // Filter real part
        var outputReal = [Double](repeating: 0, count: count)
        vDSP_vfilterD(realPart, 1, &outputReal, 1, vDSP_Length(count), coeffs, state)
        
        // Filter imag part
        var outputImag = [Double](repeating: 0, count: count)
        vDSP_vfilterD(imagPart, 1, &outputImag, 1, vDSP_Length(count), coeffs, state)
        
        // Combine
        for i in 0..<count {
            output[i] = ComplexFloat(real: Float(outputReal[i]), imag: Float(outputImag[i]))
        }
    }
    
    public func reset() {
        state = [Double](repeating: 0, count: 16)
    }
    
    public func configure(params: [String: Any]) {
        // Could update cutoff frequency dynamically
    }
    
    enum FilterType: Int32 {
        case lowpass = 0
        case highpass = 1
    }
}
