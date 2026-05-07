//  DemodulatorTests.swift
//  NeuralSDR2Tests
//
//  Unit tests for demodulators (AM, FM, SSB)
//

import XCTest
import Accelerate
@testable import NeuralSDR2Kit

// Helper to generate complex IQ samples for a modulated signal
private func generateAMSignal(carrierFreq: Double, modFreq: Double, modDepth: Float, sampleRate: Double, count: Int) -> [ComplexFloat] {
    var samples = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: count)
    for i in 0..<count {
        let t = Double(i) / sampleRate
        let envelope = 1.0 + modDepth * Float(cos(2.0 * Double.pi * modFreq * t))
        let carrier = cos(2.0 * Double.pi * carrierFreq * t)
        samples[i] = ComplexFloat(real: envelope * Float(carrier), imag: 0)
    }
    return samples
}

private func generateFMSignal(carrierFreq: Double, modFreq: Double, deviation: Double, sampleRate: Double, count: Int) -> [ComplexFloat] {
    var samples = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: count)
    var phase = 0.0
    for i in 0..<count {
        let t = Double(i) / sampleRate
        let modSignal = cos(2.0 * Double.pi * modFreq * t)
        let freqOffset = deviation * modSignal
        phase += 2.0 * Double.pi * (carrierFreq + freqOffset) / sampleRate
        samples[i] = ComplexFloat(real: Float(cos(phase)), imag: Float(sin(phase)))
    }
    return samples
}

final class AMDemodulatorTests: XCTestCase {
    func testAMEnvelopeDetection() {
        // Generate an AM signal at baseband (carrierFreq=0)
        // For AM demod, we need the complex envelope
        let sampleRate = 64000.0
        let count = 8192
        let modFreq = 1000.0
        let modDepth: Float = 0.5

        var input = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: count)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let envelope: Float = 1.0 + modDepth * Float(cos(2.0 * Double.pi * modFreq * t))
            input[i] = ComplexFloat(real: envelope, imag: 0)
        }

        let demod = AMDemodulator(bandwidth: 6000, sampleRate: sampleRate)
        var output = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: count)

        input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                demod.process(inPtr.baseAddress!, outPtr.baseAddress!, count: count)
            }
        }

        // Check that output has finite values
        for i in 1000..<count {
            XCTAssertTrue(output[i].real.isFinite, "Non-finite output at index \(i)")
        }

        // The demodulated audio should have some energy
        var sumSq: Float = 0
        for i in 2000..<count {
            sumSq += output[i].real * output[i].real
        }
        let rms = sqrt(sumSq / Float(count - 2000))
        XCTAssertGreaterThan(rms, 0.001, "AM demod should produce audio output")
    }

    func testAMResetDoesNotCrash() {
        let demod = AMDemodulator(bandwidth: 6000, sampleRate: 64000)
        let input: [ComplexFloat] = [ComplexFloat(real: 1.0, imag: 0)]
        var output = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: 1)

        input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                demod.process(inPtr.baseAddress!, outPtr.baseAddress!, count: 1)
            }
        }

        demod.reset()

        input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                demod.process(inPtr.baseAddress!, outPtr.baseAddress!, count: 1)
            }
        }
        XCTAssertTrue(output[0].real.isFinite)
    }

    func testAMSetBandwidth() {
        let demod = AMDemodulator(bandwidth: 6000, sampleRate: 64000)
        demod.setBandwidth(10000)
        // Just verify no crash
        let input: [ComplexFloat] = [ComplexFloat(real: 0.5, imag: 0)]
        var output = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: 1)
        input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                demod.process(inPtr.baseAddress!, outPtr.baseAddress!, count: 1)
            }
        }
        XCTAssertTrue(output[0].real.isFinite)
    }
}

final class FMDemodulatorTests: XCTestCase {
    func testFMConstantFrequencyProducesDC() {
        // A constant-frequency complex sinusoid should produce DC output from FM demod
        let sampleRate = 64000.0
        let count = 8192
        let freq = 5000.0  // 5 kHz offset

        var input = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: count)
        for i in 0..<count {
            let phase = 2.0 * Double.pi * freq * Double(i) / sampleRate
            input[i] = ComplexFloat(real: Float(cos(phase)), imag: Float(sin(phase)))
        }

        let demod = FMDemodulator(bandwidth: 15000, sampleRate: sampleRate, peakDeviation: 5000)
        var output = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: count)

        input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                demod.process(inPtr.baseAddress!, outPtr.baseAddress!, count: count)
            }
        }

        // The output should settle to approximately freq / peakDeviation
        // 5000 Hz / 5000 Hz deviation = ~1.0
        var sum: Float = 0
        var count2 = 0
        for i in 1000..<count {
            sum += output[i].real
            count2 += 1
        }
        let avg = sum / Float(count2)
        XCTAssertEqual(avg, 1.0, accuracy: 0.2, "FM demod constant freq should output ~1.0 for 5kHz/5kHz deviation")
    }

    func testFMZeroFrequencyProducesZero() {
        // Zero frequency offset should produce zero output
        let sampleRate = 64000.0
        let count = 4096

        // DC signal (1+0j)
        let input = [ComplexFloat](repeating: ComplexFloat(real: 1.0, imag: 0), count: count)
        let demod = FMDemodulator(bandwidth: 15000, sampleRate: sampleRate, peakDeviation: 5000)
        var output = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: count)

        input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                demod.process(inPtr.baseAddress!, outPtr.baseAddress!, count: count)
            }
        }

        // Output should be near zero (no frequency change)
        var sum: Float = 0
        for i in 100..<count {
            sum += abs(output[i].real)
        }
        let avg = sum / Float(count - 100)
        XCTAssertLessThan(avg, 0.1, "FM demod of DC signal should be near zero")
    }

    func testFMReset() {
        let demod = FMDemodulator(bandwidth: 15000, sampleRate: 64000)
        demod.reset()
        // No crash
        let input: [ComplexFloat] = [ComplexFloat(real: 1.0, imag: 0)]
        var output = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: 1)
        input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                demod.process(inPtr.baseAddress!, outPtr.baseAddress!, count: 1)
            }
        }
        XCTAssertTrue(output[0].real.isFinite)
    }

    func testWFMFactory() {
        let demod = WBFMDemodulator(sampleRate: 512000)
        XCTAssertEqual(demod.peakDeviation, 75000)
    }

    func testNFMFactory() {
        let demod = NBFMDemodulator(sampleRate: 64000)
        XCTAssertEqual(demod.peakDeviation, 5000)
    }
}

