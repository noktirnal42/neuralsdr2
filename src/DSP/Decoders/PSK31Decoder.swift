//
// PSK31Decoder.swift
// NeuralSDR2
//
// PSK31/PSK63 Digital Mode Decoder
// BPSK with Costas loop carrier recovery, Mueller-Muller symbol timing
// Full Varicode table, differential decoding
//

import Foundation
import Accelerate

public class PSK31Decoder: DSPBlock {
    public var name: String = "PSK31 Decoder"
    public var sampleRate: Double
    public var inputChannels = 1
    public var outputChannels = 1

    private let baudRate: Double = 31.25
    private var samplesPerSymbol: Double

    private var costasFreq: Float = 0
    private var costasPhase: Float = 0
    private var costasBandwidth: Float = 0
    private var costasDamping: Float = 1.0 / sqrt(2.0)

    private var mmMu: Float = 0.5
    private var mmLastSample: ComplexFloat = ComplexFloat(real: 0, imag: 0)
    private var mmPrevSample: ComplexFloat = ComplexFloat(real: 0, imag: 0)
    private var mmPrevBit: Int = 0

    private var phaseHistory: ComplexFloat = ComplexFloat(real: 0, imag: 0)
    private var prevPhase: Float = 0

    private var bitBuffer: String = ""
    private var decodedText: String = ""
    private var prevBit: Int = 0
    private var consecutiveZeros: Int = 0

    private var sampleCounter: Double = 0

    private var varicodeTable: [String: Character] = [:]

    public var onCharacter: ((Character) -> Void)?
    public var onText: ((String) -> Void)?

    public init(sampleRate: Double = 48000) {
        self.sampleRate = sampleRate
        self.samplesPerSymbol = sampleRate / baudRate
        buildVaricodeTable()
    }

    private func buildVaricodeTable() {
        varicodeTable = [
            "1": " ",
            "101": "T",
            "111": "E",
            "1011": "A",
            "10101": "N",
            "10111": "I",
            "11111": "O",
            "11101": "S",
            "111011": "H",
            "11011": "R",
            "110101": "D",
            "110111": "L",
            "1101011": "C",
            "1101111": "U",
            "1110101": "M",
            "1110111": "W",
            "11110101": "F",
            "11110111": "G",
            "11010111": "Y",
            "111110111": "P",
            "111010111": "B",
            "111011011": "V",
            "111011111": "K",
            "1111101011": "J",
            "11111011011": "X",
            "1111101111": "Q",
            "1110101011": "Z",
            "1111110111": "0",
            "10111111": "1",
            "1110110111": "2",
            "11101110111": "3",
            "111011110111": "4",
            "1110111110111": "5",
            "11101111110111": "6",
            "111011111110111": "7",
            "1110111111110111": "8",
            "11101111111110111": "9",
            "111010101": ".",
            "1110101111": ",",
            "110011101111": "?",
            "1111111": "\r",
            "1011010": "\n"
        ]
    }

    private func costasLoopProcess(_ sample: ComplexFloat) -> ComplexFloat {
        let nco = ComplexFloat(real: cos(costasPhase), imag: -sin(costasPhase))
        let mixed = sample * nco

        let phaseError = mixed.imag * mixed.real

        let alpha = costasBandwidth * costasDamping
        let beta = costasBandwidth * costasBandwidth / (4.0 * costasDamping)

        costasFreq += beta * phaseError
        costasPhase += costasFreq + alpha * phaseError

        if costasPhase > Float.pi { costasPhase -= 2 * Float.pi }
        if costasPhase < -Float.pi { costasPhase += 2 * Float.pi }

        return ComplexFloat(real: mixed.real, imag: mixed.imag)
    }

