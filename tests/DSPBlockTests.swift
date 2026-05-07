//  DSPBlockTests.swift
//  NeuralSDR2Tests
//
//  Unit tests for DSP pipeline components
//

import XCTest
import Accelerate
@testable import NeuralSDR2Kit

final class ComplexFloatTests: XCTestCase {
    func testMagnitude() {
        let c = ComplexFloat(real: 3.0, imag: 4.0)
        XCTAssertEqual(c.magnitude, 5.0, accuracy: 0.001)
    }

    func testMagnitudeSquared() {
        let c = ComplexFloat(real: 3.0, imag: 4.0)
        XCTAssertEqual(c.magnitudeSquared, 25.0, accuracy: 0.001)
    }

    func testPhase() {
        let c = ComplexFloat(real: 1.0, imag: 1.0)
        XCTAssertEqual(c.phase, Float.pi / 4.0, accuracy: 0.001)
    }

    func testAddition() {
        let a = ComplexFloat(real: 1.0, imag: 2.0)
        let b = ComplexFloat(real: 3.0, imag: 4.0)
        let result = a + b
        XCTAssertEqual(result.real, 4.0, accuracy: 0.001)
        XCTAssertEqual(result.imag, 6.0, accuracy: 0.001)
    }

    func testSubtraction() {
        let a = ComplexFloat(real: 5.0, imag: 7.0)
        let b = ComplexFloat(real: 2.0, imag: 3.0)
        let result = a - b
        XCTAssertEqual(result.real, 3.0, accuracy: 0.001)
        XCTAssertEqual(result.imag, 4.0, accuracy: 0.001)
    }

    func testMultiplication() {
        let a = ComplexFloat(real: 1.0, imag: 2.0)
        let b = ComplexFloat(real: 3.0, imag: 4.0)
        // (1+2i)(3+4i) = 3 + 4i + 6i + 8i^2 = 3-8 + 10i = -5+10i
        let result = a * b
        XCTAssertEqual(result.real, -5.0, accuracy: 0.001)
        XCTAssertEqual(result.imag, 10.0, accuracy: 0.001)
    }

    func testScalarMultiplication() {
        let a = ComplexFloat(real: 2.0, imag: 3.0)
        let result = a * 4.0
        XCTAssertEqual(result.real, 8.0, accuracy: 0.001)
        XCTAssertEqual(result.imag, 12.0, accuracy: 0.001)
    }

    func testConjugate() {
        let a = ComplexFloat(real: 3.0, imag: -4.0)
        let conj = a.conjugate
        XCTAssertEqual(conj.real, 3.0, accuracy: 0.001)
        XCTAssertEqual(conj.imag, 4.0, accuracy: 0.001)
    }

    func testFromDB() {
        let linear = ComplexFloat.fromDB(20.0)  // 10.0
        XCTAssertEqual(linear, 10.0, accuracy: 0.001)
    }

    func testToDB() {
        let c = ComplexFloat(real: 10.0, imag: 0.0)
        XCTAssertEqual(c.toDB, 20.0, accuracy: 0.01)
    }

    func testZeroMagnitude() {
        let c = ComplexFloat(real: 0.0, imag: 0.0)
        XCTAssertEqual(c.magnitude, 0.0, accuracy: 0.001)
    }
}

final class FIRFilterTests: XCTestCase {
    func testIdentityFilter() {
        // A single-coefficient filter with coefficient 1.0 should pass signal through
        let filter = FIRFilter(name: "Identity", coefficients: [1.0], sampleRate: 48000)
        let input: [ComplexFloat] = [
            ComplexFloat(real: 1.0, imag: 0.5),
            ComplexFloat(real: 0.5, imag: 1.0),
            ComplexFloat(real: -1.0, imag: -0.5)
        ]
        var output = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: input.count)

