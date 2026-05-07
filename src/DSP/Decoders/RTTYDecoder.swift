//
// RTTYDecoder.swift
// NeuralSDR2
//
// RTTY (Radio Teletype) Decoder
// Dual Goertzel detectors for mark/space, symbol timing PLL, Baudot decode
//

import Foundation

public class RTTYDecoder: DSPBlock {
    public var name: String = "RTTY Decoder"
    public var sampleRate: Double
    public var inputChannels = 1
    public var outputChannels = 1

    private let baudRate: Double = 45.45
    private var shift: Double = 170.0
    private var samplesPerBit: Int

    private var markFrequency: Double = 2125.0
    private var spaceFrequency: Double = 1275.0

    private var markGoertzelN: Int = 0
    private var markGoertzelCoeff: Float = 0
    private var markQ0: Float = 0
    private var markQ1: Float = 0
    private var markQ2: Float = 0
    private var markGoertzelCount: Int = 0

    private var spaceGoertzelN: Int = 0
    private var spaceGoertzelCoeff: Float = 0
    private var spaceQ0: Float = 0
    private var spaceQ1: Float = 0
    private var spaceQ2: Float = 0
    private var spaceGoertzelCount: Int = 0

    private var lastMarkPower: Float = 0
    private var lastSpacePower: Float = 0

    private var pllPhase: Double = 0
    private var pllFreq: Double = 0
    private var pllCenterFreq: Double = 0

    private enum RxState {
        case waitingForStart
        case inStartBit
        case inDataBit
        case inStopBit
    }

    private var rxState: RxState = .waitingForStart
    private var bitIndex: Int = 0
    private var dataBits: UInt8 = 0
    private var isMark: Bool = true
    private var lastIsMark: Bool = true

    private var lettersMode: Bool = true

    private var decodedText: String = ""

    public var onCharacter: ((Character) -> Void)?
    public var onText: ((String) -> Void)?

    public init(sampleRate: Double = 48000) {
        self.sampleRate = sampleRate
        self.samplesPerBit = Int(sampleRate / baudRate)
        self.pllCenterFreq = baudRate
        self.pllFreq = baudRate
        setupGoertzel()
    }

    private func setupGoertzel() {
        markGoertzelN = max(samplesPerBit, 64)
        let markK = Int(0.5 + Double(markGoertzelN) * markFrequency / sampleRate)
        markGoertzelCoeff = 2.0 * cos(2.0 * Float.pi * Float(markK) / Float(markGoertzelN))
        markQ0 = 0; markQ1 = 0; markQ2 = 0
        markGoertzelCount = 0

        spaceGoertzelN = max(samplesPerBit, 64)
        let spaceK = Int(0.5 + Double(spaceGoertzelN) * spaceFrequency / sampleRate)
        spaceGoertzelCoeff = 2.0 * cos(2.0 * Float.pi * Float(spaceK) / Float(spaceGoertzelN))
        spaceQ0 = 0; spaceQ1 = 0; spaceQ2 = 0
        spaceGoertzelCount = 0
    }

    private func goertzelMark(_ sample: ComplexFloat) {
        markQ0 = markGoertzelCoeff * markQ1 - markQ2 + sample.real
        markQ2 = markQ1
        markQ1 = markQ0
        markGoertzelCount += 1
        if markGoertzelCount >= markGoertzelN {
            lastMarkPower = markQ1 * markQ1 + markQ2 * markQ2 - markGoertzelCoeff * markQ1 * markQ2
            markQ0 = 0; markQ1 = 0; markQ2 = 0
            markGoertzelCount = 0
        }
    }

    private func goertzelSpace(_ sample: ComplexFloat) {
        spaceQ0 = spaceGoertzelCoeff * spaceQ1 - spaceQ2 + sample.real
        spaceQ2 = spaceQ1
        spaceQ1 = spaceQ0
        spaceGoertzelCount += 1
        if spaceGoertzelCount >= spaceGoertzelN {
            lastSpacePower = spaceQ1 * spaceQ1 + spaceQ2 * spaceQ2 - spaceGoertzelCoeff * spaceQ1 * spaceQ2
            spaceQ0 = 0; spaceQ1 = 0; spaceQ2 = 0
            spaceGoertzelCount = 0
        }
    }

    private func detectMarkSpace(_ sample: ComplexFloat) -> Bool {
        goertzelMark(sample)
        goertzelSpace(sample)
        return lastMarkPower > lastSpacePower
    }

    private func pllAdvance() -> Bool {
        pllPhase += pllFreq / sampleRate
        if pllPhase >= 1.0 {
            pllPhase -= 1.0
            return true
        }
        return false
    }

