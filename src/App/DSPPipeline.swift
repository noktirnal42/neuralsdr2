//
// DSPPipeline.swift
// NeuralSDR2
//
// Main DSP processing pipeline
// Manages signal flow from hardware to audio output
//
// Signal flow:
//   IQ Input (2.048 MSPS)
//     → Spectrum Analyzer (parallel branch)
//     → Channel Filter (FIR lowpass at bandwidth/2)
//     → Decimation (by 32 for narrow modes → 64 kHz, by 4 for WFM → 512 kHz)
//     → Demodulator (AM/FM/SSB/CW at decimated rate)
//     → AGC (at audio rate)
//     → Squelch (at audio rate)
//     → Audio Output callback
//

import Foundation
import Accelerate

/// The main DSP processing pipeline that transforms raw IQ samples into audio output.
///
/// The pipeline implements the full signal chain: channel filtering, decimation,
/// demodulation, AGC, and squelch. It also provides a parallel spectrum analyzer branch.
///
/// ```swift
/// let pipeline = DSPPipeline(sampleRate: 2_048_000, centerFrequency: 1090_000_000)
/// pipeline.setDemodulator(.AM)
/// pipeline.onAudioOutput { audioSamples in
///     // Handle audio
/// }
/// pipeline.process(samples: iqSamples)
/// ```
public class DSPPipeline {
    private var sampleRate: Double
    public var centerFrequency: Double
    private var bandwidth: Double

    /// The audio output sample rate after decimation, in Hz.
    public private(set) var audioSampleRate: Double = 64_000
    /// The decimation factor applied to the input sample rate.
    public private(set) var decimationFactor: Int = 32

    private var demodulator: DSPBlock?
    private var spectrumAnalyzer: SpectrumAnalyzer?
    private var channelFilter: FIRFilter?
    private var agcProcessor: AGCProcessor?
    private var squelchProcessor: SquelchProcessor?
    private var spectrumCallback: (([Float]) -> Void)?
    private var audioCallback: (([Float]) -> Void)?
    private var filteredIQ: [ComplexFloat] = []
    private var decimatedIQ: [ComplexFloat] = []
    private var demodOutput: [ComplexFloat] = []
    private var audio: [Float] = []
    public private(set) var rdsDecoder: RDSDecoder?
    private var rdsCallback: (() -> Void)?
    private var currentDemodulatorType: DemodulatorType = .NFM

    /// Creates a new DSP pipeline with the given sample rate and center frequency.
    /// - Parameters:
    ///   - sampleRate: The input sample rate in Hz (default 2.048 MSPS).
    ///   - centerFrequency: The center frequency in Hz (default 1090 MHz for ADS-B).
    public init(sampleRate: Double = 2_048_000, centerFrequency: Double = 1090_000_000) {
        self.sampleRate = sampleRate
        self.centerFrequency = centerFrequency
        self.bandwidth = 15000

        spectrumAnalyzer = SpectrumAnalyzer(fftSize: 2048, sampleRate: sampleRate, centerFrequency: centerFrequency, useGPU: false)
        squelchProcessor = SquelchProcessor(threshold: -90.0, enabled: false)

        rebuildChannelFilter()
    }

    private func rebuildChannelFilter() {
        let cutoff = bandwidth / 2.0
        let transitionWidth = max(500.0, bandwidth * 0.15)
        let coeffs = DSPFilterDesign.lowpassFIR(
            cutoff: cutoff,
            sampleRate: sampleRate,
            transitionWidth: transitionWidth,
            attenuation: 60
        )
        channelFilter = FIRFilter(name: "Channel Filter", coefficients: coeffs, sampleRate: sampleRate)
    }

