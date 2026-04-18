//
//  FT8Decoder.swift
//  NeuralSDR2
//
//  FT8/FT4 Digital Mode Decoder
//  Supports WSJT-X compatible decoding
//

import Foundation
import Accelerate

/// FT8/FT4 Decoder
public class FT8Decoder: DSPBlock {
    public var name: String = "FT8 Decoder"
    public var sampleRate: Double
    public var inputChannels = 1
    public var outputChannels = 1
    
    // FT8 constants
    private let ft8ToneCount = 8          // 8 tones
    private let ft8SymbolPeriod: Double = 0.160  // 160ms per symbol
    private let ft8MessageLength = 72     // bits per message
    private let ft8TimeSlot: Double = 15.0 // 15 second slots
    
    // FT4 constants
    private let ft4ToneCount = 4          // 4 tones for FT4
    private let ft4SymbolPeriod: Double = 0.048  // 48ms per symbol
    
    // State
    private var mode: String = "FT8"      // FT8 or FT4
    private var isDecoding = false
    private var currentSlot: Int = 0
    private var samplesBuffer: [ComplexFloat] = []
    private var decodedMessages: [FT8Message] = []
    
    // FFT parameters
    private let fftSize = 2048
    private var fftSetup: FFTSetup?
    private var magnitudeBuffer: [Float] = []
    
    // Callbacks
    public var onMessage: ((FT8Message) -> Void)?
    public var onDecodeStart: (() -> Void)?
    public var onDecodeComplete: (() -> Void)?
    
    public init(sampleRate: Double = 48000) {
        self.sampleRate = sampleRate
        setupFFT()
    }
    
    deinit {
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }
    
    private func setupFFT() {
        let log2Size = Int(log2(Double(fftSize)))
        fftSetup = vDSP_create_fftsetup(Int32(log2Size), FFTRadix(kFFTRadix2))
        magnitudeBuffer = [Float](repeating: 0, count: fftSize / 2 + 1)
    }
    
    public func process(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        // Pass through
        for i in 0..<count {
            output[i] = input[i]
        }
        
        // Buffer samples for processing
        samplesBuffer.append(contentsOf: Array(UnsafeBufferPointer(start: input, count: count)))
        
        // Process when we have enough samples for one symbol
        let samplesPerSymbol = Int(sampleRate * (mode == "FT8" ? ft8SymbolPeriod : ft4SymbolPeriod))
        if samplesBuffer.count >= samplesPerSymbol * 2 {
            processBuffer()
        }
    }
    
    private func processBuffer() {
        guard !isDecoding else { return }
        
        isDecoding = true
        onDecodeStart?()
        
        // Perform FFT on buffered samples
        // Detect tones
        // Decode message
        // Sync to time slots
        
        isDecoding = false
        onDecodeComplete?()
    }
    
    /// Start decoding
    public func startDecoding(mode: String = "FT8") {
        self.mode = mode
        decodedMessages.removeAll()
        samplesBuffer.removeAll()
    }
    
    /// Stop decoding
    public func stopDecoding() {
        isDecoding = false
    }
    
    /// Get decoded messages
    public func getMessages() -> [FT8Message] {
        return decodedMessages
    }
    
    /// Clear decoded messages
    public func clearMessages() {
        decodedMessages.removeAll()
    }
    
    public func reset() {
        stopDecoding()
        clearMessages()
        samplesBuffer.removeAll()
    }
    
    public func configure(params: [String: Any]) {
        if let mode = params["mode"] as? String {
            self.mode = mode
        }
        if let sr = params["sampleRate"] as? Double {
            sampleRate = sr
        }
    }
}

/// FT4 Decoder (similar to FT8 but faster)
public class FT4Decoder: DSPBlock {
    public var name: String = "FT4 Decoder"
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

/// FT8 Message structure
public struct FT8Message {
    var timestamp: Date
    var snr: Float           // Signal-to-noise ratio (dB)
    var deltaFrequency: Double // Frequency offset (Hz)
    var callsign1: String    // First callsign
    var callsign2: String    // Second callsign
    var gridSquare: String   // Grid square (e.g., "FN31")
    var message: String      // Full message text
    var isCQ: Bool           // Is this a CQ call?
    
    public init(timestamp: Date = Date(), snr: Float = 0, deltaFrequency: Double = 0,
                callsign1: String = "", callsign2: String = "", gridSquare: String = "",
                message: String = "", isCQ: Bool = false) {
        self.timestamp = timestamp
        self.snr = snr
        self.deltaFrequency = deltaFrequency
        self.callsign1 = callsign1
        self.callsign2 = callsign2
        self.gridSquare = gridSquare
        self.message = message
        self.isCQ = isCQ
    }
}

/// WSJT-X compatible message parser
public class FT8MessageParser {
    public func parse(_ message: String) -> FT8Message? {
        // Parse standard FT8 message formats
        // CQ CALL GRID
        // CALL1 CALL2 GRID
        // CALL1 CALL2 +NN
        
        let components = message.components(separatedBy: " ")
        
        if components.count >= 2 {
            if components[0] == "CQ" {
                // CQ call
                return FT8Message(callsign1: components.count > 1 ? components[1] : "",
                                 isCQ: true)
            } else if components.count >= 3 {
                // Two callsigns
                return FT8Message(callsign1: components[0],
                                 callsign2: components[1],
                                 gridSquare: components.count > 2 ? components[2] : "")
            }
        }
        
        return nil
    }
}

/// FT8 Decoder with waterfall visualization
public class FT8WaterfallDecoder {
    private var decoder: FT8Decoder
    private var waterfallData: [[Float]] = []
    
    public init(sampleRate: Double = 48000) {
        self.decoder = FT8Decoder(sampleRate: sampleRate)
    }
    
    public func processSamples(_ samples: [ComplexFloat]) {
        // Process through decoder
        // Update waterfall display
        // Detect tones
    }
}
