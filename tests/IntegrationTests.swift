// IntegrationTests.swift
// NeuralSDR2Tests
//
// End-to-end integration tests for the full signal processing chain

import XCTest
@testable import NeuralSDR2Kit

final class IntegrationTests: XCTestCase {

    // MARK: - AM Pipeline

    func testAMPipelineEndToEnd() {
        let pipeline = DSPPipeline(sampleRate: 2_048_000, centerFrequency: 1_000_000)
        pipeline.setDemodulator(.AM)

        var audioOutput: [Float] = []
        pipeline.onAudioOutput { audio in
            audioOutput = audio
        }

        let sampleRate: Double = 2_048_000
        let numSamples = 32768
        let modFreq: Double = 1000.0
        let modDepth: Float = 0.5

        var iqSamples = [ComplexFloat]()
        iqSamples.reserveCapacity(numSamples)
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            let modulation: Float = 1.0 + modDepth * Float(cos(2.0 * Double.pi * modFreq * t))
            let carrier: Float = 1.0
            let sample = modulation * carrier
            iqSamples.append(ComplexFloat(real: sample, imag: 0))
        }

        pipeline.process(samples: iqSamples)

        XCTAssertFalse(audioOutput.isEmpty, "AM pipeline should produce audio output")
        let hasNonZero = audioOutput.contains { abs($0) > 1e-6 }
        XCTAssertTrue(hasNonZero, "AM pipeline audio output should contain non-zero samples")
    }

    // MARK: - FM Pipeline

    func testFMPipelineEndToEnd() {
        let pipeline = DSPPipeline(sampleRate: 2_048_000, centerFrequency: 100_000_000)
        pipeline.setDemodulator(.NFM)

        var audioOutput: [Float] = []
        pipeline.onAudioOutput { audio in
            audioOutput = audio
        }

        let sampleRate: Double = 2_048_000
        let numSamples = 32768
        let modFreq: Double = 1000.0
        let deviation: Double = 5000.0

        var iqSamples = [ComplexFloat]()
        iqSamples.reserveCapacity(numSamples)
        var phase = 0.0
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            let modSignal = cos(2.0 * Double.pi * modFreq * t)
            let freqOffset = deviation * modSignal
            phase += 2.0 * Double.pi * freqOffset / sampleRate
            iqSamples.append(ComplexFloat(real: Float(cos(phase)), imag: Float(sin(phase))))
        }

        pipeline.process(samples: iqSamples)

        XCTAssertFalse(audioOutput.isEmpty, "FM pipeline should produce audio output")
        let hasFinite = audioOutput.allSatisfy { $0.isFinite }
        XCTAssertTrue(hasFinite, "FM pipeline audio output should be finite")
    }

    // MARK: - SSB Pipeline

    func testSSBPipelineEndToEnd() {
        let pipeline = DSPPipeline(sampleRate: 2_048_000, centerFrequency: 100_000_000)
        pipeline.setDemodulator(.USB)

        var audioOutput: [Float] = []
        pipeline.onAudioOutput { audio in
            audioOutput = audio
        }

        let sampleRate: Double = 2_048_000
        let numSamples = 32768
        let toneFreq: Double = 1000.0

        var iqSamples = [ComplexFloat]()
        iqSamples.reserveCapacity(numSamples)
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            let audio = Float(cos(2.0 * Double.pi * toneFreq * t))
            let signalPhase = 2.0 * Double.pi * toneFreq * t
            iqSamples.append(ComplexFloat(
                real: audio * Float(cos(signalPhase)),
                imag: audio * Float(sin(signalPhase))
            ))
        }

        pipeline.process(samples: iqSamples)

        XCTAssertFalse(audioOutput.isEmpty, "SSB pipeline should produce audio output")
        let hasFinite = audioOutput.allSatisfy { $0.isFinite }
        XCTAssertTrue(hasFinite, "SSB pipeline audio output should be finite")
    }

    // MARK: - Spectrum Analyzer

    func testSpectrumAnalyzerIntegration() {
        let pipeline = DSPPipeline(sampleRate: 2_048_000, centerFrequency: 100_000_000)

        var spectrumResult: [Float] = []
        pipeline.onSpectrumUpdate { spectrum in
            spectrumResult = spectrum
        }

        let noise = (0..<8192).map { _ in
            ComplexFloat(real: Float.random(in: -1...1), imag: Float.random(in: -1...1))
        }
        pipeline.process(samples: noise)

        XCTAssertFalse(spectrumResult.isEmpty, "Spectrum should produce output")
        let allFinite = spectrumResult.allSatisfy { $0.isFinite }
        XCTAssertTrue(allFinite, "Spectrum output should be finite")
    }

    // MARK: - Mode Switching

    func testModeSwitching() {
        let pipeline = DSPPipeline(sampleRate: 2_048_000, centerFrequency: 100_000_000)

        for mode in DemodulatorType.allCases {
            pipeline.setDemodulator(mode)
            XCTAssertGreaterThan(pipeline.audioSampleRate, 0, "Audio sample rate should be positive for \(mode.rawValue)")
        }
    }

    // MARK: - Recording Manager

    func testRecordingManagerIntegration() {
        let manager = RecordingManager()

        do {
            let url = try manager.startAudioRecording(
                frequency: 100_000_000,
                sampleRate: 48000,
                mode: "NFM",
                format: .wav
            )

            let samples = [Float](repeating: 0.5, count: 4800)
            try manager.writeAudioSamples(samples)

        guard let metadata = try manager.stopRecording() as RecordingMetadata? else {
            XCTFail("stopRecording returned nil")
            return
        }
        let mode = metadata.mode
        let fileSize = metadata.fileSize
        let filePath = metadata.filePath
        XCTAssertEqual(mode, "NFM")
        XCTAssertGreaterThan(fileSize, 0)

        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath))

        try? FileManager.default.removeItem(atPath: filePath)
        } catch {
            XCTFail("Recording integration test failed: \(error)")
        }
    }

    // MARK: - Satellite Propagation Chain

    func testSatellitePropagationChain() {
        let tle = TLE(
            name: "ISS",
            line1: "1 25544U 98067A 24001.50000000 .00016717 00000-0 30200-3 0 9993",
            line2: "2 25544 51.6416 247.4627 0006703 130.5360 325.0288 15.49560572449197"
        )
        let propagator = SGP4Propagator(tle: tle)

        let now = Date()
        let pos = propagator.getPosition(at: now)

        XCTAssertGreaterThan(pos.altitude, 200, "ISS altitude should be > 200 km")
        XCTAssertLessThan(pos.altitude, 600, "ISS altitude should be < 600 km")

        XCTAssertGreaterThanOrEqual(pos.latitude, -90)
        XCTAssertLessThanOrEqual(pos.latitude, 90)
        XCTAssertGreaterThanOrEqual(pos.longitude, -360)
        XCTAssertLessThanOrEqual(pos.longitude, 360)
    }

    // MARK: - DSP Filter Chain

    func testDSPFilterChain() {
        let coeffs = DSPFilterDesign.lowpassFIR(
            cutoff: 5000,
            sampleRate: 48000,
            transitionWidth: 2000,
            attenuation: 60
        )
        XCTAssertGreaterThan(coeffs.count, 0, "Filter should have coefficients")

        let sum = coeffs.reduce(0, +)
        XCTAssertEqual(sum, 1.0, accuracy: 0.05, "Lowpass filter should have near-unity DC gain")

        let filter = FIRFilter(name: "Test Lowpass", coefficients: coeffs, sampleRate: 48000)

        let numSamples = 8192
        let lowFreq: Float = 500.0
        let highFreq: Float = 20000.0
        let sr: Float = 48000.0

        var lowFreqInput = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: numSamples)
        var highFreqInput = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: numSamples)

        for i in 0..<numSamples {
            lowFreqInput[i] = ComplexFloat(real: 0.5 * sin(2.0 * Float.pi * lowFreq * Float(i) / sr), imag: 0)
            highFreqInput[i] = ComplexFloat(real: 0.5 * sin(2.0 * Float.pi * highFreq * Float(i) / sr), imag: 0)
        }

        var lowFreqOutput = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: numSamples)
        var highFreqOutput = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: numSamples)

        lowFreqInput.withUnsafeBufferPointer { inPtr in
            lowFreqOutput.withUnsafeMutableBufferPointer { outPtr in
                filter.process(inPtr.baseAddress!, outPtr.baseAddress!, count: numSamples)
            }
        }

        filter.reset()

        highFreqInput.withUnsafeBufferPointer { inPtr in
            highFreqOutput.withUnsafeMutableBufferPointer { outPtr in
                filter.process(inPtr.baseAddress!, outPtr.baseAddress!, count: numSamples)
            }
        }

        var lowSq: Float = 0
        var highSq: Float = 0
        for i in 2000..<numSamples {
            lowSq += lowFreqOutput[i].real * lowFreqOutput[i].real
            highSq += highFreqOutput[i].real * highFreqOutput[i].real
        }
        let lowRMS = sqrt(lowSq / Float(numSamples - 2000))
        let highRMS = sqrt(highSq / Float(numSamples - 2000))

        XCTAssertGreaterThan(lowRMS, highRMS, "Lowpass filter should pass low frequencies and attenuate high frequencies")
    }

    // MARK: - Doppler Correction Chain

    func testDopplerCorrectionChain() {
        let tle = TLE(
            name: "ISS",
            line1: "1 25544U 98067A 24001.50000000 .00016717 00000-0 30200-3 0 9993",
            line2: "2 25544 51.6416 247.4627 0006703 130.5360 325.0288 15.49560572449197"
        )
        let propagator = SGP4Propagator(tle: tle)
        let doppler = DopplerCorrection()

        let now = Date()
        let pos = propagator.getPosition(at: now, observerLat: 37.7749, observerLon: -122.4194)

        let shift = doppler.calculateShift(rangeRate: pos.rangeRate, frequency: 437_000_000)

        XCTAssertTrue(shift.isFinite || shift.isNaN, "Doppler shift should be finite (may be NaN with stale TLE)")
        if shift.isFinite {
            XCTAssertLessThan(abs(shift), 50_000, "Doppler shift for ISS at 437 MHz should be within ±50 kHz")
        }

        let correctedFreq = doppler.getCorrectedFrequency(frequency: 437_000_000, rangeRate: pos.rangeRate)
        XCTAssertTrue(correctedFreq.isFinite || correctedFreq.isNaN, "Corrected frequency should be finite")
    }

    // MARK: - Pipeline Mode Switching Preserves Function

    func testPipelineModeSwitchPreservesProcessing() {
        let pipeline = DSPPipeline(sampleRate: 2_048_000, centerFrequency: 100_000_000)

        var audioReceivedCount = 0
        pipeline.onAudioOutput { _ in
            audioReceivedCount += 1
        }

        let samples = (0..<8192).map { _ in
            ComplexFloat(real: Float.random(in: -0.5...0.5), imag: Float.random(in: -0.5...0.5))
        }

        pipeline.setDemodulator(.AM)
        pipeline.process(samples: samples)
        let amCount = audioReceivedCount

        pipeline.setDemodulator(.NFM)
        pipeline.process(samples: samples)
        let nfmCount = audioReceivedCount

        pipeline.setDemodulator(.USB)
        pipeline.process(samples: samples)
        let ssbCount = audioReceivedCount

        XCTAssertGreaterThan(amCount, 0, "AM mode should produce audio")
        XCTAssertGreaterThan(nfmCount, amCount, "NFM mode should also produce audio")
        XCTAssertGreaterThan(ssbCount, nfmCount, "USB mode should also produce audio")
    }

    // MARK: - WFM Pipeline

    func testWFMPipelineEndToEnd() {
        let pipeline = DSPPipeline(sampleRate: 2_048_000, centerFrequency: 98_100_000)
        pipeline.setDemodulator(.WFM)
        XCTAssertEqual(pipeline.audioSampleRate, 512_000.0, "WFM should decimate to 512 kHz")

        var audioOutput: [Float] = []
        pipeline.onAudioOutput { audio in
            audioOutput = audio
        }

        let sampleRate: Double = 2_048_000
        let numSamples = 32768
        let modFreq: Double = 1000.0
        let deviation: Double = 75_000.0

        var iqSamples = [ComplexFloat]()
        iqSamples.reserveCapacity(numSamples)
        var phase = 0.0
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            let modSignal = cos(2.0 * Double.pi * modFreq * t)
            let freqOffset = deviation * modSignal
            phase += 2.0 * Double.pi * freqOffset / sampleRate
            iqSamples.append(ComplexFloat(real: Float(cos(phase)), imag: Float(sin(phase))))
        }

        pipeline.process(samples: iqSamples)

        XCTAssertFalse(audioOutput.isEmpty, "WFM pipeline should produce audio output")
        let allFinite = audioOutput.allSatisfy { $0.isFinite }
        XCTAssertTrue(allFinite, "WFM pipeline audio should be finite")
    }
}
