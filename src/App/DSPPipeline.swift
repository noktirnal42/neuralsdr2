//
//  DSPPipeline.swift
//  NeuralSDR2
//
//  Main DSP processing pipeline
//  Manages signal flow from hardware to audio output
//

import Foundation
import Accelerate

/// Manages the complete DSP chain
public class DSPPipeline {
    private var demodulator: DSPBlock?
    private var spectrumAnalyzer: SpectrumAnalyzer?
    private var filter: FIRFilter?
    
    private var sampleRate: Double
    private var centerFrequency: Double
    private var bandwidth: Double
    
    // Callbacks
    private var spectrumCallback: (([Float]) -> Void)?
    private var audioCallback: (([Float]) -> Void)?
    
    public init(sampleRate: Double = 2_048_000, centerFrequency: Double = 1090_000_000) {
        self.sampleRate = sampleRate
        self.centerFrequency = centerFrequency
        self.bandwidth = 15000  // Default bandwidth
        
        // Initialize spectrum analyzer
        self.spectrumAnalyzer = SpectrumAnalyzer(fftSize: 2048, sampleRate: sampleRate, centerFrequency: centerFrequency)
    }
    
    /// Set demodulator type
    public func setDemodulator(_ type: DemodulatorType) {
        switch type {
        case .AM:
            demodulator = AMDemodulator(bandwidth: bandwidth, sampleRate: sampleRate)
        case .NFM:
            demodulator = FMDemodulator(bandwidth: bandwidth, sampleRate: sampleRate, deemphasis: 50)
        case .WFM:
            demodulator = FMDemodulator(bandwidth: 200_000, sampleRate: sampleRate, deemphasis: 75)
        case .USB:
            demodulator = SSBDemodulator(bandwidth: 2400, sampleRate: sampleRate, sideband: .USB)
        case .LSB:
            demodulator = SSBDemodulator(bandwidth: 2400, sampleRate: sampleRate, sideband: .LSB)
        case .CW:
            demodulator = SSBDemodulator(bandwidth: 500, sampleRate: sampleRate, sideband: .USB)
        }
    }
    
    /// Process incoming IQ samples
    public func process(samples: [ComplexFloat]) {
        // Update spectrum analyzer
        if let spectrum = spectrumAnalyzer?.process(samples) {
            spectrumCallback?(spectrum)
        }
        
        // Apply demodulation
        var output = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: samples.count)
        demodulator?.process(samples, &output, count: samples.count)
        
        // Extract audio (real part)
        var audio = [Float](repeating: 0, count: output.count)
        for i in 0..<output.count {
            audio[i] = output[i].real
        }
        
        audioCallback?(audio)
    }
    
    /// Configure bandwidth
    public func setBandwidth(_ bw: Double) {
        bandwidth = bw
        // Could update filter coefficients dynamically
    }
    
    /// Set spectrum update callback
    public func onSpectrumUpdate(_ callback: @escaping ([Float]) -> Void) {
        spectrumCallback = callback
    }
    
    /// Set audio output callback
    public func onAudioOutput(_ callback: @escaping ([Float]) -> Void) {
        audioCallback = callback
    }
}

/// Demodulator types
public enum DemodulatorType: String, CaseIterable {
    case AM = "AM"
    case NFM = "NFM"
    case WFM = "WFM"
    case USB = "USB"
    case LSB = "LSB"
    case CW = "CW"
}

// MARK: - Audio Output

/// CoreAudio audio output handler
public class AudioOutputHandler {
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    
    public init() {}
    
    public func start(sampleRate: Double = 48000, channels: UInt16 = 2) {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        
        audioEngine?.attach(playerNode!)
        
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: channels
        )
        
        audioEngine?.connect(playerNode!, to: audioEngine!.mainMixerNode, format: format)
        
        do {
            try audioEngine?.start()
            playerNode?.play()
        } catch {
            print("Audio engine error: \(error)")
        }
    }
    
    public func play(buffer: [Float]) {
        // Convert to AVAudioPCMBuffer and play
        // Implementation would depend on buffer format
    }
    
    public func stop() {
        playerNode?.stop()
        audioEngine?.stop()
    }
}