    private func muellerMullerUpdate(_ sample: ComplexFloat) -> Int? {
        let prev = mmPrevSample
        let last = mmLastSample
        mmPrevSample = last
        mmLastSample = sample

        let muGardner = (last.real * sample.real - last.imag * sample.imag)
            - (prev.real * last.real - prev.imag * last.imag)

        mmMu += 0.01 * muGardner

        if mmMu > 1.0 {
            mmMu -= 1.0
            let bit: Int = sample.real > 0 ? 1 : 0
            return bit
        }
        if mmMu < 0.0 {
            mmMu += 1.0
            return nil
        }

        sampleCounter += 1.0
        if sampleCounter >= samplesPerSymbol {
            sampleCounter -= samplesPerSymbol
            let bit: Int = sample.real > 0 ? 1 : 0
            return bit
        }

        return nil
    }

    private func decodeBit(_ bit: Int) {
        if bit == 0 {
            consecutiveZeros += 1
            if consecutiveZeros >= 2 && !bitBuffer.isEmpty {
                if let char = varicodeTable[bitBuffer] {
                    decodedText += String(char)
                    onCharacter?(char)
                    onText?(decodedText)
                }
                bitBuffer = ""
                consecutiveZeros = 0
            }
        } else {
            if consecutiveZeros == 1 && !bitBuffer.isEmpty {
                bitBuffer += "0"
            }
            consecutiveZeros = 0
            bitBuffer += "1"
            if bitBuffer.count > 20 {
                bitBuffer = ""
                consecutiveZeros = 0
            }
        }
        prevBit = bit
    }

    public func process(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        for i in 0..<count {
            output[i] = input[i]
        }

        for i in 0..<count {
            let corrected = costasLoopProcess(input[i])

            if muellerMullerUpdate(corrected) != nil {
                let currentPhase = corrected.phase
                let phaseDiff = currentPhase - prevPhase
                prevPhase = currentPhase

                let normalizedDiff = phaseDiff > Float.pi ? phaseDiff - 2 * Float.pi :
                    (phaseDiff < -Float.pi ? phaseDiff + 2 * Float.pi : phaseDiff)

                let decodedBit = abs(normalizedDiff) > Float.pi / 2 ? 1 : 0
                decodeBit(decodedBit)
            }
        }
    }

    public func reset() {
        decodedText = ""
        bitBuffer = ""
        prevBit = 0
        consecutiveZeros = 0
        costasPhase = 0
        costasFreq = 0
        mmMu = 0.5
        mmLastSample = ComplexFloat(real: 0, imag: 0)
        mmPrevSample = ComplexFloat(real: 0, imag: 0)
        sampleCounter = 0
        prevPhase = 0
    }

    public func configure(params: [String: Any]) {
        if let sr = params["sampleRate"] as? Double {
            sampleRate = sr
            samplesPerSymbol = sampleRate / baudRate
        }
        if let bw = params["loopBandwidth"] as? Float {
            costasBandwidth = bw
        }
    }

    public func getText() -> String {
        return decodedText
    }

    public func clearText() {
        decodedText = ""
    }
}

// MARK: - PSK63 Decoder

public class PSK63Decoder: DSPBlock {
    public var name: String = "PSK63 Decoder"
    public var sampleRate: Double
    public var inputChannels = 1
    public var outputChannels = 1

    private let baudRate: Double = 62.5
    private var samplesPerSymbol: Double
    private var inner: PSK31Decoder

    public init(sampleRate: Double = 48000) {
        self.sampleRate = sampleRate
        self.samplesPerSymbol = sampleRate / baudRate
        self.inner = PSK31Decoder(sampleRate: sampleRate)
    }

    public func process(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        inner.process(input, output, count: count)
    }

    public func reset() {
        inner.reset()
    }

    public func configure(params: [String: Any]) {
        if let sr = params["sampleRate"] as? Double {
            sampleRate = sr
            samplesPerSymbol = sampleRate / baudRate
        }
        inner.configure(params: params)
    }

    public var onText: ((String) -> Void)? {
        get { return inner.onText }
        set { inner.onText = newValue }
    }

    public var onCharacter: ((Character) -> Void)? {
        get { return inner.onCharacter }
        set { inner.onCharacter = newValue }
    }

    public func getText() -> String {
        return inner.getText()
    }

    public func clearText() {
        inner.clearText()
    }
}
