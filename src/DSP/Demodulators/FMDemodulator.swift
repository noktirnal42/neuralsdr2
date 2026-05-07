//
// FMDemodulator.swift
// NeuralSDR2
//
// FM (Frequency Modulation) demodulator
// Supports narrow FM and wideband FM (broadcast)
//

import Foundation
import Accelerate

/// FM Demodulator using quadrature demodulation
public class FMDemodulator: DSPBlock {
    public var name: String
    public var sampleRate: Double
    public var inputChannels = 1
    public var outputChannels = 1

    private var bandwidth: Double
    public var peakDeviation: Double
    private var deemphasis: Double
    private var previousAngle: Float = 0
    private var deemphasisFilter: DeemphasisFilter?
    private var deemphasisAudioBuffer: [Float] = []

    public init(name: String = "FM Demodulator", bandwidth: Double = 15000, sampleRate: Double = 2_048_000, deemphasis: Double = 75, peakDeviation: Double = 5000) {
        self.name = name
        self.sampleRate = sampleRate
        self.bandwidth = bandwidth
        self.peakDeviation = peakDeviation
        self.deemphasis = deemphasis

        if deemphasis > 0 {
            deemphasisFilter = DeemphasisFilter(timeConstant: deemphasis, sampleRate: sampleRate)
        }
    }

    public func process(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        let scale = Float(sampleRate) / (2.0 * Float.pi * Float(peakDeviation))

        for i in 0..<count {
            let angle = atan2(input[i].imag, input[i].real)

            var delta = angle - previousAngle

            if delta > Float.pi {
                delta -= 2.0 * Float.pi
            } else if delta < -Float.pi {
                delta += 2.0 * Float.pi
            }

            previousAngle = angle

            let audio = delta * scale

            output[i] = ComplexFloat(real: audio, imag: 0)
        }

        if let filter = deemphasisFilter {
            if deemphasisAudioBuffer.count < count {
                deemphasisAudioBuffer = [Float](repeating: 0, count: count)
            }
            for i in 0..<count {
                deemphasisAudioBuffer[i] = output[i].real
            }
            filter.process(&deemphasisAudioBuffer, count: count)
            for i in 0..<count {
                output[i] = ComplexFloat(real: deemphasisAudioBuffer[i], imag: 0)
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
        if let dev = params["peakDeviation"] as? Double {
            peakDeviation = dev
        }
    }

    public func setBandwidth(_ newBandwidth: Double) {
        bandwidth = newBandwidth
    }

    public func setPeakDeviation(_ deviation: Double) {
        peakDeviation = deviation
    }
}

// MARK: - Deemphasis Filter

/// Simple first-order low-pass filter for FM deemphasis
public class DeemphasisFilter {
    private var tau: Float
    private var alpha: Float
    private var previousOutput: Float = 0

    public init(timeConstant: Double, sampleRate: Double) {
        self.tau = Float(timeConstant) * 1e-6

        let dt = Float(1.0 / sampleRate)
        self.alpha = dt / (self.tau + dt)
    }

    public func process(_ samples: inout [Float], count: Int) {
        for i in 0..<count {
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

/// Wideband FM for broadcast (75μs deemphasis, 200kHz bandwidth, 75kHz deviation)
public class WBFMDemodulator: FMDemodulator {
    public init(sampleRate: Double = 2_048_000) {
        super.init(name: "WBFM", bandwidth: 200_000, sampleRate: sampleRate, deemphasis: 75, peakDeviation: 75_000)
    }
}

// MARK: - NBFM (Narrow FM)

/// Narrowband FM for communications (50μs deemphasis, 12.5kHz bandwidth, 5kHz deviation)
public class NBFMDemodulator: FMDemodulator {
    public init(sampleRate: Double = 2_048_000) {
        super.init(name: "NBFM", bandwidth: 12_500, sampleRate: sampleRate, deemphasis: 50, peakDeviation: 5_000)
    }
}
