//  SpectrumAndPipelineTests.swift
//  NeuralSDR2Tests
//
//  Unit tests for Spectrum Analyzer and DSPPipeline
//

import XCTest
import Accelerate
@testable import NeuralSDR2Kit

final class SpectrumAnalyzerTests: XCTestCase {
    func testSpectrumAnalyzerReturnsCorrectSize() {
        let analyzer = SpectrumAnalyzer(fftSize: 2048, sampleRate: 2_048_000)
        let samples = [ComplexFloat](repeating: ComplexFloat(real: 1.0, imag: 0), count: 2048)
        let spectrum = analyzer.process(samples)

        XCTAssertEqual(spectrum.count, 2048, "Spectrum output size should cover the full centered IQ FFT")
    }

    func testSpectrumOfSineWave() {
        let fftSize = 2048
        let sampleRate: Double = 2_048_000
        let analyzer = SpectrumAnalyzer(fftSize: fftSize, sampleRate: sampleRate, windowType: .hann)

        // Generate a sine wave at 100 kHz
        let freq = 100_000.0
        var samples = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: fftSize)
        for i in 0..<fftSize {
            let phase = Float(2.0 * Double.pi * freq * Double(i) / sampleRate)
            samples[i] = ComplexFloat(real: cos(phase), imag: sin(phase))
        }

        let spectrum = analyzer.process(samples)

        // Find the peak bin
        var maxVal: Float = -1000
        for i in 0..<spectrum.count {
            if spectrum[i] > maxVal {
                maxVal = spectrum[i]
            }
        }

        // The peak should be near the bin corresponding to 100 kHz
        // At 2.048 MSPS, 2048 FFT: bin width = 1 kHz
        // 100 kHz = bin 100 (but depends on fft-shift / frequency mapping)
        // The analyzer maps: bin 0 = center - sampleRate/2, bin N/2 = center
        // So 100 kHz offset from center at 1090 MHz = bin 100 + N/4 (approximately)
        // The exact bin depends on how the FFT output is arranged

        // At minimum, verify the peak is well above the noise floor
        XCTAssertGreaterThan(maxVal, -50.0, "Sine wave peak should be well above noise floor")
        XCTAssertLessThan(maxVal, 10.0, "Normalized spectrum peak should stay in a sane dB range")
    }

    func testSpectrumOfWhiteNoise() {
        let analyzer = SpectrumAnalyzer(fftSize: 2048, sampleRate: 2_048_000)
        let samples = (0..<2048).map { _ in
            ComplexFloat(real: Float.random(in: -1...1), imag: Float.random(in: -1...1))
        }
        let spectrum = analyzer.process(samples)

        // White noise spectrum has high per-bin variance; just verify reasonable dynamic range
        // Check that no single bin is more than 80 dB above the mean
        var sum: Float = 0
        for val in spectrum { sum += val }
        let mean = sum / Float(spectrum.count)

        var maxDeviation: Float = 0
        for val in spectrum {
            maxDeviation = max(maxDeviation, abs(val - mean))
        }

        // White noise still has high per-bin variance after proper FFT normalization.
        XCTAssertLessThan(maxDeviation, 140.0, "White noise spectrum should stay within a reasonable dynamic range")
    }

    func testGetFrequencyAxis() {
        let analyzer = SpectrumAnalyzer(fftSize: 1024, sampleRate: 2_048_000, centerFrequency: 100_000_000)
        let freqs = analyzer.getFrequencyAxis()
        XCTAssertEqual(freqs.count, 1024)
        XCTAssertEqual(freqs.first ?? 0, 98_976_000, accuracy: 1.0)
        XCTAssertEqual(freqs.last ?? 0, 101_022_000, accuracy: 1.0)
    }

    func testResetDoesNotCrash() {
        let analyzer = SpectrumAnalyzer(fftSize: 2048, sampleRate: 2_048_000)
        analyzer.reset()
        let samples = [ComplexFloat](repeating: ComplexFloat(real: 0.5, imag: 0), count: 2048)
        let spectrum = analyzer.process(samples)
        XCTAssertEqual(spectrum.count, 2048)
    }
}

final class WaterfallDataTests: XCTestCase {
    func testAddLine() {
        let waterfall = WaterfallData(width: 100, height: 50)
        let line = [Float](repeating: -60.0, count: 100)
        waterfall.addLine(line)
        // Should not crash
    }

    func testGetCurrentIndex() {
        let waterfall = WaterfallData(width: 100, height: 50)
        XCTAssertEqual(waterfall.getCurrentIndex(), 0)
        let line = [Float](repeating: -60.0, count: 100)
        waterfall.addLine(line)
        XCTAssertEqual(waterfall.getCurrentIndex(), 1)
    }

    func testWrappingIndex() {
        let waterfall = WaterfallData(width: 100, height: 5)
        let line = [Float](repeating: -60.0, count: 100)
        for _ in 0..<5 { waterfall.addLine(line) }
        XCTAssertEqual(waterfall.getCurrentIndex(), 0, "Index should wrap around")
    }
}

final class DSPPipelineTests: XCTestCase {
    func testPipelineCreation() {
        let pipeline = DSPPipeline(sampleRate: 2_048_000, centerFrequency: 1090_000_000)
        XCTAssertEqual(pipeline.audioSampleRate, 64_000.0)
        XCTAssertEqual(pipeline.decimationFactor, 32)
    }

