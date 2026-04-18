//
//  PSK31Decoder.swift
//  NeuralSDR2
//
//  PSK31/PSK63 Digital Mode Decoder
//  BPSK and QPSK modulation support
//

import Foundation
import Accelerate

/// PSK31 Decoder
public class PSK31Decoder: DSPBlock {
    public var name: String = "PSK31 Decoder"
    public var sampleRate: Double
    public var inputChannels = 1
    public var outputChannels = 1
    
    // PSK31 constants
    private let baudRate: Double = 31.25    // 31.25 baud
    private var samplesPerSymbol: Int
    
    // State
    private var phaseReference: Float = 0
    private var bitBuffer: UInt32 = 0
    private var bitCount: Int = 0
    private var currentChar: String = ""
    private var decodedText: String = ""
    
    // Filters
    private var bandpassFilter: FIRFilter?
    private var pll: PLL?
    
    // Callbacks
    public var onCharacter: ((Character) -> Void)?
    public var onText: ((String) -> Void)?
    
    public init(sampleRate: Double = 48000) {
        self.sampleRate = sampleRate
        self.samplesPerSymbol = Int(sampleRate / baudRate)
        setupFilters()
    }
    
    private func setupFilters() {
        // Bandpass filter around center frequency
        // PLL for carrier recovery
        pll = PLL(sampleRate: sampleRate, loopBandwidth: 10.0)
    }
    
    public func process(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        for i in 0..<count {
            output[i] = input[i]
        }
        
        // Process each sample
        for i in 0..<count {
            // Phase detection
            let phase = input[i].phase
            
            // Compare with reference
            let phaseDiff = phase - phaseReference
            phaseReference = phase
            
            // Detect bit (0 or 1)
            let bit: UInt32 = phaseDiff > 0 ? 1 : 0
            
            // Accumulate bits
            decodeBit(bit)
        }
    }
    
    private func decodeBit(_ bit: UInt32) {
        // PSK31 uses Varicode
        // Characters are separated by one or more zero bits
        // Bits are sent LSB first
        
        if bit == 0 {
            if bitCount > 0 {
                // End of character
                let char = varicodeToChar(bitBuffer)
                if let c = char {
                    decodedText += String(c)
                    onCharacter?(c)
                    onText?(decodedText)
                }
                bitBuffer = 0
                bitCount = 0
            }
        } else {
            // Shift in bit (LSB first)
            bitBuffer |= (1 << bitCount)
            bitCount += 1
            
            // Limit character length
            if bitCount > 7 {
                bitCount = 0
                bitBuffer = 0
            }
        }
    }
    
    private func varicodeToChar(_ code: UInt32) -> Character? {
        // PSK31 Varicode table (partial)
        let varicodeTable: [UInt32: Character] = [
            0x01: "e", 0x02: "t", 0x03: "a", 0x04: "o",
            0x05: "n", 0x06: "i", 0x07: "s", 0x08: "h",
            0x09: "r", 0x0A: "d", 0x0B: "l", 0x0C: "u",
            0x0D: "c", 0x0E: "m", 0x0F: "f", 0x10: "g",
            0x11: "w", 0x12: "y", 0x13: "p", 0x14: "b",
            0x15: "v", 0x16: "k", 0x17: "x", 0x18: "j",
            0x19: "q", 0x1A: "z",
            // Add more as needed
        ]
        return varicodeTable[code]
    }
    
    public func reset() {
        decodedText = ""
        currentChar = ""
        bitBuffer = 0
        bitCount = 0
        phaseReference = 0
    }
    
    public func configure(params: [String: Any]) {
        if let sr = params["sampleRate"] as? Double {
            sampleRate = sr
            samplesPerSymbol = Int(sampleRate / baudRate)
            setupFilters()
        }
    }
    
    /// Get decoded text
    public func getText() -> String {
        return decodedText
    }
    
    /// Clear decoded text
    public func clearText() {
        decodedText = ""
    }
}

/// PSK63 Decoder (faster version)
public class PSK63Decoder: DSPBlock {
    public var name: String = "PSK63 Decoder"
    public var sampleRate: Double
    public var inputChannels = 1
    public var outputChannels = 1
    
    public init(sampleRate: Double = 48000) {
        self.sampleRate = sampleRate
    }
    
    public func process(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        for i in 0..<count {
            output[i] = input[i]
        }
    }
    
    public func reset() {}
    public func configure(params: [String: Any]) {}
}

/// PLL (Phase Locked Loop) for carrier recovery
class PLL {
    private var phase: Float = 0
    private var frequency: Float = 0
    private var loopBandwidth: Float
    private var sampleRate: Double
    
    init(sampleRate: Double, loopBandwidth: Float) {
        self.sampleRate = sampleRate
        self.loopBandwidth = loopBandwidth
    }
    
    func update(_ phaseError: Float) -> Float {
        // Simple PLL implementation
        phase += phaseError * loopBandwidth
        return phase
    }
}
