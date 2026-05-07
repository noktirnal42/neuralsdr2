//
// CWDecoder.swift
// NeuralSDR2
//
// CW (Morse Code) Decoder with Goertzel tone detection
// Sample-based timing, hysteresis threshold, state machine
//

import Foundation
import Accelerate

public enum CWState {
    case idle
    case marking
    case interElement
}

public struct MorseElement {
    public var isDot: Bool
    public var durationSamples: Int
    public init(isDot: Bool, durationSamples: Int) {
        self.isDot = isDot
        self.durationSamples = durationSamples
    }
}

public struct DecodedChar {
    public var character: Character
    public var confidence: Float
    public init(character: Character, confidence: Float) {
        self.character = character
        self.confidence = confidence
    }
}

public class CWDecoder: DSPBlock {
    public var name: String = "CW Decoder"
    public var sampleRate: Double
    public var inputChannels = 1
    public var outputChannels = 1

    public var centerFrequency: Double = 700.0
    private var bandwidth: Double = 100.0
    private var speed: Double = 20.0
    private var autoSpeed: Bool = true
    private var threshold: Float = 0.3

    private var state: CWState = .idle
    private var elements: [MorseElement] = []
    private var currentChar: String = ""
    private var decodedChars: [DecodedChar] = []

    private var samplesPerDotUnit: Int
    private var samplesPerDashUnit: Int
    private var samplesPerElementGap: Int
    private var samplesPerLetterGap: Int
    private var samplesPerWordGap: Int

    private var goertzelCoeff: Float = 0
    private var goertzelN: Int = 0
    private var goertzelQ0: Float = 0
    private var goertzelQ1: Float = 0
    private var goertzelQ2: Float = 0

    private var isToneOn: Bool = false
    private var toneOnSampleCount: Int = 0
    private var toneOffSampleCount: Int = 0
    private var totalSampleCount: Int = 0

    private var envelopeAvg: Float = 0
    private var envelopeAlpha: Float = 0.001

    public var onCharacter: ((Character) -> Void)?
    public var onWord: ((String) -> Void)?
    public var onText: ((String) -> Void)?
    public var onSpeedChange: ((Double) -> Void)?

    public init(sampleRate: Double = 48000) {
        self.sampleRate = sampleRate
        self.samplesPerDotUnit = 0
        self.samplesPerDashUnit = 0
        self.samplesPerElementGap = 0
        self.samplesPerLetterGap = 0
        self.samplesPerWordGap = 0
        calculateTiming()
        setupGoertzel()
    }

    private func calculateTiming() {
        let dotDuration = 1.2 / speed
        samplesPerDotUnit = Int(dotDuration * sampleRate)
        samplesPerDashUnit = samplesPerDotUnit * 3
        samplesPerElementGap = samplesPerDotUnit
        samplesPerLetterGap = samplesPerDotUnit * 3
        samplesPerWordGap = samplesPerDotUnit * 7
    }

    private func setupGoertzel() {
        goertzelN = max(Int(sampleRate / bandwidth), 64)
        let k = Int(0.5 + Double(goertzelN) * centerFrequency / sampleRate)
        goertzelCoeff = 2.0 * cos(2.0 * Float.pi * Float(k) / Float(goertzelN))
        goertzelQ0 = 0
        goertzelQ1 = 0
        goertzelQ2 = 0
    }

    private func goertzelProcessSample(_ sample: ComplexFloat) -> Float {
        goertzelQ0 = goertzelCoeff * goertzelQ1 - goertzelQ2 + sample.real
        goertzelQ2 = goertzelQ1
        goertzelQ1 = goertzelQ0
        goertzelCount += 1

        if goertzelCount >= goertzelN {
            let power = goertzelQ1 * goertzelQ1 + goertzelQ2 * goertzelQ2 - goertzelCoeff * goertzelQ1 * goertzelQ2
            goertzelQ0 = 0
            goertzelQ1 = 0
            goertzelQ2 = 0
            goertzelCount = 0
            return sqrt(max(power, 0))
        }
        return -1
    }

    private var goertzelCount: Int = 0
    private var lastGoertzelPower: Float = 0

    private func detectTone(_ sample: ComplexFloat) -> Bool {
        let power = goertzelProcessSample(sample)
        if power >= 0 {
            lastGoertzelPower = power
            envelopeAvg = envelopeAvg * (1 - envelopeAlpha) + power * envelopeAlpha
            let onThreshold = threshold * max(envelopeAvg, 0.001) * 3.0
            let offThreshold = onThreshold * 0.5
            if isToneOn {
                if power < offThreshold {
                    return false
                }
                return true
            } else {
                if power > onThreshold {
                    return true
                }
                return false
            }
        }
        return isToneOn
    }