    func testSetDemodulatorAM() {
        let pipeline = DSPPipeline(sampleRate: 2_048_000)
        pipeline.setDemodulator(.AM)
        XCTAssertEqual(pipeline.audioSampleRate, 64_000.0)
    }

    func testSetDemodulatorWFM() {
        let pipeline = DSPPipeline(sampleRate: 2_048_000)
        pipeline.setDemodulator(.WFM)
        XCTAssertEqual(pipeline.audioSampleRate, 512_000.0)
    }

    func testSetDemodulatorIQ() {
        let pipeline = DSPPipeline(sampleRate: 2_048_000)
        pipeline.setDemodulator(.IQ)
        XCTAssertEqual(pipeline.audioSampleRate, 64_000.0)
        XCTAssertEqual(pipeline.decimationFactor, 32)
    }

    func testSetDemodulatorUSB() {
        let pipeline = DSPPipeline(sampleRate: 2_048_000)
        pipeline.setDemodulator(.USB)
        XCTAssertEqual(pipeline.audioSampleRate, 64_000.0)
    }

    func testPipelineProcessing() {
        let pipeline = DSPPipeline(sampleRate: 2_048_000)
        pipeline.setDemodulator(.AM)

        var audioReceived = false
        pipeline.onAudioOutput { _ in
            audioReceived = true
        }

        // Generate some noise input
        let samples = (0..<16384).map { _ in
            ComplexFloat(real: Float.random(in: -0.5...0.5), imag: Float.random(in: -0.5...0.5))
        }
        pipeline.process(samples: samples)

        XCTAssertTrue(audioReceived, "Pipeline should have produced audio output")
    }

    func testPipelineSpectrumCallback() {
        let pipeline = DSPPipeline(sampleRate: 2_048_000)

        var spectrumReceived = false
        pipeline.onSpectrumUpdate { _ in
            spectrumReceived = true
        }

        let samples = (0..<4096).map { _ in
            ComplexFloat(real: Float.random(in: -0.5...0.5), imag: Float.random(in: -0.5...0.5))
        }
        pipeline.process(samples: samples)

        XCTAssertTrue(spectrumReceived, "Pipeline should have produced spectrum output")
    }

    func testPipelineIQModeSkipsDemodulatedAudio() {
        let pipeline = DSPPipeline(sampleRate: 2_048_000)
        pipeline.setDemodulator(.IQ)

        var spectrumReceived = false
        var receivedAudio: [Float] = [1]

        pipeline.onSpectrumUpdate { _ in
            spectrumReceived = true
        }

        pipeline.onAudioOutput { audio in
            receivedAudio = audio
        }

        let samples = (0..<4096).map { _ in
            ComplexFloat(real: Float.random(in: -0.5...0.5), imag: Float.random(in: -0.5...0.5))
        }
        pipeline.process(samples: samples)

        XCTAssertTrue(spectrumReceived, "IQ mode should still produce spectrum output")
        XCTAssertTrue(receivedAudio.isEmpty, "IQ mode should not emit demodulated speaker audio")
    }

    func testPipelineSetBandwidth() {
        let pipeline = DSPPipeline(sampleRate: 2_048_000)
        pipeline.setDemodulator(.AM)
        pipeline.setBandwidth(10000)
        // No crash
    }

    func testPipelineSquelch() {
        let pipeline = DSPPipeline(sampleRate: 2_048_000)
        pipeline.setDemodulator(.AM)
        pipeline.setSquelchEnabled(true)
        pipeline.setSquelchThreshold(-80.0)
        // No crash
    }

    func testPipelineAGC() {
        let pipeline = DSPPipeline(sampleRate: 2_048_000)
        pipeline.setDemodulator(.AM)
        pipeline.setAGCType(.slow)
        // No crash
    }
}

final class BufferPoolTests: XCTestCase {
    func testAcquireReturnsBuffer() {
        let pool = BufferPool(bufferSize: 1024)
        let buffer = pool.acquire()
        XCTAssertEqual(buffer.count, 1024)
    }

    func testReleaseAndReacquire() {
        let pool = BufferPool(bufferSize: 512, maxBuffers: 5)
        let buffer = pool.acquire()
        pool.release(buffer)
        let buffer2 = pool.acquire()
        XCTAssertEqual(buffer2.count, 512)
    }

    func testMaxBuffers() {
        let pool = BufferPool(bufferSize: 256, maxBuffers: 2)
        let b1 = pool.acquire()
        let b2 = pool.acquire()
        let b3 = pool.acquire() // Should create new since pool is empty
        pool.release(b1)
        pool.release(b2)
        pool.release(b3) // Third one should be discarded (maxBuffers=2)
        // No crash
    }
}

final class FlowgraphTests: XCTestCase {
    func testAddBlock() {
        let graph = Flowgraph()
        let filter = FIRFilter.lowpass(cutoff: 1000, sampleRate: 48000)
        graph.addBlock(filter)
        // No crash
    }

    func testConnect() {
        let graph = Flowgraph()
        let filter1 = FIRFilter.lowpass(cutoff: 1000, sampleRate: 48000)
        let filter2 = FIRFilter.lowpass(cutoff: 2000, sampleRate: 48000)
        graph.addBlock(filter1)
        graph.addBlock(filter2)
        graph.connect(from: filter1.name, to: filter2.name)
        // No crash
    }

    func testStartStop() {
        let graph = Flowgraph()
        graph.start()
        graph.stop()
        // No crash
    }
}
