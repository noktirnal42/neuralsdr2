//
//  CWDecoder.swift
//  NeuralSDR2
//
//  CW (Morse Code) Decoder with auto-speed detection
//  Supports multiple Morse code modes and CW skimmer functionality
//

import Foundation
import Accelerate

/// CW Decoder states
enum CWState {
    case idle
    case dot
    case dash
    case letterSpace
    case wordSpace
}

/// Morse code element
struct MorseElement {
    var isDot: Bool
    var duration: Float
    var timestamp: Date
}

/// Decoded character
struct DecodedChar {
    var character: Character
    var timestamp: Date
    var confidence: Float
}

/// CW Decoder class
public class CWDecoder: DSPBlock {
    public var name: String = "CW Decoder"
    public var sampleRate: Double
    public var inputChannels = 1
    public var outputChannels = 1
    
    // Configuration
    private var centerFrequency: Double = 700.0  // CW tone frequency (Hz)
    private var bandwidth: Double = 100.0        // Filter bandwidth (Hz)
    private var speed: Double = 20.0             // WPM (words per minute)
    private var autoSpeed: Bool = true           // Auto-detect speed
    private var threshold: Float = 0.3           // Detection threshold
    
    // State variables
    private var state: CWState = .idle
    private var elementStart: Date?
    private var currentDotCount: Int = 0
    private var currentDashCount: Int = 0
    private var elements: [MorseElement] = []
    private var currentChar: String = ""
    private var decodedChars: [DecodedChar] = []
    
    // Timing
    private var dotDuration: Float = 0.06       // 20 WPM dot = 60ms
    private var dashDuration: Float = 0.18      // 3 dots
    private var elementGap: Float = 0.06        // 1 dot
    private var letterGap: Float = 0.18         // 3 dots
    private var wordGap: Float = 0.42           // 7 dots
    
    // Filters
    private var bandpassFilter: FIRFilter?
    private var envelopeFilter: FIRFilter?
    
    // Callbacks
    public var onCharacter: ((Character) -> Void)?
    public var onWord: ((String) -> Void)?
    public var onSpeedChange: ((Double) -> Void)?
    
    public init(sampleRate: Double = 48000) {
        self.sampleRate = sampleRate
        calculateTiming()
        setupFilters()
    }
    
    public func process(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        // Copy input to output (pass-through)
        for i in 0..<count {
            output[i] = input[i]
        }
        
        // Process through bandpass filter
        var filtered = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: count)
        bandpassFilter?.process(input, &filtered, count: count)
        
        // Calculate envelope
        var envelope = [Float](repeating: 0, count: count)
        for i in 0..<count {
            envelope[i] = filtered[i].magnitude
        }
        