    private func pllCorrect(_ transition: Bool) {
        if transition {
            let error = pllPhase - 0.5
            pllFreq += error * 0.01 * baudRate
        }
        let freqError = pllFreq - pllCenterFreq
        pllFreq -= freqError * 0.0001
    }

    public func process(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        for i in 0..<count {
            output[i] = input[i]
        }

        for i in 0..<count {
            let currentIsMark = detectMarkSpace(input[i])

            let transition = currentIsMark != lastIsMark
            lastIsMark = currentIsMark

            let symbolEdge = pllAdvance()
            if transition {
                pllCorrect(true)
            }

            if !symbolEdge { continue }

            isMark = currentIsMark

            switch rxState {
            case .waitingForStart:
                if !isMark {
                    rxState = .inStartBit
                    pllPhase = 0.5
                    bitIndex = 0
                    dataBits = 0
                }

            case .inStartBit:
                if isMark {
                    rxState = .waitingForStart
                } else {
                    rxState = .inDataBit
                    bitIndex = 0
                    dataBits = 0
                }

            case .inDataBit:
                if isMark {
                    dataBits |= (1 << bitIndex)
                }
                bitIndex += 1
                if bitIndex >= 5 {
                    rxState = .inStopBit
                }

            case .inStopBit:
                if isMark {
                    decodeBaudot(dataBits)
                }
                rxState = .waitingForStart
            }
        }
    }

    private func decodeBaudot(_ code: UInt8) {
        if code == 0x1B {
            lettersMode = false
            return
        }
        if code == 0x1F {
            lettersMode = true
            return
        }

        let char: Character?
        if lettersMode {
            char = baudotLetter(code)
        } else {
            char = baudotFigure(code)
        }

        if let c = char {
            decodedText += String(c)
            onCharacter?(c)
            onText?(decodedText)
        }
    }

    private func baudotLetter(_ code: UInt8) -> Character? {
        let table: [UInt8: Character] = [
            0x00: "\0",
            0x01: "E", 0x02: "\n", 0x03: "A", 0x04: " ",
            0x05: "S", 0x06: "I", 0x07: "U", 0x08: "\r",
            0x09: "D", 0x0A: "R", 0x0B: "J", 0x0C: "N",
            0x0D: "F", 0x0E: "C", 0x0F: "K", 0x10: "T",
            0x11: "Z", 0x12: "L", 0x13: "W", 0x14: "H",
            0x15: "Y", 0x16: "P", 0x17: "Q", 0x18: "O",
            0x19: "B", 0x1A: "G", 0x1C: "M", 0x1D: "X",
            0x1E: "V"
        ]
        return table[code]
    }

    private func baudotFigure(_ code: UInt8) -> Character? {
        let table: [UInt8: Character] = [
            0x00: "\0",
            0x01: "3", 0x02: "\n", 0x03: "-", 0x04: " ",
            0x05: "'", 0x06: "8", 0x07: "7", 0x08: "\r",
            0x09: "⚠", 0x0A: "4", 0x0B: "🔔", 0x0C: ",",
            0x0D: "!", 0x0E: ":", 0x0F: "(", 0x10: "5",
            0x11: "\"", 0x12: ")", 0x13: "2", 0x14: "#",
            0x15: "6", 0x16: "0", 0x17: "1", 0x18: "9",
            0x19: "?", 0x1A: "&", 0x1C: ".", 0x1D: "/",
            0x1E: ";"
        ]
        return table[code]
    }

    public func reset() {
        rxState = .waitingForStart
        bitIndex = 0
        dataBits = 0
        isMark = true
        lastIsMark = true
        lettersMode = true
        decodedText = ""
        pllPhase = 0
        pllFreq = pllCenterFreq
        markQ0 = 0; markQ1 = 0; markQ2 = 0; markGoertzelCount = 0
        spaceQ0 = 0; spaceQ1 = 0; spaceQ2 = 0; spaceGoertzelCount = 0
        lastMarkPower = 0
        lastSpacePower = 0
    }

    public func configure(params: [String: Any]) {
        if let sr = params["sampleRate"] as? Double {
            sampleRate = sr
            samplesPerBit = Int(sampleRate / baudRate)
            setupGoertzel()
        }
        if let newShift = params["shift"] as? Double {
            shift = newShift
            spaceFrequency = markFrequency - shift
            setupGoertzel()
        }
        if let mark = params["markFrequency"] as? Double {
            markFrequency = mark
            spaceFrequency = markFrequency - shift
            setupGoertzel()
        }
        if let baud = params["baudRate"] as? Double {
            pllCenterFreq = baud
            pllFreq = baud
            samplesPerBit = Int(sampleRate / baud)
        }
    }

    public func getText() -> String {
        return decodedText
    }

    public func clearText() {
        decodedText = ""
    }
}