final class SSBDemodulatorTests: XCTestCase {
    func testSSBProducesAudioOutput() {
        let sampleRate = 64000.0
        let count = 8192

        // Generate a USB signal: carrier + 1kHz tone offset
        var input = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: count)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let audio = Float(cos(2.0 * Double.pi * 1000.0 * t))
            // In USB, the audio spectrum is shifted up by the BFO frequency
            // For baseband IQ, the signal energy is at +1 kHz offset
            let signalPhase = 2.0 * Double.pi * 1000.0 * t
            input[i] = ComplexFloat(real: audio * Float(cos(signalPhase)), imag: audio * Float(sin(signalPhase)))
        }

        let demod = SSBDemodulator(bandwidth: 2400, sampleRate: sampleRate, sideband: .USB)
        var output = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: count)

        input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                demod.process(inPtr.baseAddress!, outPtr.baseAddress!, count: count)
            }
        }

        // Output should have energy after settling
        var sumSq: Float = 0
        for i in 2000..<count {
            sumSq += output[i].real * output[i].real
        }
        let rms = sqrt(sumSq / Float(count - 2000))
        XCTAssertGreaterThan(rms, 0.001, "SSB demod should produce audio output")
    }

    func testUSBAndLSBFactories() {
        let usb = USBDemodulator(sampleRate: 64000)
        let lsb = LSBDemodulator(sampleRate: 64000)
        // Just verify they create without crash
        XCTAssertEqual(usb.name, "USB")
        XCTAssertEqual(lsb.name, "LSB")
    }

    func testSSBReset() {
        let demod = SSBDemodulator(bandwidth: 2400, sampleRate: 64000)
        demod.reset()
        // Verify no crash
        let input: [ComplexFloat] = [ComplexFloat(real: 1.0, imag: 0)]
        var output = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: 1)
        input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                demod.process(inPtr.baseAddress!, outPtr.baseAddress!, count: 1)
            }
        }
        XCTAssertTrue(output[0].real.isFinite)
    }

    func testSSBSetBFOFrequency() {
        let demod = SSBDemodulator(bandwidth: 2400, sampleRate: 64000)
        demod.setBFOFrequency(800)
        // No crash
        let input: [ComplexFloat] = [ComplexFloat(real: 0.5, imag: 0)]
        var output = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: 1)
        input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                demod.process(inPtr.baseAddress!, outPtr.baseAddress!, count: 1)
            }
        }
        XCTAssertTrue(output[0].real.isFinite)
    }
}

final class DeemphasisFilterTests: XCTestCase {
    func testDeemphasisDoesNotCrash() {
        let filter = DeemphasisFilter(timeConstant: 75, sampleRate: 48000)
        var samples: [Float] = (0..<1024).map { _ in Float.random(in: -1...1) }
        filter.process(&samples, count: 1024)
        XCTAssertTrue(samples.allSatisfy { $0.isFinite })
    }

    func testDeemphasisAttenuatesHighFrequency() {
        // 75μs deemphasis should attenuate high-frequency content
        let filter = DeemphasisFilter(timeConstant: 75, sampleRate: 48000)

        // Generate a 15 kHz tone
        var highFreq = [Float](repeating: 0, count: 4096)
        for i in 0..<4096 {
            highFreq[i] = 0.5 * sin(2.0 * Float.pi * 15000.0 * Float(i) / 48000.0)
        }

        // Generate a 100 Hz tone at same amplitude
        var lowFreq = [Float](repeating: 0, count: 4096)
        for i in 0..<4096 {
            lowFreq[i] = 0.5 * sin(2.0 * Float.pi * 100.0 * Float(i) / 48000.0)
        }

        filter.process(&highFreq, count: 4096)
        filter.reset()
        filter.process(&lowFreq, count: 4096)

        // Measure RMS of each (skip first 1000 for settling)
        var highSq: Float = 0, lowSq: Float = 0
        for i in 1000..<4096 {
            highSq += highFreq[i] * highFreq[i]
            lowSq += lowFreq[i] * lowFreq[i]
        }
        let highRMS = sqrt(highSq / 3096)
        let lowRMS = sqrt(lowSq / 3096)

        XCTAssertLessThan(highRMS, lowRMS, "Deemphasis should attenuate high frequency more than low frequency")
    }
}