        // Detect dots and dashes
        detectElements(envelope: envelope)
    }
    
    private func detectElements(envelope: [Float]) {
        let now = Date()
        let threshold = self.threshold
        
        for (index, amplitude) in envelope.enumerated() {
            if amplitude > threshold {
                // Signal detected
                if state == .idle {
                    state = .dot
                    elementStart = now
                }
            } else {
                // No signal
                if state != .idle {
                    // Element ended
                    guard let start = elementStart else { continue }
                    let duration = Float(now.timeIntervalSince(start))
                    
                    // Classify as dot or dash
                    let isDot = duration < dotDuration * 1.5
                    let element = MorseElement(isDot: isDot, duration: duration, timestamp: start)
                    elements.append(element)
                    
                    if isDot {
                        currentDotCount += 1
                    } else {
                        currentDashCount += 1
                    }
                    
                    state = .letterSpace
                }
            }
        }
        
        // Check for letter or word space
        if state == .letterSpace {
            if let lastStart = elementStart {
                let gap = Float(now.timeIntervalSince(lastStart))
                if gap > letterGap {
                    decodeCharacter()
                    elements.removeAll()
                    state = .idle
                }
                if gap > wordGap {
                    decodeWord()
                    elements.removeAll()
                    currentChar = ""
                    state = .idle
                }
            }
        }
    }
    
    private func decodeCharacter() {
        guard !elements.isEmpty else { return }
        
        // Convert elements to Morse code string
        var morse = ""
        for element in elements {
            morse += element.isDot ? "." : "-"
        }
        
        // Translate to character
        if let char = morseToChar(morse) {
            let decoded = DecodedChar(character: char, timestamp: Date(), confidence: 0.9)
            decodedChars.append(decoded)
            currentChar += String(char)
            onCharacter?(char)
        }
        
        elements.removeAll()
        currentDotCount = 0
        currentDashCount = 0
    }
    
    private func decodeWord() {
        if !currentChar.isEmpty {
            onWord?(currentChar)
            currentChar = ""
        }
    }
    
    private func morseToChar(_ morse: String) -> Character? {
        let morseCodeDict: [String: Character] = [
            ".-": "A", "-...": "B", "-.-.": "C", "-..": "D", ".": "E",
            "..-.": "F", "--.": "G", "....": "H", "..": "I", ".---": "J",
            "-.-": "K", ".-..": "L", "--": "M", "-.": "N", "---": "O",
            ".--.": "P", "--.-": "Q", ".-.": "R", "...": "S", "-": "T",
            "..-": "U", "...-": "V", ".--": "W", "-..-": "X", "-.--": "Y",
            "--..": "Z", ".----": "1", "..---": "2", "...--": "3",
            "....-": "4", ".....": "5", "-....": "6", "--...": "7",
            "---..": "8", "----.": "9", "-----": "0"
        ]
        return morseCodeDict[morse]
    }
    
    private func calculateTiming() {
        // WPM to timing conversion
        // Standard: PARIS is 50 dots long
        // At 20 WPM: 50 dots = 1 minute / 20 = 3 seconds
        // Dot duration = 3 / 50 = 0.06 seconds
        dotDuration = Float(1.2 / speed)
        dashDuration = dotDuration * 3
        elementGap = dotDuration
        letterGap = dotDuration * 3
        wordGap = dotDuration * 7
    }
    
    private func setupFilters() {
        // Create bandpass filter for CW tone
        let lowCut = centerFrequency - bandwidth / 2
        let highCut = centerFrequency + bandwidth / 2
        
        // Simple bandpass using lowpass - highpass
        // Implementation would go here
    }
    
    public func reset() {
        state = .idle
        elements.removeAll()
        currentChar = ""
        decodedChars.removeAll()
        currentDotCount = 0
        currentDashCount = 0
    }
    
    public func configure(params: [String: Any]) {
        if let speed = params["speed"] as? Double {
            self.speed = speed
            calculateTiming()
        }
        if let autoSpeed = params["autoSpeed"] as? Bool {
            self.autoSpeed = autoSpeed
        }
        if let threshold = params["threshold"] as? Float {
            self.threshold = threshold
        }
        if let centerFreq = params["centerFrequency"] as? Double {
            self.centerFrequency = centerFreq
            setupFilters()
        }
    }
    
    /// Set CW speed manually
    public func setSpeed(_ wpm: Double) {
        speed = wpm
        calculateTiming()
    }
    
    /// Auto-detect speed from received elements
    private func autoDetectSpeed() {
        guard elements.count > 2 else { return }
        
        // Calculate average dot duration from elements
        var dotDurations: [Float] = []
        for element in elements {
            if element.isDot {
                dotDurations.append(element.duration)
            }
        }
        
        if !dotDurations.isEmpty {
            let avgDot = dotDurations.reduce(0, +) / Float(dotDurations.count)
            let detectedWPM = 1.2 / Double(avgDot)
            
            // Smooth speed changes
            speed = speed * 0.7 + detectedWPM * 0.3
            calculateTiming()
            onSpeedChange?(speed)
        }
    }
    
    /// Get decoded text
    public func getDecodedText() -> String {
        return String(decodedChars.map { $0.character })
    }
    
    /// Get current WPM
    public var currentWPM: Double {
        return speed
    }
}

// MARK: - CW Skimmer

/// CW Skimmer - decodes multiple CW signals simultaneously
public class CWSkimmer {
    private var decoders: [CWDecoder] = []
    private var centerFrequencies: [Double] = [500, 700, 1000, 1500]  // Common CW frequencies
    private var sampleRate: Double
    
    public init(sampleRate: Double = 48000) {
        self.sampleRate = sampleRate
        setupDecoders()
    }
    
