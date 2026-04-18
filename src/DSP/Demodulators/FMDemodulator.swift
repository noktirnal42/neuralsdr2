//
//  FMDemodulator.swift
//  NeuralSDR2
//
//  FM (Frequency Modulation) demodulator
//  Supports narrow FM and wideband FM (broadcast)
//

import Foundation
import Accelerate

/// FM Demodulator using quadrature demodulation
public class FMDemodulator: DSPBlock {
    public var name: String
    public var sampleRate: Double
    public var inputChannels = 1
    public var outputChannels = 1  // Real audio output
    
    private var bandwidth: Double
    private var deemphasis: Double  // Time constant in microseconds (50 or 75)
    private var previousAngle: Float = 0
    private var deemphasisFilter: DeemphasisFilter?
    
    public init(name: String = "FM Demodulator", bandwidth: Double = 15000, sampleRate: Double = 2_048_000, deemphasis: Double = 75) {
        self.name = name
        self.sampleRate = sampleRate
        self.bandwidth = bandwidth
        self.deemphasis = deemphasis
        
        // Setup deemphasis filter if needed
        if deemphasis > 0 {
            deemphasisFilter = DeemphasisFilter(timeConstant: deemphasis, sampleRate: sampleRate)
        }
    }
    
    public func process(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        // Quadrature demodulation: differentiate phase
        // FM: d(phase)/dt = frequency deviation = audio
        
        for i in 0..<count {
            // Calculate phase
            let angle = atan2(input[i].imag, input[i].real)
            
            // Differentiate (with phase unwrapping)
            var delta = angle - previousAngle
            
            // Handle phase wrapping
            if delta > Float.pi {
                delta -= 2.0 * Float.pi
            } else if delta < -Float.pi {
                delta += 2.0 * Float.pi
            }
            
            previousAngle = angle
            
            // Scale to audio range
            // The scaling factor converts from radians/sample to audio amplitude
            let scale = Float(sampleRate) / (2.0 * Float.pi)
            let audio = delta * scale
            
            output[i] = ComplexFloat(real: audio, imag: 0)
        }
        
        // Apply deemphasis filter
        if let filter = deemphasisFilter {
            var audioBuffer = [Float](repeating: 0, count: count)
            for i in 0..<count {
                audioBuffer[i] = output[i].real
            }
            
            filter.process(&audioBuffer, count: count)
            
            for i in 0..<count {
                output[i] = ComplexFloat(real: audioBuffer[i], imag: 0)
            }
        }
    }
    
    public func reset() {
        previousAngle = 0
        deemphasisFilter?.reset()
    }
    
    public func configure(params: [String: Any]) {
        if let bw = params["bandwidth"] as? Double {
            bandwidth = bw
        }
        if let deemp = params["deemphasis"] as? Double {
            if deemp > 0 {
                deemphasisFilter = DeemphasisFilter(timeConstant: deemp, sampleRate: sampleRate)
            } else {
                deemphasisFilter = nil
            }
        }
    }
    
    /// Set FM bandwidth (deviation + audio bandwidth)
    public func setBandwidth(_ newBandwidth: Double) {
        bandwidth = newBandwidth
    }
}

// MARK: - Deemphasis Filter

/// Simple first-order low-pass filter for FM deemphasis
public class DeemphasisFilter {
    private var tau: Float  // Time constant
    private var alpha: Float  // Filter coefficient
    private var previousOutput: Float = 0
    
    public init(timeConstant: Double, sampleRate: Double) {
        // tau in seconds
        self.tau = Float(timeCondition) * 1e-6  // Convert microseconds to seconds
        
        // Calculate alpha for first-order low-pass
        // alpha = dt / (tau + dt) where dt = 1/sampleRate
        let dt = Float(1.0 / sampleRate)
        self.alpha = dt / (self.tau + dt)
    }
    
    public func process(_ samples: inout [Float], count: Int) {
        for i in 0..<count {
            // Simple first-order low-pass: y[n] = alpha * x[n] + (1 - alpha) * y[n-1]
            let output = alpha * samples[i] + (1.0 - alpha) * previousOutput
            previousOutput = output
            samples[i] = output
        }
    }
    
    public func reset() {
        previousOutput = 0
    }
}

// MARK: - WBFM (Broadcast FM)

/// Wideband FM for broadcast (75μs deemphasis, 200kHz bandwidth)
public class WBFMDemodulator: FMDemodulator {
    public init(sampleRate: Double = 2_048_000) {
        super.init(name: "WBFM", bandwidth: 200_000, sampleRate: sampleRate, deemphasis: 75)
    }
}

// MARK: - NBFM (Narrow FM)

/// Narrowband FM for communications (50μs deemphasis, 12.5kHz bandwidth)
public class NBFMDemodulator: FMDemodulator {
    public init(sampleRate: Double = 2_048_000) {
        super.init(name: "NBFM", bandwidth: 12_500, sampleRate: sampleRate, deemphasis: 50)
    }
}
