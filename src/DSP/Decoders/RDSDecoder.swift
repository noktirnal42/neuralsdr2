//
// RDSDecoder.swift
// NeuralSDR2
//
// RDS (Radio Data System) Decoder for FM broadcast
// BPSK at 1187.5 baud on 57 kHz subcarrier with differential encoding
//

import Foundation
import Accelerate

public class RDSDecoder: DSPBlock {
    public var name: String = "RDS Decoder"
    public var sampleRate: Double
    public var inputChannels = 1
    public var outputChannels = 1

    // RDS constants
    private let rdsFrequency: Double = 57000.0
    private let rdsBitrate: Double = 1187.5
    private let rdsSymbolRate: Double = 1187.5
    private let blockSize: Int = 26

    // RDS sync words (26-bit) for each offset
    private static let syncA: UInt32 = 0x3CBD
    private static let syncB: UInt32 = 0x25D8
    private static let syncC: UInt32 = 0x3D28
    private static let syncCPrime: UInt32 = 0x0CC5
    private static let syncD: UInt32 = 0x0F25

    // RDS (26,16) cyclic code generator polynomial: x^10 + x^8 + x^7 + x^5 + x^4 + x^3 + 1 = 0x5B9
    private static let rdsPoly: UInt32 = 0x5B9

    // Block sync word list for matching
    private static let syncWords: [(offset: String, word: UInt32)] = [
        ("A", RDSDecoder.syncA),
        ("B", RDSDecoder.syncB),
        ("C", RDSDecoder.syncC),
        ("C'", RDSDecoder.syncCPrime),
        ("D", RDSDecoder.syncD)
    ]

    // Costas loop state
    private var costasPhase: Double = 0
    private var costasFreq: Double = 0
    private var costasLoopBandwidth: Double = 0.01
    private var costasDamping: Double = 0.707

    // Clock recovery state
    private var symbolPhase: Double = 0
    private var symbolFreq: Double = 1.0 / 1187.5
    private var prevSample: Float = 0
    private var prevSymbol: Float = 0
    private var symbolHistory: [Float] = []
    private var sampleIndex: Int = 0
    private var samplesPerSymbol: Double

    // BPSK demodulation state
    private var prevBit: Int = -1
    private var diffDecodedBits: [Int] = []

    // Block synchronization state
    private var bitBuffer: UInt64 = 0
    private var bitCount: Int = 0
    private var blockSyncFound: Bool = false
    private var currentOffset: Int = 0
    private var blockWords: [UInt32] = []
    private var groupWords: [UInt32] = [] // 4 words per group (A,B,C,D)

    // Decoded RDS data
    private var pi: UInt16 = 0
    private var psChars: [Character] = [Character](repeating: " ", count: 8)
    private var psSegmentFlags: UInt8 = 0
    private var rtABFlag: UInt8 = 0xFF
    private var rtChars: [Character] = [Character](repeating: " ", count: 64)
    private var rtSegmentFlag: UInt64 = 0
    private var pty: UInt8 = 0
    private var ta: Bool = false
    private var tp: Bool = false
    private var afList: [Float] = []
    private var msFlag: Bool = false
    private var diFlags: UInt8 = 0

    // Filters
    private var lowpassFilter: FIRFilter?
    private var mixerPhase: Double = 0

    // Sample buffer for processing
    private var sampleBuffer: [ComplexFloat] = []
    private var filteredBuffer: [ComplexFloat] = []

    // Callbacks
    public var onPS: ((String) -> Void)?
    public var onRT: ((String) -> Void)?
    public var onPI: ((UInt16) -> Void)?
    public var onPTY: ((UInt8) -> Void)?
    public var onTP: ((Bool) -> Void)?
    public var onTA: ((Bool) -> Void)?
    public var onMS: ((Bool) -> Void)?
    public var onGroup: ((Int, [UInt32]) -> Void)?
    public var onRawBlock: ((Int, UInt32, UInt32) -> Void)?

    public init(sampleRate: Double = 64000) {
        self.sampleRate = sampleRate
        self.samplesPerSymbol = sampleRate / rdsSymbolRate
        setupFilters()
    }

    public func process(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        for i in 0..<count {
            output[i] = input[i]
        }

        // Step 1: Mix down from 57 kHz to baseband
        var baseband = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: count)
        mixDown(input, &baseband, count: count)

        // Step 2: Lowpass filter to isolate RDS baseband signal (~2 kHz bandwidth)
        if let lp = lowpassFilter {
            var filtered = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: count)
            lp.process(baseband, &filtered, count: count)