        input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                filter.process(inPtr.baseAddress!, outPtr.baseAddress!, count: input.count)
            }
        }

        for i in 0..<input.count {
            XCTAssertEqual(output[i].real, input[i].real, accuracy: 0.001, "Real mismatch at index \(i)")
            XCTAssertEqual(output[i].imag, input[i].imag, accuracy: 0.001, "Imag mismatch at index \(i)")
        }
    }

    func testScalingFilter() {
        // A single coefficient of 0.5 should halve the signal
        let filter = FIRFilter(name: "Scale", coefficients: [0.5], sampleRate: 48000)
        let input: [ComplexFloat] = [
            ComplexFloat(real: 2.0, imag: 4.0)
        ]
        var output = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: 1)

        input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                filter.process(inPtr.baseAddress!, outPtr.baseAddress!, count: 1)
            }
        }

        XCTAssertEqual(output[0].real, 1.0, accuracy: 0.001)
        XCTAssertEqual(output[0].imag, 2.0, accuracy: 0.001)
    }

    func testMovingAverageFilter() {
        // 3-tap moving average: coefficients [1/3, 1/3, 1/3]
        let coeffs: [Float] = [1.0/3.0, 1.0/3.0, 1.0/3.0]
        let filter = FIRFilter(name: "MA3", coefficients: coeffs, sampleRate: 48000)

        // Input: [3, 6, 9, 3, 0]
        let input: [ComplexFloat] = [
            ComplexFloat(real: 3.0, imag: 0),
            ComplexFloat(real: 6.0, imag: 0),
            ComplexFloat(real: 9.0, imag: 0),
            ComplexFloat(real: 3.0, imag: 0),
            ComplexFloat(real: 0.0, imag: 0)
        ]
        var output = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: input.count)

        input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                filter.process(inPtr.baseAddress!, outPtr.baseAddress!, count: input.count)
            }
        }

        // Output[2] = (3 + 6 + 9) / 3 = 6.0
        // Output[3] = (6 + 9 + 3) / 3 = 6.0
        // Output[4] = (9 + 3 + 0) / 3 = 4.0
        XCTAssertEqual(output[2].real, 6.0, accuracy: 0.01)
        XCTAssertEqual(output[3].real, 6.0, accuracy: 0.01)
        XCTAssertEqual(output[4].real, 4.0, accuracy: 0.01)
    }

    func testStatePreservationAcrossBlocks() {
        // Process two blocks of samples and verify state is preserved
        let coeffs: [Float] = [0.5, 0.5]
        let filter = FIRFilter(name: "MA2", coefficients: coeffs, sampleRate: 48000)

        // First block: [1, 2]
        let input1: [ComplexFloat] = [
            ComplexFloat(real: 1.0, imag: 0),
            ComplexFloat(real: 2.0, imag: 0)
        ]
        var output1 = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: 2)

        input1.withUnsafeBufferPointer { inPtr in
            output1.withUnsafeMutableBufferPointer { outPtr in
                filter.process(inPtr.baseAddress!, outPtr.baseAddress!, count: 2)
            }
        }

        // Second block: [3]
        let input2: [ComplexFloat] = [ComplexFloat(real: 3.0, imag: 0)]
        var output2 = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: 1)

        input2.withUnsafeBufferPointer { inPtr in
            output2.withUnsafeMutableBufferPointer { outPtr in
                filter.process(inPtr.baseAddress!, outPtr.baseAddress!, count: 1)
            }
        }

        // output2[0] should use state from previous block: (2 + 3) * 0.5 = 2.5
        XCTAssertEqual(output2[0].real, 2.5, accuracy: 0.01, "State preservation across blocks failed")
    }

    func testReset() {
        let coeffs: [Float] = [0.5, 0.5]
        let filter = FIRFilter(name: "MA2", coefficients: coeffs, sampleRate: 48000)

        // Process some data
        let input1: [ComplexFloat] = [ComplexFloat(real: 10.0, imag: 0)]
        var output1 = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: 1)
        input1.withUnsafeBufferPointer { inPtr in
            output1.withUnsafeMutableBufferPointer { outPtr in
                filter.process(inPtr.baseAddress!, outPtr.baseAddress!, count: 1)
            }
        }

        // Reset
        filter.reset()

        // Process again — should be as if starting fresh
        let input2: [ComplexFloat] = [ComplexFloat(real: 4.0, imag: 0)]
        var output2 = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: 1)
        input2.withUnsafeBufferPointer { inPtr in
            output2.withUnsafeMutableBufferPointer { outPtr in
                filter.process(inPtr.baseAddress!, outPtr.baseAddress!, count: 1)
            }
        }

        // After reset, first sample with 2-tap filter: output = 4 * 0.5 + 0 * 0.5 = 2.0
        XCTAssertEqual(output2[0].real, 2.0, accuracy: 0.01)
    }

    func testLowpassFactory() {
        let filter = FIRFilter.lowpass(cutoff: 1000, sampleRate: 48000)
        XCTAssertGreaterThan(filter.name.count, 0)
        // Filter should have coefficients
        let input: [ComplexFloat] = [ComplexFloat(real: 1.0, imag: 0)]
        var output = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: 1)
        input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                filter.process(inPtr.baseAddress!, outPtr.baseAddress!, count: 1)
            }
        }
        // Just verify it doesn't crash — the output should be finite
        XCTAssertTrue(output[0].real.isFinite)
    }

    func testBandpassFactory() {
        let filter = FIRFilter.bandpass(lowCutoff: 300, highCutoff: 3000, sampleRate: 48000)
        XCTAssertGreaterThan(filter.name.count, 0)
    }
}

