//
//  AMDemodulator.swift
//  NeuralSDR2
//
//  AM (Amplitude Modulation) demodulator
//  Supports standard AM, with optional synchronous detection
//

import Foundation
import Accelerate

/// AM Demodulator using envelope detection or synchronous detection
public class AMDemodulator: DSPBlock {
    public var name: String
    public var sampleRate: Double
    public var inputChannels = 1
    public var outputChannels = 1  // Real audio output
    
    private var bandwidth: Double
    private var useSynchronous: Bool
    private var carrierFrequency: Double
    private var carrierPhase: Double = 0
    
    // For envelope detection
    private var filter: FIRFilter?
    
    public init(name: String = "AM Demodulator", bandwidth: Double = 6000, sampleRate: Double = 2_048_000, synchronous: Bool = false) {
        self.name = name
        self.sampleRate = sampleRate
        self.bandwidth = bandwidth
        self.useSynchronous = synchronous
        self.carrierFrequency = 0
    }
    
    public func process(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        // AM demodulation - output is real audio
        // We'll output as complex with imag=0 for compatibility
        
        if useSynchronous {
            processSynchronous(input, output, count: count)
        } else {
            processEnvelope(input, output, count: count)
        }
    }
    
    private func processEnvelope(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        // Envelope detection: |x(t)|
        for i in 0..<count {
            let magnitude = input[i].magnitude
            output[i] = ComplexFloat(real: magnitude, imag: 0)
        }
    }
    
    private func processSynchronous(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        // Synchronous detection: multiply by carrier and low-pass filter
        for i in 0..<count {
            // Multiply by carrier (cosine)
            carrierPhase += carrierFrequency * 2.0 * .pi / sampleRate
            carrierPhase = truncatingRemainder(carrierPhase, by: 2.0 * .pi)
            
            let carrier = ComplexFloat(real: cos(carrierPhase), imag: sin(carrierPhase))
            let mixed = input[i] * carrier
            
            // The audio is in the real part after mixing
            // In a full implementation, we'd low-pass filter here
            output[i] = ComplexFloat(real: mixed.real, imag: 0)
        }
    }
    
    public func reset() {
        carrierPhase = 0
        filter?.reset()
    }
    
    public func configure(params: [String: Any]) {
        if let bw = params["bandwidth"] as? Double {
            bandwidth = bw
        }
        if let sync = params["synchronous"] as? Bool {
            useSynchronous = sync
        }
        if let carrier = params["carrierFrequency"] as? Double {
            carrierFrequency = carrier
        }
    }
    
    /// Set bandwidth for post-demodulation filtering
    public func setBandwidth(_ newBandwidth: Double) {
        bandwidth = newBandwidth
        // Could update filter if implemented
    }
}

// MARK: - AM Stereo (compatible with C-QUAM)

public class AMStereoDemodulator: AMDemodulator {
    private var stereoEnabled = false
    
    public override init(name: String = "AM Stereo Demodulator", bandwidth: Double = 15000, sampleRate: Double = 2_048_000, synchronous: Bool = false) {
        super.init(name: name, bandwidth: bandwidth, sampleRate: sampleRate, synchronous: synchronous)
    }
    
    // AM stereo decoding would go here (C-QUAM, ISB, etc.)
    // For now, inherits standard AM demodulation
}