    public func process(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        for i in 0..<count {
            output[i] = input[i]
        }

        for i in 0..<count {
            let tonePresent = detectTone(input[i])
            totalSampleCount += 1

            switch state {
            case .idle:
                if tonePresent {
                    state = .marking
                    toneOnSampleCount = 0
                    toneOffSampleCount = 0
                } else {
                    toneOffSampleCount += 1
                    if toneOffSampleCount >= samplesPerWordGap {
                        if !currentChar.isEmpty {
                            onWord?(currentChar)
                            onText?(currentChar)
                            currentChar = ""
                        }
                        toneOffSampleCount = 0
                    }
                }

            case .marking:
                if tonePresent {
                    toneOnSampleCount += 1
                    toneOffSampleCount = 0
                } else {
                    let duration = toneOnSampleCount
                    let isDot = duration < samplesPerDotUnit * 2
                    elements.append(MorseElement(isDot: isDot, durationSamples: duration))
                    state = .interElement
                    toneOffSampleCount = 1
                }

            case .interElement:
                if tonePresent {
                    if toneOffSampleCount >= samplesPerLetterGap {
                        decodeCharacter()
                    }
                    state = .marking
                    toneOnSampleCount = 1
                    toneOffSampleCount = 0
                } else {
                    toneOffSampleCount += 1
                    if toneOffSampleCount >= samplesPerWordGap {
                        decodeCharacter()
                        if !currentChar.isEmpty {
                            onWord?(currentChar)
                            onText?(currentChar + " ")
                            currentChar = ""
                        }
                        state = .idle
                    }
                }
            }
        }
    }

    private func decodeCharacter() {
        guard !elements.isEmpty else { return }

        var morse = ""
        for element in elements {
            morse += element.isDot ? "." : "-"
        }

        if let char = morseToChar(morse) {
            let confidence: Float = 0.9
            let decoded = DecodedChar(character: char, confidence: confidence)
            decodedChars.append(decoded)
            currentChar += String(char)
            onCharacter?(char)
        }

        if autoSpeed {
            autoDetectSpeed()
        }

        elements.removeAll()
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
            "---..": "8", "----.": "9", "-----": "0",
            ".-.-.-": ".", "--..--": ",", "..--..": "?",
            ".----.": "'", "-.-.--": "!", "-..-.": "/",
            "-.--.": "(", "-.--.-": ")", ".-...": "&",
            "---...": ":", "-.-.-.": ";", "-...-": "=",
            ".-.-.": "+", "-....-": "-", "..--.-": "_",
            ".-..-.": "\"", "...-..-": "$", ".--.-.": "@"
        ]
        return morseCodeDict[morse]
    }

    private func autoDetectSpeed() {
        var dotDurations: [Int] = []
        for element in elements {
            if element.isDot {
                dotDurations.append(element.durationSamples)
            }
        }
        if dotDurations.isEmpty, let first = elements.first {
            dotDurations.append(first.durationSamples / (first.isDot ? 1 : 3))
        }

        guard !dotDurations.isEmpty else { return }

        let avgDotSamples = Float(dotDurations.reduce(0, +)) / Float(dotDurations.count)
        guard avgDotSamples > 0 else { return }

        let detectedWPM = 1.2 * sampleRate / Double(avgDotSamples)
        if detectedWPM > 5 && detectedWPM < 60 {
            speed = speed * 0.7 + detectedWPM * 0.3
            calculateTiming()
            onSpeedChange?(speed)
        }
    }

    public func reset() {
        state = .idle
        elements.removeAll()
        currentChar = ""
        decodedChars.removeAll()
        toneOnSampleCount = 0
        toneOffSampleCount = 0
        totalSampleCount = 0
        isToneOn = false
        goertzelQ0 = 0
        goertzelQ1 = 0
        goertzelQ2 = 0
        goertzelCount = 0
        lastGoertzelPower = 0
        envelopeAvg = 0
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
            centerFrequency = centerFreq
            setupGoertzel()
        }
        if let bw = params["bandwidth"] as? Double {
            bandwidth = bw
            setupGoertzel()
        }
    }

    public func setSpeed(_ wpm: Double) {
        speed = wpm
        calculateTiming()
    }

    public func getDecodedText() -> String {
        return String(decodedChars.map { $0.character })
    }

    public var currentWPM: Double {
        return speed
    }
}

// MARK: - CW Skimmer

public class CWSkimmer {
    private var decoders: [CWDecoder] = []
    private var centerFrequencies: [Double] = [500, 700, 1000, 1500]
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

    public func addFrequency(_ freq: Double) {
        if !centerFrequencies.contains(freq) {
            let decoder = CWDecoder(sampleRate: sampleRate)
            decoder.centerFrequency = freq
            decoders.append(decoder)
            centerFrequencies.append(freq)
        }
    }

    public func removeFrequency(_ freq: Double) {
        if let index = centerFrequencies.firstIndex(of: freq) {
            centerFrequencies.remove(at: index)
            decoders.remove(at: index)
        }
    }

    public func getMonitoredFrequencies() -> [Double] {
        return centerFrequencies
    }
}

// MARK: - CW Encoder

public class CWEncoder {
    private var speed: Double = 20.0
    private var sampleRate: Double
    private var toneFrequency: Double = 700.0

    public init(sampleRate: Double = 48000, toneFrequency: Double = 700.0) {
        self.sampleRate = sampleRate
        self.toneFrequency = toneFrequency
    }

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

    public func setSpeed(_ wpm: Double) {
        speed = wpm
    }
}