final class IIRFilterTests: XCTestCase {
    func testLowpassDoesNotCrash() {
        let filter = IIRFilter(cutoff: 1000, sampleRate: 48000, type: .lowpass)
        let input: [ComplexFloat] = (0..<256).map { _ in ComplexFloat(real: Float.random(in: -1...1), imag: 0) }
        var output = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: input.count)

        input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                filter.process(inPtr.baseAddress!, outPtr.baseAddress!, count: input.count)
            }
        }

        // All outputs should be finite
        for i in 0..<output.count {
            XCTAssertTrue(output[i].real.isFinite, "Non-finite output at index \(i)")
        }
    }

    func testLowpassAttenuatesHighFrequency() {
        // A lowpass at 500 Hz should significantly attenuate a 10kHz signal at 48kHz SR
        let filter = IIRFilter(cutoff: 500, sampleRate: 48000, type: .lowpass)
        let freq: Float = 10000.0
        let sr: Float = 48000.0

        var input = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: 4096)
        for i in 0..<4096 {
            input[i] = ComplexFloat(real: sin(2.0 * Float.pi * freq * Float(i) / sr), imag: 0)
        }

        var output = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: 4096)
        input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                filter.process(inPtr.baseAddress!, outPtr.baseAddress!, count: 4096)
            }
        }

        // Measure RMS of output (steady state, skip first 500 samples)
        var sumSq: Float = 0
        for i in 500..<4096 {
            sumSq += output[i].real * output[i].real
        }
        let rms = sqrt(sumSq / Float(3596))

        // RMS of full-scale 10kHz sine = 0.707
        // After lowpass at 500 Hz, should be heavily attenuated (< 0.1)
        XCTAssertLessThan(rms, 0.1, "High frequency signal not attenuated by lowpass: RMS=\(rms)")
    }

    func testReset() {
        let filter = IIRFilter(cutoff: 1000, sampleRate: 48000, type: .lowpass)

        // Process some data
        let input: [ComplexFloat] = [ComplexFloat(real: 1.0, imag: 0)]
        var output = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: 1)
        input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                filter.process(inPtr.baseAddress!, outPtr.baseAddress!, count: 1)
            }
        }

        filter.reset()

        // Process again — should not crash
        input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                filter.process(inPtr.baseAddress!, outPtr.baseAddress!, count: 1)
            }
        }
        XCTAssertTrue(output[0].real.isFinite)
    }
}

