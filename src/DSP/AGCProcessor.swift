//
//  AGCProcessor.swift
//  NeuralSDR2
//
//  Automatic Gain Control for audio and RF signals
//

import Foundation
import Accelerate
import os.log

/// AGC types
public enum AGCType {
    case fast      // Quick attack, slow decay
    case slow      // Slow attack and decay
    case custom    // User-defined parameters
}

/// Automatic Gain Control processor
public class AGCProcessor {
    private var threshold: Float       // Target level in dB
    private var attackTime: Float      // Attack time constant (ms)
    private var decayTime: Float       // Decay time constant (ms)
    private var hangTime: Float        // Hang time (ms)
    private var gain: Float            // Current gain
    private var minGain: Float         // Minimum gain
    private var maxGain: Float         // Maximum gain
    private var sampleRate: Double
    
    private var envelope: Float // Signal envelope
    private var lastGain: Float // Previous gain value
    private var hangCounter: Int // Hang time counter

    private var attackCoeff: Float = 0.0
    private var decayCoeff: Float = 0.0
    private var targetLevelLinear: Float = 0.0
    private var hangSamples: Int = 0

    private func updateCoefficients() {
        attackCoeff = Float(exp(-1.0 / (Double(attackTime) * 1000.0 / sampleRate)))
        decayCoeff = Float(exp(-1.0 / (Double(decayTime) * 1000.0 / sampleRate)))
        targetLevelLinear = Float(pow(10.0, Double(threshold) / 20.0))
        hangSamples = Int(Double(hangTime) * sampleRate / 1000.0)
    }

    public init(
        type: AGCType = .fast,
        sampleRate: Double = 48000,
        threshold: Float = -12.0,
        minGain: Float = 0.0,
        maxGain: Float = 20.0
    ) {
        self.sampleRate = sampleRate
        self.threshold = threshold
        self.minGain = minGain
        self.maxGain = maxGain
        self.gain = 0.0
        self.envelope = 0.0
        self.lastGain = 0.0
        self.hangCounter = 0

        // Set time constants based on type
        switch type {
        case .fast:
            attackTime = 5.0 // 5ms attack
            decayTime = 100.0 // 100ms decay
            hangTime = 50.0 // 50ms hang
        case .slow:
            attackTime = 50.0
            decayTime = 500.0
            hangTime = 200.0
        case .custom:
            attackTime = 10.0
            decayTime = 100.0
            hangTime = 50.0
        }

        updateCoefficients()
    }
    
    /// Process audio samples with AGC
    public func process(_ samples: inout [Float]) {
        guard !samples.isEmpty else { return }

        for i in 0..<samples.count {
            // Calculate envelope (peak detection)
            let absSample = abs(samples[i])
            envelope = max(absSample, envelope * attackCoeff)

            // Calculate target gain
            var targetGain: Float

            if envelope > 0 {
                targetGain = targetLevelLinear / envelope
            } else {
                targetGain = 1.0
            }

            // Limit gain
            targetGain = max(minGain, min(maxGain, targetGain))

            // Apply gain smoothing
            if targetGain < lastGain {
                // Attack - use attack coefficient
                gain = lastGain + (targetGain - lastGain) * (1.0 - attackCoeff)
            } else {
                // Decay - use decay coefficient
                if hangCounter > 0 {
                    hangCounter -= 1
                    gain = lastGain // Hold previous gain
                } else {
                    gain = lastGain + (targetGain - lastGain) * (1.0 - decayCoeff)
                }
            }

            // Apply gain
            samples[i] *= gain
            lastGain = gain

            // Reset hang counter if signal is strong
            if envelope > targetLevelLinear {
                hangCounter = hangSamples
            }
    }
}

/// Process complex IQ samples
    public func processComplex(_ samples: inout [ComplexFloat]) {
        guard !samples.isEmpty else { return }

        for i in 0..<samples.count {
            // Calculate magnitude
            let magnitude = samples[i].magnitude
            envelope = max(magnitude, envelope * attackCoeff)

            // Calculate target gain
            let targetLevel: Float = 0.5 // Target magnitude
            var targetGain: Float

            if envelope > 0 {
                targetGain = targetLevel / envelope
            } else {
                targetGain = 1.0
            }

            // Limit gain
            targetGain = max(minGain, min(maxGain, targetGain))

            // Apply gain smoothing
            if targetGain < lastGain {
                gain = lastGain + (targetGain - lastGain) * (1.0 - attackCoeff)
            } else {
                if hangCounter > 0 {
                    hangCounter -= 1
                    gain = lastGain
                } else {
                    gain = lastGain + (targetGain - lastGain) * (1.0 - decayCoeff)
                }
            }

            // Apply gain to both I and Q
            samples[i].real *= gain
            samples[i].imag *= gain

            lastGain = gain

            if envelope > targetLevel {
                hangCounter = hangSamples
            }
    }
}

/// Reset AGC state
    public func reset() {
        gain = 0.0
        envelope = 0.0
        lastGain = 0.0
        hangCounter = 0
    }
    
    /// Set AGC type
    public func setType(_ type: AGCType) {
        switch type {
        case .fast:
            attackTime = 5.0
            decayTime = 100.0
            hangTime = 50.0
        case .slow:
            attackTime = 50.0
            decayTime = 500.0
            hangTime = 200.0
        case .custom:
            break
        }
        updateCoefficients()
    }

    /// Set custom time constants
    public func setTimeConstants(attack: Float, decay: Float, hang: Float) {
        attackTime = attack
        decayTime = decay
        hangTime = hang
        updateCoefficients()
    }
    
    /// Get current gain in dB
    public var currentGainDB: Float {
        return 20.0 * log10(max(gain, 0.001))
    }
    
    /// Get current gain as linear value
    public var currentGain: Float {
        return gain
    }
}

// MARK: - Squelch Processor

/// Squelch processor for muting weak signals
public class SquelchProcessor {
    private var threshold: Float // Squelch threshold in dB
    private var enabled: Bool
    private var hangTime: Int // Hang time in samples
    private var hangCounter: Int
    private var isMuted: Bool
    private var thresholdLinear: Float

    private func updateThresholdLinear() {
        thresholdLinear = Float(pow(10.0, Double(threshold) / 20.0))
    }

    public init(threshold: Float = -90.0, enabled: Bool = false, hangTime: Int = 1000) {
        self.threshold = threshold
        self.enabled = enabled
        self.hangTime = hangTime
        self.hangCounter = 0
        self.isMuted = false
        self.thresholdLinear = 0.0
        updateThresholdLinear()
    }

    /// Process audio samples with squelch
    public func process(_ samples: inout [Float]) {
        guard enabled else { return }

        for i in 0..<samples.count {
            let level = abs(samples[i])

            if level > thresholdLinear {
                // Signal above threshold
                hangCounter = hangTime
                isMuted = false
            } else {
                // Signal below threshold
                if hangCounter > 0 {
                    hangCounter -= 1
                } else {
                    isMuted = true
                }
            }

            // Mute if squelched
            if isMuted {
                samples[i] = 0
            }
        }
    }

    /// Set squelch threshold
    public func setThreshold(_ value: Float) {
        threshold = value
        updateThresholdLinear()
    }

    /// Enable/disable squelch
    public func setEnabled(_ value: Bool) {
        enabled = value
        if !enabled {
            isMuted = false
        }
    }
    
    /// Get squelch state
    public var isSquelched: Bool {
        return isMuted
    }
}