    /// Select the demodulation mode. This reconfigures the internal demodulator, AGC, and decimation.
    /// - Parameter type: The demodulation mode to use.
    public func setDemodulator(_ type: DemodulatorType) {
        currentDemodulatorType = type
        switch type {
        case .IQ:
            decimationFactor = 32
            audioSampleRate = sampleRate / Double(decimationFactor)
            demodulator = nil
            agcProcessor = nil
            rdsDecoder = nil

        case .AM:
            decimationFactor = 32
            audioSampleRate = sampleRate / Double(decimationFactor)
            demodulator = AMDemodulator(bandwidth: bandwidth, sampleRate: audioSampleRate)
            agcProcessor = AGCProcessor(type: .slow, sampleRate: audioSampleRate)
            rdsDecoder = nil

        case .NFM:
            decimationFactor = 32
            audioSampleRate = sampleRate / Double(decimationFactor)
            demodulator = FMDemodulator(
                name: "NFM Demodulator",
                bandwidth: bandwidth,
                sampleRate: audioSampleRate,
                deemphasis: 50,
                peakDeviation: 5000
            )
            agcProcessor = AGCProcessor(type: .fast, sampleRate: audioSampleRate)
            rdsDecoder = nil

        case .WFM:
            decimationFactor = 4
            audioSampleRate = sampleRate / Double(decimationFactor)
            demodulator = FMDemodulator(
                name: "WFM Demodulator",
                bandwidth: 200_000,
                sampleRate: audioSampleRate,
                deemphasis: 75,
                peakDeviation: 75_000
            )
            agcProcessor = AGCProcessor(type: .slow, sampleRate: audioSampleRate)
            rdsDecoder = RDSDecoder(sampleRate: audioSampleRate)

        case .USB:
            decimationFactor = 32
            audioSampleRate = sampleRate / Double(decimationFactor)
            demodulator = SSBDemodulator(bandwidth: 2400, sampleRate: audioSampleRate, sideband: .USB)
            agcProcessor = AGCProcessor(type: .slow, sampleRate: audioSampleRate)
            rdsDecoder = nil

        case .LSB:
            decimationFactor = 32
            audioSampleRate = sampleRate / Double(decimationFactor)
            demodulator = SSBDemodulator(bandwidth: 2400, sampleRate: audioSampleRate, sideband: .LSB)
            agcProcessor = AGCProcessor(type: .slow, sampleRate: audioSampleRate)
            rdsDecoder = nil

        case .CW:
            decimationFactor = 32
            audioSampleRate = sampleRate / Double(decimationFactor)
            demodulator = SSBDemodulator(bandwidth: 500, sampleRate: audioSampleRate, sideband: .USB)
            agcProcessor = AGCProcessor(type: .fast, sampleRate: audioSampleRate)
            rdsDecoder = nil

        case .DMR:
            decimationFactor = 32
            audioSampleRate = sampleRate / Double(decimationFactor)
            demodulator = DMRDecoder(sampleRate: audioSampleRate)
            agcProcessor = AGCProcessor(type: .fast, sampleRate: audioSampleRate)

        case .P25:
            decimationFactor = 32
            audioSampleRate = sampleRate / Double(decimationFactor)
            demodulator = P25Decoder(sampleRate: audioSampleRate)
            agcProcessor = AGCProcessor(type: .fast, sampleRate: audioSampleRate)

        case .DSTAR:
            decimationFactor = 32
            audioSampleRate = sampleRate / Double(decimationFactor)
            demodulator = DSTARDecoder(sampleRate: audioSampleRate)
            agcProcessor = AGCProcessor(type: .fast, sampleRate: audioSampleRate)
        }
    }

    /// Process a buffer of IQ samples through the full signal chain.
    ///
    /// The pipeline applies channel filtering, decimation, demodulation, AGC,
    /// squelch, and delivers audio output via the callback registered with
    /// ``onAudioOutput(_:)``. Spectrum data is delivered via ``onSpectrumUpdate(_:)``.
    /// - Parameter samples: An array of ``ComplexFloat`` IQ samples.
    public func process(samples: [ComplexFloat]) {
        let count = samples.count
        guard count > 0 else { return }

        if let spectrum = spectrumAnalyzer?.process(samples) {
            spectrumCallback?(spectrum)
        }

        if filteredIQ.count < count {
            filteredIQ = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: count)
        }
        if let filter = channelFilter {
            samples.withUnsafeBufferPointer { inputPtr in
                filteredIQ.withUnsafeMutableBufferPointer { outputPtr in
                    filter.process(inputPtr.baseAddress!, outputPtr.baseAddress!, count: count)
                }
            }
        } else {
            for i in 0..<count {
                filteredIQ[i] = samples[i]
            }
        }