final class AGCProcessorTests: XCTestCase {
    func testAGCBoostsWeakSignal() {
        let agc = AGCProcessor(type: .fast, sampleRate: 48000, threshold: -12.0)
        var samples: [Float] = (0..<10000).map { _ in Float.random(in: -0.01...0.01) }
        let inputRMS = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))

        agc.process(&samples)

        var outputRMS: Float = 0
        // Skip first 5000 samples for AGC to settle
        var sumSq: Float = 0
        for i in 5000..<10000 {
            sumSq += samples[i] * samples[i]
        }
        outputRMS = sqrt(sumSq / 5000.0)

        // After AGC, output should be louder than input
        XCTAssertGreaterThan(outputRMS, inputRMS, "AGC should boost weak signal")
    }

    func testAGCDoesNotAmplifySilence() {
        let agc = AGCProcessor(type: .fast, sampleRate: 48000)
        var samples: [Float] = [Float](repeating: 0, count: 1000)
        agc.process(&samples)

        // All zeros should remain zeros
        for sample in samples {
            XCTAssertEqual(sample, 0.0, accuracy: 0.001)
        }
    }

    func testAGCReset() {
        let agc = AGCProcessor(type: .fast, sampleRate: 48000)
        var samples: [Float] = (0..<1000).map { _ in Float.random(in: -0.5...0.5) }
        agc.process(&samples)

        agc.reset()

        // Current gain should be reset
        XCTAssertEqual(agc.currentGain, 0.0, accuracy: 0.001)
    }

    func testAGCTypeSwitching() {
        let agc = AGCProcessor(type: .fast, sampleRate: 48000)
        agc.setType(.slow)
        // Just verify no crash
        var samples: [Float] = (0..<1000).map { _ in Float.random(in: -0.5...0.5) }
        agc.process(&samples)
        XCTAssertTrue(samples.allSatisfy { $0.isFinite })
    }

    func testSquelchMutesWeakSignal() {
        let squelch = SquelchProcessor(threshold: -20.0, enabled: true, hangTime: 0)
        var samples: [Float] = [Float](repeating: 0.001, count: 100) // Very quiet
        squelch.process(&samples)

        let allMuted = samples.allSatisfy { $0 == 0.0 }
        XCTAssertTrue(allMuted, "Squelch should mute weak signal")
    }

    func testSquelchPassesStrongSignal() {
        let squelch = SquelchProcessor(threshold: -20.0, enabled: true, hangTime: 0)
        var samples: [Float] = [Float](repeating: 0.5, count: 100) // Strong signal
        squelch.process(&samples)

        let anyNonZero = samples.contains { $0 != 0.0 }
        XCTAssertTrue(anyNonZero, "Squelch should pass strong signal")
    }

    func testSquelchDisabled() {
        let squelch = SquelchProcessor(threshold: -20.0, enabled: false)
        var samples: [Float] = [Float](repeating: 0.001, count: 100)
        squelch.process(&samples)

        // With squelch disabled, signal should pass through
        let anyNonZero = samples.contains { $0 != 0.0 }
        XCTAssertTrue(anyNonZero, "Disabled squelch should not mute")
    }
}

final class FilterDesignTests: XCTestCase {
    func testLowpassFIRReturnsCoefficients() {
        let coeffs = DSPFilterDesign.lowpassFIR(cutoff: 1000, sampleRate: 48000, transitionWidth: 500)
        XCTAssertGreaterThan(coeffs.count, 0, "Should return non-empty coefficients")
    }

    func testLowpassFIRNormalizedGains() {
        // Sum of coefficients should approximate 1.0 (unity DC gain)
        let coeffs = DSPFilterDesign.lowpassFIR(cutoff: 5000, sampleRate: 48000, transitionWidth: 1000)
        let sum = coeffs.reduce(0, +)
        XCTAssertEqual(sum, 1.0, accuracy: 0.01, "Lowpass filter should have unity DC gain")
    }

    func testLowpassFIRSymmetry() {
        let coeffs = DSPFilterDesign.lowpassFIR(cutoff: 1000, sampleRate: 48000, transitionWidth: 500)
        guard coeffs.count > 2 else { return }
        // FIR lowpass should be symmetric
        let mid = coeffs.count / 2
        for i in 0..<min(mid, 10) {
            let leftIdx = mid - 1 - i
            let rightIdx = mid + i + (coeffs.count % 2 == 0 ? 0 : 1)
            if leftIdx >= 0 && rightIdx < coeffs.count {
                XCTAssertEqual(coeffs[leftIdx], coeffs[rightIdx], accuracy: 0.001,
                               "FIR filter should be symmetric at indices \(leftIdx) and \(rightIdx)")
            }
        }
    }
}
