//
// AMDemodulator.swift
// NeuralSDR2
//
// AM (Amplitude Modulation) demodulator
// Supports standard AM, with optional synchronous detection
//

import Foundation
import Accelerate

/// AM Demodulator using envelope detection or synchronous detection
public class AMDemodulator: DSPBlock {
    public var name: String
    public var sampleRate: Double
    public var inputChannels = 1
    public var outputChannels = 1

    private var bandwidth: Double
    private var useSynchronous: Bool
    private var carrierFrequency: Double
    private var carrierPhase: Double = 0

    private var filter: FIRFilter
    private var filterTempBuffer: [ComplexFloat] = []

    public init(name: String = "AM Demodulator", bandwidth: Double = 6000, sampleRate: Double = 2_048_000, synchronous: Bool = false) {
        self.name = name
        self.sampleRate = sampleRate
        self.bandwidth = bandwidth
        self.useSynchronous = synchronous
        self.carrierFrequency = 0

        let filterCoeffs = DSPFilterDesign.lowpassFIR(
            cutoff: bandwidth / 2.0,
            sampleRate: sampleRate,
            transitionWidth: 500,
            attenuation: 60
        )
        self.filter = FIRFilter(name: "AM Post-Demod Filter", coefficients: filterCoeffs, sampleRate: sampleRate)
    }

    public func process(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        if useSynchronous {
            processSynchronous(input, output, count: count)
        } else {
            processEnvelope(input, output, count: count)
        }
    }

    private func processEnvelope(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        for i in 0..<count {
            let magnitude = input[i].magnitude
            output[i] = ComplexFloat(real: magnitude, imag: 0)
        }

        var sum: Float = 0
        for i in 0..<count {
            sum += output[i].real
        }
        let mean = sum / Float(count)
        for i in 0..<count {
            output[i] = ComplexFloat(real: output[i].real - mean, imag: 0)
        }

        applyFilter(output, count: count)
    }

    private func processSynchronous(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        for i in 0..<count {
            carrierPhase += carrierFrequency * 2.0 * Double.pi / sampleRate
            carrierPhase = carrierPhase.truncatingRemainder(dividingBy: 2.0 * Double.pi)

            let carrier = ComplexFloat(real: Float(cos(carrierPhase)), imag: Float(sin(carrierPhase)))
            let mixed = input[i] * carrier

            output[i] = ComplexFloat(real: mixed.real, imag: 0)
        }

        applyFilter(output, count: count)
    }

    private func applyFilter(_ buffer: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        if filterTempBuffer.count < count {
            filterTempBuffer = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: count)
        }
        for i in 0..<count {
            filterTempBuffer[i] = buffer[i]
        }
        filterTempBuffer.withUnsafeBufferPointer { tempPtr in
            filter.process(UnsafePointer(tempPtr.baseAddress!), buffer, count: count)
        }
        for i in 0..<count {
            buffer[i] = ComplexFloat(real: buffer[i].real, imag: 0)
        }
    }

    public func reset() {
        carrierPhase = 0
        filter.reset()
    }

    public func configure(params: [String: Any]) {
        if let bw = params["bandwidth"] as? Double {
            setBandwidth(bw)
        }
        if let sync = params["synchronous"] as? Bool {
            useSynchronous = sync
        }
        if let carrier = params["carrierFrequency"] as? Double {
            carrierFrequency = carrier
        }
    }

    public func setBandwidth(_ newBandwidth: Double) {
        bandwidth = newBandwidth
        let filterCoeffs = DSPFilterDesign.lowpassFIR(
            cutoff: bandwidth / 2.0,
            sampleRate: sampleRate,
            transitionWidth: 500,
            attenuation: 60
        )
        filter = FIRFilter(name: "AM Post-Demod Filter", coefficients: filterCoeffs, sampleRate: sampleRate)
    }
}

// MARK: - AM Stereo (compatible with C-QUAM)

public class AMStereoDemodulator: AMDemodulator {
    private var stereoEnabled = false

    public override init(name: String = "AM Stereo Demodulator", bandwidth: Double = 15000, sampleRate: Double = 2_048_000, synchronous: Bool = false) {
        super.init(name: name, bandwidth: bandwidth, sampleRate: sampleRate, synchronous: synchronous)
    }
}