    private func setupDecoders() {
        for freq in centerFrequencies {
            let decoder = CWDecoder(sampleRate: sampleRate)
            decoder.centerFrequency = freq
            decoders.append(decoder)
        }
    }
    
    /// Process samples through all decoders
    public func process(_ samples: [ComplexFloat]) -> [(frequency: Double, text: String)] {
        var results: [(frequency: Double, text: String)] = []
        
        for decoder in decoders {
            var output = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: samples.count)
            decoder.process(samples, &output, count: samples.count)
            
            let text = decoder.getDecodedText()
            if !text.isEmpty {
                results.append((frequency: decoder.centerFrequency, text: text))
            }
        }
        
        return results
    }
    
    /// Add frequency to monitor
    public func addFrequency(_ freq: Double) {
        if !centerFrequencies.contains(freq) {
            let decoder = CWDecoder(sampleRate: sampleRate)
            decoder.centerFrequency = freq
            decoders.append(decoder)
            centerFrequencies.append(freq)
        }
    }
    
    /// Remove frequency
    public func removeFrequency(_ freq: Double) {
        if let index = centerFrequencies.firstIndex(of: freq) {
            centerFrequencies.remove(at: index)
            decoders.remove(at: index)
        }
    }
    
    /// Get all monitored frequencies
    public func getMonitoredFrequencies() -> [Double] {
        return centerFrequencies
    }
}

// MARK: - Morse Code Encoder (for practice)

/// Morse Code Encoder
public class CWEncoder {
    private var speed: Double = 20.0
    private var sampleRate: Double
    private var toneFrequency: Double = 700.0
    
    public init(sampleRate: Double = 48000, toneFrequency: Double = 700.0) {
        self.sampleRate = sampleRate
        self.toneFrequency = toneFrequency
    }
    
    /// Encode text to Morse code audio
    public func encode(_ text: String) -> [Float] {
        var audio: [Float] = []
        let dotDuration = Int(sampleRate * 1.2 / speed)
        let dashDuration = dotDuration * 3
        let elementGap = dotDuration
        let letterGap = dotDuration * 3
        let wordGap = dotDuration * 7
        
        let morseDict: [Character: String] = [
            "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".",
            "F": "..-.", "G": "--.", "H": "....", "I": "..", "J": ".---",
            "K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---",
            "P": ".--.", "Q": "--.-", "R": ".-.", "S": "...", "T": "-",
            "U": "..-", "V": "...-", "W": ".--", "X": "-..-", "Y": "-.--",
            "Z": "--..", "1": ".----", "2": "..---", "3": "...--",
            "4": "....-", "5": ".....", "6": "-....", "7": "--...",
            "8": "---..", "9": "----.", "0": "-----"
        ]
        
        let words = text.uppercased().components(separatedBy: " ")
        
        for (wordIndex, word) in words.enumerated() {
            if wordIndex > 0 {
                audio.append(contentsOf: generateSilence(wordGap))
            }
            
            for (charIndex, char) in word.enumerated() {
                if charIndex > 0 {
                    audio.append(contentsOf: generateSilence(letterGap))
                }
                
                if let morse = morseDict[char] {
                    for (elementIndex, element) in morse.enumerated() {
                        if elementIndex > 0 {
                            audio.append(contentsOf: generateSilence(elementGap))
                        }
                        
                        if element == "." {
                            audio.append(contentsOf: generateTone(dotDuration))
                        } else {
                            audio.append(contentsOf: generateTone(dashDuration))
                        }
                    }
                }
            }
        }
        
        return audio
    }
    
    private func generateTone(_ samples: Int) -> [Float] {
        let omega = 2.0 * Double.pi * toneFrequency / sampleRate
        var tone: [Float] = []
        tone.reserveCapacity(samples)
        
        for i in 0..<samples {
            let t = Double(i)
            tone.append(Float(sin(omega * t)))
        }
        
        return tone
    }
    
    private func generateSilence(_ samples: Int) -> [Float] {
        return [Float](repeating: 0, count: samples)
    }
    
    /// Set encoding speed
    public func setSpeed(_ wpm: Double) {
        speed = wpm
    }
}