        let decCount = (count + decimationFactor - 1) / decimationFactor
        if decimatedIQ.count < decCount {
            decimatedIQ = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: decCount)
        }
        for i in 0..<decCount {
            decimatedIQ[i] = filteredIQ[i * decimationFactor]
        }

        guard decCount > 0 else { return }

        if currentDemodulatorType == .IQ {
            audioCallback?([])
            return
        }

        if demodOutput.count < decCount {
            demodOutput = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: decCount)
        }
        decimatedIQ.withUnsafeBufferPointer { inputPtr in
            demodOutput.withUnsafeMutableBufferPointer { outputPtr in
                demodulator?.process(inputPtr.baseAddress!, outputPtr.baseAddress!, count: decCount)
            }
        }

        if audio.count < decCount {
            audio = [Float](repeating: 0, count: decCount)
        }
        for i in 0..<decCount {
            audio[i] = demodOutput[i].real
        }

        agcProcessor?.process(&audio)
        squelchProcessor?.process(&audio)

        // Process RDS if in WFM mode
        if let rds = rdsDecoder {
            let rdsInput = decimatedIQ
            rdsInput.withUnsafeBufferPointer { inputPtr in
                var dummy = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: rdsInput.count)
                dummy.withUnsafeMutableBufferPointer { outputPtr in
                    rds.process(inputPtr.baseAddress!, outputPtr.baseAddress!, count: rdsInput.count)
                }
            }
            rdsCallback?()
        }

        audioCallback?(audio)
    }

    /// Set the channel bandwidth in Hz. This rebuilds the channel filter.
    /// - Parameter bw: The new bandwidth in Hz.
    public func setBandwidth(_ bw: Double) {
        bandwidth = bw
        rebuildChannelFilter()
        if let am = demodulator as? AMDemodulator {
            am.setBandwidth(bw)
        } else if let fm = demodulator as? FMDemodulator {
            fm.setBandwidth(bw)
        } else if let ssb = demodulator as? SSBDemodulator {
            ssb.setBandwidth(bw)
        }
    }

    public func setSquelchEnabled(_ enabled: Bool) {
        squelchProcessor?.setEnabled(enabled)
    }

    public func setSquelchThreshold(_ threshold: Float) {
        squelchProcessor?.setThreshold(threshold)
    }

    public func setAGCType(_ type: AGCType) {
        agcProcessor?.setType(type)
    }

    /// Register a callback to receive spectrum data updates (in dB).
    /// - Parameter callback: A closure called with the current spectrum magnitudes.
    public func onSpectrumUpdate(_ callback: @escaping ([Float]) -> Void) {
        spectrumCallback = callback
    }

    /// Register a callback to receive demodulated audio output.
    /// - Parameter callback: A closure called with the current audio samples.
    public func onAudioOutput(_ callback: @escaping ([Float]) -> Void) {
        audioCallback = callback
    }

    public func setRDSCallbacks(_ callback: @escaping () -> Void) {
        rdsCallback = callback
    }
}

/// The demodulation modes supported by the DSP pipeline.
///
/// Each case corresponds to a specific demodulator configuration:
/// - `AM`: Amplitude modulation (envelope detection)
/// - `NFM`: Narrowband FM (5 kHz deviation)
/// - `WFM`: Wideband FM broadcast (75 kHz deviation)
/// - `USB`: Upper sideband
/// - `LSB`: Lower sideband
/// - `CW`: Continuous wave (Morse code, USB-based)
public enum DemodulatorType: String, CaseIterable, Sendable {
    case IQ = "IQ"
    case AM = "AM"
    case NFM = "NFM"
    case WFM = "WFM"
    case USB = "USB"
    case LSB = "LSB"
    case CW = "CW"
    case DMR = "DMR"
    case P25 = "P25"
    case DSTAR = "DSTAR"
}
