//
// SSBDemodulator.swift
// NeuralSDR2
//
// SSB (Single Sideband) demodulator
// Supports USB (Upper Sideband) and LSB (Lower Sideband)
//

import Foundation
import Accelerate

/// SSB Demodulator using frequency shifting and filtering
public class SSBDemodulator: DSPBlock {
    public var name: String
    public var sampleRate: Double
    public var inputChannels = 1
    public var outputChannels = 1 // Real audio output

    private var bandwidth: Double
    private var bfoFrequency: Double // Beat Frequency Oscillator
    private var filter: FIRFilter?
    private var mixedBuffer: [ComplexFloat] = []
    private var phase: Float = 0

    public enum Sideband {
        case USB // Upper Sideband
        case LSB // Lower Sideband
    }

    private var sideband: Sideband

    public init(name: String = "SSB Demodulator", bandwidth: Double = 2400, sampleRate: Double = 2_048_000, sideband: Sideband = .USB) {
        self.name = name
        self.sampleRate = sampleRate
        self.bandwidth = bandwidth
        self.sideband = sideband
        self.bfoFrequency = 1500 // Default BFO offset

        let filterCoeffs = DSPFilterDesign.lowpassFIR(cutoff: bandwidth / 2, sampleRate: sampleRate, transitionWidth: 500, attenuation: 60)
        self.filter = FIRFilter(name: "SSB Filter", coefficients: filterCoeffs, sampleRate: sampleRate)
    }

    public func process(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        let shiftFreq = sideband == .USB ? -bfoFrequency : bfoFrequency
        let phaseStep = Float(2.0 * Double(shiftFreq) / Double(sampleRate))

        for i in 0..<count {
            let lo = ComplexFloat(real: cos(phase), imag: sin(phase))
            phase += phaseStep

            // Wrap phase to [-pi, pi]
            while phase > Float.pi {
                phase -= 2.0 * Float.pi
            }
            while phase < -Float.pi {
                phase += 2.0 * Float.pi
            }

            let mixed = input[i] * lo

            output[i] = ComplexFloat(real: mixed.real, imag: 0)
        }

        if let filter = filter {
            if mixedBuffer.count < count {
                mixedBuffer = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: count)
            }
            for i in 0..<count {
                mixedBuffer[i] = output[i]
            }
            mixedBuffer.withUnsafeBufferPointer { mixedBuf in
                filter.process(mixedBuf.baseAddress!, output, count: count)
            }
        }
    }

    public func reset() {
        phase = 0
        filter?.reset()
    }

    public func configure(params: [String: Any]) {
        if let bw = params["bandwidth"] as? Double {
            setBandwidth(bw)
        }
        if let bfo = params["bfoFrequency"] as? Double {
            bfoFrequency = bfo
        }
        if let sb = params["sideband"] as? Sideband {
            sideband = sb
        }
    }

    public func setBFOFrequency(_ frequency: Double) {
        bfoFrequency = frequency
    }

    public func setSideband(_ sb: Sideband) {
        sideband = sb
    }

    public func setBandwidth(_ newBandwidth: Double) {
        bandwidth = newBandwidth
        let filterCoeffs = DSPFilterDesign.lowpassFIR(cutoff: bandwidth / 2, sampleRate: sampleRate, transitionWidth: 500, attenuation: 60)
        filter = FIRFilter(name: "SSB Filter", coefficients: filterCoeffs, sampleRate: sampleRate)
    }
}

// MARK: - USB Demodulator

/// Upper Sideband demodulator
public class USBDemodulator: SSBDemodulator {
    public init(sampleRate: Double = 2_048_000) {
        super.init(name: "USB", bandwidth: 2400, sampleRate: sampleRate, sideband: .USB)
    }
}

// MARK: - LSB Demodulator

/// Lower Sideband demodulator
public class LSBDemodulator: SSBDemodulator {
    public init(sampleRate: Double = 2_048_000) {
        super.init(name: "LSB", bandwidth: 2400, sampleRate: sampleRate, sideband: .LSB)
    }
}