            // Step 3: Costas loop for BPSK carrier tracking
            var costasOut = [Float](repeating: 0, count: count)
            costasLoop(filtered, &costasOut, count: count)

            // Step 4: Clock recovery and symbol sampling
            clockRecovery(costasOut, count: count)
        }
    }

    // MARK: - Subcarrier Extraction

    private func mixDown(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        let omega = 2.0 * Double.pi * rdsFrequency / sampleRate
        for i in 0..<count {
            let phase = mixerPhase + omega * Double(i)
            let cosPhase = Float(cos(phase))
            let sinPhase = Float(-sin(phase))
            output[i] = ComplexFloat(
                real: input[i].real * cosPhase - input[i].imag * sinPhase,
                imag: input[i].real * sinPhase + input[i].imag * cosPhase
            )
        }
        mixerPhase += omega * Double(count)
        mixerPhase = mixerPhase.truncatingRemainder(dividingBy: 2.0 * Double.pi)
    }

    // MARK: - Costas Loop

    private func costasLoop(_ input: [ComplexFloat], _ output: UnsafeMutablePointer<Float>, count: Int) {
        let bw = costasLoopBandwidth
        let damp = costasDamping
        let alpha = Float(4 * bw * damp / (damp + 0.25 / damp))
        let beta = Float(2 * bw * bw / (damp + 0.25 / damp))

        for i in 0..<count {
            let cosPhase = Float(cos(costasPhase))
            let sinPhase = Float(-sin(costasPhase))

            let iBranch = input[i].real * cosPhase - input[i].imag * sinPhase
            let qBranch = input[i].real * sinPhase + input[i].imag * cosPhase

            let basebandI = iBranch
            let error = qBranch * (basebandI >= 0 ? Float(1) : Float(-1))

            costasFreq += Double(beta * error)
            costasPhase += Double(alpha * error) + costasFreq

            if costasPhase > Double.pi { costasPhase -= 2.0 * Double.pi }
            if costasPhase < -Double.pi { costasPhase += 2.0 * Double.pi }

            output[i] = basebandI
        }
    }

    // MARK: - Clock Recovery (Gardner timing error detector)

    private func clockRecovery(_ samples: UnsafePointer<Float>, count: Int) {
        let halfSym = samplesPerSymbol / 2.0

        for i in 0..<count {
            symbolHistory.append(samples[i])
            sampleIndex += 1

            let currentPhasePos = Double(sampleIndex) - symbolPhase
            let symbolInterval = samplesPerSymbol

            if currentPhasePos >= symbolInterval {
                let midIdx = max(0, symbolHistory.count - Int(halfSym) - 1)
                let lateIdx = max(0, symbolHistory.count - 1)

                let midSample = midIdx < symbolHistory.count ? symbolHistory[midIdx] : Float(0)
                let lateSample = lateIdx < symbolHistory.count ? symbolHistory[lateIdx] : Float(0)

                let timingError = Float((lateSample - prevSymbol) * midSample)
                let gain: Float = 0.05
                symbolPhase += Double(gain * timingError)

                let symbol = lateSample
                decideBit(symbol)

                prevSymbol = symbol
                symbolPhase += symbolInterval
            }
        }

        // Keep history bounded
        let maxHistory = Int(samplesPerSymbol * 4)
        if symbolHistory.count > maxHistory {
            symbolHistory.removeFirst(symbolHistory.count - maxHistory)
        }
    }

    // MARK: - BPSK Differential Decoding

    private func decideBit(_ sample: Float) {
        let hardDecision = sample >= 0 ? 1 : 0

        if prevBit >= 0 {
            let diffBit = hardDecision ^ prevBit
            shiftInBit(diffBit)
        }

        prevBit = hardDecision
    }

    // MARK: - Block Synchronization

    private func shiftInBit(_ bit: Int) {
        bitBuffer = ((bitBuffer << 1) | UInt64(bit)) & 0x3FFFFFF // 26-bit mask
        bitCount += 1

        if bitCount < 26 {
            if !blockSyncFound {
                tryFindSync()
            }
            return
        }

        bitCount = 26

        if !blockSyncFound {
            tryFindSync()
            return
        }

        // We are in sync - extract blocks at the right position
        let currentWord = UInt32(bitBuffer & 0x3FFFFFF)

        if currentOffset == 0 {
            groupWords.removeAll(keepingCapacity: true)
        }

        let (offsetName, infoword, checkword) = splitRDSBlock(currentWord)

        // Verify check bits using syndrome
        if verifyBlock(currentWord) {
            groupWords.append(infoword)

            if offsetName != nil {
                onRawBlock?(currentOffset, infoword, checkword)
            }

            currentOffset += 1

            if currentOffset >= 4 && groupWords.count >= 4 {
                decodeGroup(groupWords)
                currentOffset = 0
            }
        } else {
            // Check failed - try to re-sync
            blockSyncFound = false
            currentOffset = 0
            groupWords.removeAll(keepingCapacity: true)
        }
    }

    private func tryFindSync() {
        let word = UInt32(bitBuffer & 0x3FFFFFF)

        for (offsetName, syncWord) in RDSDecoder.syncWords {
            let hamming = hammingDistance(word, syncWord)
            if hamming <= 2 {
                blockSyncFound = true
                currentOffset = (offsetName == "A") ? 0 :
                                (offsetName == "B") ? 1 :
                                (offsetName == "C" || offsetName == "C'") ? 2 :
                                (offsetName == "D") ? 3 : 0
                groupWords.removeAll(keepingCapacity: true)

                let (_, info, _) = splitRDSBlock(word)
                groupWords.append(info)
                return
            }
        }
    }

    private func hammingDistance(_ a: UInt32, _ b: UInt32) -> Int {
        var x = a ^ b
        var dist = 0
        while x != 0 {
            dist += 1
            x &= x - 1
        }
        return dist
    }

    // MARK: - RDS Block Error Checking

    private func splitRDSBlock(_ word: UInt32) -> (String?, UInt32, UInt32) {
        let infoword = (word >> 10) & 0xFFFF
        let checkword = word & 0x3FF
        var offsetName: String? = nil

        for (name, sync) in RDSDecoder.syncWords {
            if (word ^ (infoword << 10 | rdsCheckBitsForOffset(infoword, sync))) == 0 {
                offsetName = name
                break
            }
        }

        return (offsetName, infoword, checkword)
    }

    private func rdsCheckBits(_ info: UInt32) -> UInt32 {
        var remainder = info << 10
        for i in stride(from: 25, through: 10, by: -1) {
            if (remainder & (1 << i)) != 0 {
                remainder ^= (RDSDecoder.rdsPoly << (i - 10))
            }
        }
        return remainder & 0x3FF
    }

    private func rdsCheckBitsForOffset(_ info: UInt32, _ offsetWord: UInt32) -> UInt32 {
        var check = rdsCheckBits(info)
        check ^= UInt32(offsetWord & 0x3FF)
        return check
    }

    private func verifyBlock(_ word: UInt32) -> Bool {
        let infoword = (word >> 10) & 0xFFFF
        let receivedCheck = word & 0x3FF

        // Try each offset word
        for (_, syncWord) in RDSDecoder.syncWords {
            let expectedCheck = rdsCheckBitsForOffset(infoword, syncWord)
            let syndrome = receivedCheck ^ expectedCheck
            if syndrome == 0 {
                return true
            }
        }

        return false
    }

    // MARK: - Group Decoding

    private func decodeGroup(_ words: [UInt32]) {
        guard words.count >= 4 else { return }

        let wordA = words[0] // Block A always contains PI
        let wordB = words[1]
        let wordC = words[2]
        let wordD = words[3]

        let newPI = UInt16(wordA & 0xFFFF)
        if newPI != pi && newPI != 0 {
            pi = newPI
            onPI?(pi)
        }

        let groupType = Int((wordB >> 12) & 0x0F)
        let groupVersion = Int((wordB >> 11) & 0x01) // 0=A, 1=B
        let groupCode = groupType * 2 + groupVersion

        tp = (wordB & (1 << 10)) != 0
        pty = UInt8((wordB >> 5) & 0x1F)

        onGroup?(groupCode, words)

        switch groupCode {
        case 0x00: decodeGroup0A(wordB: wordB, wordC: wordC, wordD: wordD)
        case 0x01: decodeGroup0B(wordB: wordB, wordD: wordD)
        case 0x04: decodeGroup2A(wordB: wordB, wordC: wordC, wordD: wordD)
        case 0x05: decodeGroup2B(wordB: wordB, wordD: wordD)
        case 0x08: decodeGroup4A(wordB: wordB, wordC: wordC, wordD: wordD)
        default: break
        }
    }

    // MARK: - Group 0A: Basic Tuning (PI, PS, AF, etc.)

    private func decodeGroup0A(wordB: UInt32, wordC: UInt32, wordD: UInt32) {
        ta = (wordB & (1 << 4)) != 0
        msFlag = (wordB & (1 << 3)) != 0
        let diBit = (wordB >> 2) & 0x01

        let segmentAddr = Int(wordB & 0x03)
        diFlags = (diFlags & ~(1 << (3 - segmentAddr))) | UInt8(diBit << (3 - segmentAddr))

        // PS segment - 2 chars per segment
        let charHi = UInt8((wordD >> 8) & 0xFF)
        let charLo = UInt8(wordD & 0xFF)

        if charHi >= 0x20 && charHi < 0x80 {
            psChars[segmentAddr * 2] = Character(UnicodeScalar(charHi))
        }
        if charLo >= 0x20 && charLo < 0x80 {
            psChars[segmentAddr * 2 + 1] = Character(UnicodeScalar(charLo))
        }

        psSegmentFlags |= (1 << segmentAddr)
        if psSegmentFlags == 0x0F {
            let psStr = String(psChars)
            onPS?(psStr)
        }

        // AF decoding from wordC
        let afCodeHi = UInt8((wordC >> 8) & 0xFF)
        let afCodeLo = UInt8(wordC & 0xFF)
        if afCodeHi > 0 && afCodeHi < 205 {
            let freq = Float(afCodeHi) * 0.1 + 87.5
            if !afList.contains(freq) {
                afList.append(freq)
            }
        }
        if afCodeLo > 0 && afCodeLo < 205 {
            let freq = Float(afCodeLo) * 0.1 + 87.5
            if !afList.contains(freq) {
                afList.append(freq)
            }
        }

        onTP?(tp)
        onTA?(ta)
        onMS?(msFlag)
    }

    // MARK: - Group 0B: Basic Tuning (no AF)

    private func decodeGroup0B(wordB: UInt32, wordD: UInt32) {
        ta = (wordB & (1 << 4)) != 0
        msFlag = (wordB & (1 << 3)) != 0
        let diBit = (wordB >> 2) & 0x01
        let segmentAddr = Int(wordB & 0x03)

        diFlags = (diFlags & ~(1 << (3 - segmentAddr))) | UInt8(diBit << (3 - segmentAddr))

        let charHi = UInt8((wordD >> 8) & 0xFF)
        let charLo = UInt8(wordD & 0xFF)

        if charHi >= 0x20 && charHi < 0x80 {
            psChars[segmentAddr * 2] = Character(UnicodeScalar(charHi))
        }
        if charLo >= 0x20 && charLo < 0x80 {
            psChars[segmentAddr * 2 + 1] = Character(UnicodeScalar(charLo))
        }

        psSegmentFlags |= (1 << segmentAddr)
        if psSegmentFlags == 0x0F {
            let psStr = String(psChars)
            onPS?(psStr)
        }

        onTP?(tp)
        onTA?(ta)
        onMS?(msFlag)
    }

    // MARK: - Group 2A: Radio Text (32 segments, 2 chars each, 64 chars total)

    private func decodeGroup2A(wordB: UInt32, wordC: UInt32, wordD: UInt32) {
        let newABFlag = UInt8((wordB >> 4) & 0x01)
        if newABFlag != rtABFlag {
            rtABFlag = newABFlag
            rtChars = [Character](repeating: " ", count: 64)
            rtSegmentFlag = 0
        }

        let segmentAddr = Int(wordB & 0x0F)

        let charC0 = UInt8((wordC >> 8) & 0xFF)
        let charC1 = UInt8(wordC & 0xFF)
        let charD0 = UInt8((wordD >> 8) & 0xFF)
        let charD1 = UInt8(wordD & 0xFF)

        let chars = [charC0, charC1, charD0, charD1]
        for j in 0..<4 {
            let idx = segmentAddr * 4 + j
            if idx < 64 {
                let code = chars[j]
                if code >= 0x20 && code < 0x80 {
                    rtChars[idx] = Character(UnicodeScalar(code))
                } else if code == 0x0D {
                    rtChars[idx] = " "
                }
            }
        }

        rtSegmentFlag |= (1 << segmentAddr)

        // Check if we have enough segments to emit text
        var complete = true
        for i in 0..<16 {
            if rtSegmentFlag & (1 << i) == 0 {
                complete = false
                break
            }
        }

        if complete || rtSegmentFlag >= 0x3 {
            var rtStr = String(rtChars)
            if let endIdx = rtStr.firstIndex(of: "\r") {
                rtStr = String(rtStr[..<endIdx])
            }
            rtStr = rtStr.trimmingCharacters(in: CharacterSet(charactersIn: " ").union(.controlCharacters))
            if !rtStr.isEmpty {
                onRT?(rtStr)
            }
        }
    }

    // MARK: - Group 2B: Radio Text (16 segments, 2 chars each, 32 chars)

    private func decodeGroup2B(wordB: UInt32, wordD: UInt32) {
        let newABFlag = UInt8((wordB >> 4) & 0x01)
        if newABFlag != rtABFlag {
            rtABFlag = newABFlag
            rtChars = [Character](repeating: " ", count: 64)
            rtSegmentFlag = 0
        }

        let segmentAddr = Int(wordB & 0x0F)

        let charD0 = UInt8((wordD >> 8) & 0xFF)
        let charD1 = UInt8(wordD & 0xFF)

        let chars = [charD0, charD1]
        for j in 0..<2 {
            let idx = segmentAddr * 2 + j
            if idx < 32 {
                let code = chars[j]
                if code >= 0x20 && code < 0x80 {
                    rtChars[idx] = Character(UnicodeScalar(code))
                } else if code == 0x0D {
                    rtChars[idx] = " "
                }
            }
        }

        rtSegmentFlag |= (1 << segmentAddr)
    }

    // MARK: - Group 4A: Clock-Time and Date

    private func decodeGroup4A(wordB: UInt32, wordC: UInt32, wordD: UInt32) {
        // RDS clock-time group (optional, not decoded in detail here)
    }

    // MARK: - Filter Setup

    private func setupFilters() {
        let rdsBandwidth = 2400.0
        let transitionWidth = 600.0
        let coeffs = DSPFilterDesign.lowpassFIR(
            cutoff: rdsBandwidth,
            sampleRate: sampleRate,
            transitionWidth: transitionWidth,
            attenuation: 50
        )
        if !coeffs.isEmpty {
            lowpassFilter = FIRFilter(name: "RDS Lowpass", coefficients: coeffs, sampleRate: sampleRate)
        }
    }

    // MARK: - Reset / Configure

    public func reset() {
        bitBuffer = 0
        bitCount = 0
        blockSyncFound = false
        currentOffset = 0
        groupWords.removeAll(keepingCapacity: true)
        prevBit = -1
        prevSymbol = 0
        symbolHistory.removeAll(keepingCapacity: true)
        symbolPhase = 0
        sampleIndex = 0
        costasPhase = 0
        costasFreq = 0
        mixerPhase = 0
        psSegmentFlags = 0
        rtSegmentFlag = 0
        rtABFlag = 0xFF
        psChars = [Character](repeating: " ", count: 8)
        rtChars = [Character](repeating: " ", count: 64)
        lowpassFilter?.reset()
    }

    public func configure(params: [String: Any]) {
        if let sr = params["sampleRate"] as? Double {
            sampleRate = sr
            samplesPerSymbol = sr / rdsSymbolRate
            setupFilters()
        }
        if let bw = params["costasBandwidth"] as? Double {
            costasLoopBandwidth = bw
        }
    }

    /// Get Program Service name
    public var programService: String {
        return psSegmentFlags > 0 ? String(psChars) : "Unknown"
    }

    /// Get Radio Text
    public var radioText: String {
        if rtSegmentFlag == 0 { return "No RT" }
        var rtStr = String(rtChars)
        if let endIdx = rtStr.firstIndex(of: "\r") {
            rtStr = String(rtStr[..<endIdx])
        }
        return rtStr.trimmingCharacters(in: .whitespaces)
    }

    /// Get Program Identification
    public var programIdentification: UInt16 {
        return pi
    }

    /// Get Program Type
    public var programType: UInt8 {
        return pty
    }

    /// Get Traffic Program flag
    public var trafficProgram: Bool {
        return tp
    }

    /// Get Traffic Announcement flag
    public var trafficAnnouncement: Bool {
        return ta
    }

    /// Get Alternative Frequencies
    public var alternativeFrequencies: [Float] {
        return afList
    }

    /// Get Music/Speech flag
    public var isMusic: Bool {
        return msFlag
    }

    /// Get Decoder Info string
    public var decoderInfo: String {
        return "PI:\(String(format: "%04X", pi)) PS:\(programService) PTY:\(pty) TP:\(tp) TA:\(ta)"
    }
}
