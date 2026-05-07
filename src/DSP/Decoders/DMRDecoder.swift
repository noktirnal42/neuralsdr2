//
// DMRDecoder.swift
// NeuralSDR2
//
// DMR (Digital Mobile Radio) Decoder
// 4FSK modulation at 4800 symbols/second, 9600 bps
// TDMA with two 30ms time slots per 60ms frame
//

import Foundation
import Accelerate

public class DMRDecoder: DSPBlock {
    public var name: String = "DMR Decoder"
    public var sampleRate: Double
    public var inputChannels = 1
    public var outputChannels = 1

    public var syncDetected: Bool = false
    public var currentSlot: Int = 0
    public var bitErrorRate: Float = 0.0

    public var onVoiceFrame: ((Int, Data) -> Void)?
    public var onDataFrame: ((Int, Data) -> Void)?
    public var onSyncDetected: ((Int) -> Void)?

    private let symbolRate: Double = 4800.0
    private let devLow: Float = 648.0
    private let devHigh: Float = 1944.0

    private static let syncPatternSlot1: UInt64 = 0x1145C044B
    private static let syncPatternSlot2: UInt64 = 0x1296A195A
    private static let syncPatternIdle: UInt64 = 0x1D5F5E7DA

    private var prevPhase: Float = 0.0
    private var samplesPerSymbol: Double
    private var symbolPhase: Double = 0.0
    private var earlySample: Float = 0.0
    private var lateSample: Float = 0.0
    private var midSample: Float = 0.0
    private var prevSymbol: Float = 0.0
    private var sampleIndex: Int = 0

    private var symbolBuffer: [UInt8] = []
    private var bitBuffer: [Int] = []
    private var slotBits: [Int] = []
    private var currentSlotIdx: Int = 0
    private var burstDetected: Bool = false
    private var burstSymbolCount: Int = 0
    private let burstLength: Int = 144

    private var monitorFilter: FIRFilter?
    private var monitorBuffer: [Float] = []

    private var crc9Table: [UInt16] = []

    public init(sampleRate: Double = 64000) {
        self.sampleRate = sampleRate
        self.samplesPerSymbol = sampleRate / symbolRate
        setupMonitorFilter()
        buildCRC9Table()
    }

    private func setupMonitorFilter() {
        let coeffs = DSPFilterDesign.lowpassFIR(
            cutoff: 3500,
            sampleRate: sampleRate,
            transitionWidth: 1500,
            attenuation: 40
        )
        if !coeffs.isEmpty {
            monitorFilter = FIRFilter(name: "DMR Monitor", coefficients: coeffs, sampleRate: sampleRate)
        }
    }

    private func buildCRC9Table() {
        let poly: UInt16 = 0x059
        crc9Table = [UInt16](repeating: 0, count: 256)
        for i in 0..<256 {
            var crc = UInt16(i) << 1
            for _ in 0..<8 {
                if crc & 0x200 != 0 {
                    crc = (crc << 1) ^ poly
                } else {
                    crc <<= 1
                }
            }
            crc9Table[i] = crc & 0x1FF
        }
    }

    public func process(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        for i in 0..<count {
            let angle = atan2(input[i].imag, input[i].real)
            var delta = angle - prevPhase
            if delta > Float.pi { delta -= 2.0 * Float.pi }
            else if delta < -Float.pi { delta += 2.0 * Float.pi }
            prevPhase = angle

            let freqOffset = delta * Float(sampleRate) / (2.0 * Float.pi)

            let audioScale: Float = 1.0 / 2500.0
            output[i] = ComplexFloat(real: freqOffset * audioScale, imag: 0)

            recoverSymbol(freqOffset: freqOffset)
        }

        if let filter = monitorFilter {
            var filtered = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: count)
            filtered.withUnsafeMutableBufferPointer { outPtr in
                filter.process(input, outPtr.baseAddress!, count: count)
            }
            for i in 0..<count {
                output[i] = filtered[i]
            }
        }
    }

    private func recoverSymbol(freqOffset: Float) {
        sampleIndex += 1

        let earlyIdx = Int(Double(sampleIndex) - symbolPhase - samplesPerSymbol * 0.5)
        let midIdx = Int(Double(sampleIndex) - symbolPhase - samplesPerSymbol * 0.25)
        let lateIdx = Int(Double(sampleIndex) - symbolPhase)

        if lateIdx >= 0 && midIdx >= 0 && earlyIdx >= 0 {
            let timingError = (lateSample - prevSymbol) * midSample * 0.05
            symbolPhase += Double(timingError)

            if Double(sampleIndex) - symbolPhase >= samplesPerSymbol {
                let symbol = decideSymbol(freqOffset: freqOffset)
                symbolBuffer.append(symbol)
                burstSymbolCount += 1

                let bits = symbolToBits(symbol)
                bitBuffer.append(contentsOf: bits)
                slotBits.append(contentsOf: bits)

                prevSymbol = lateSample
                symbolPhase += samplesPerSymbol

                if burstSymbolCount >= burstLength {
                    processBurst()
                    burstSymbolCount = 0
                }
            }
        }

        earlySample = lateSample
        lateSample = freqOffset
        midSample = freqOffset
    }

    private func decideSymbol(freqOffset: Float) -> UInt8 {
        let thresholds: [Float] = [
            (devHigh + devLow) / 2.0,
            (devLow + -devLow) / 2.0,
            (-devLow + -devHigh) / 2.0
        ]

        if freqOffset > thresholds[0] { return 0 }
        else if freqOffset > thresholds[1] { return 1 }
        else if freqOffset > thresholds[2] { return 2 }
        else { return 3 }
    }

    private func symbolToBits(_ symbol: UInt8) -> [Int] {
        switch symbol {
        case 0: return [1, 1]
        case 1: return [1, 0]
        case 2: return [0, 1]
        case 3: return [0, 0]
        default: return [0, 0]
        }
    }

    private func processBurst() {
        guard slotBits.count >= burstLength * 2 else {
            slotBits.removeAll(keepingCapacity: true)
            return
        }

        let syncStart = 66
        guard slotBits.count >= syncStart + 48 else {
            slotBits.removeAll(keepingCapacity: true)
            return
        }

        let syncWord = extractBits(slotBits, offset: syncStart, count: 48)

        let slot1Dist = hammingDistance(syncWord, DMRDecoder.syncPatternSlot1, bits: 48)
        let slot2Dist = hammingDistance(syncWord, DMRDecoder.syncPatternSlot2, bits: 48)
        let idleDist = hammingDistance(syncWord, DMRDecoder.syncPatternIdle, bits: 48)

        let maxErrors = 10
        if slot1Dist <= maxErrors {
            currentSlotIdx = 0
            syncDetected = true
            onSyncDetected?(0)
            decodeBurst(slot: 0)
        } else if slot2Dist <= maxErrors {
            currentSlotIdx = 1
            syncDetected = true
            onSyncDetected?(1)
            decodeBurst(slot: 1)
        } else if idleDist <= maxErrors {
            syncDetected = true
            onSyncDetected?(currentSlotIdx)
        }

        let totalBits = slotBits.count
        if totalBits > 0 {
            bitErrorRate = bitErrorRate * 0.9 + Float(min(slot1Dist, slot2Dist, idleDist)) / 48.0 * 0.1
        }

        slotBits.removeAll(keepingCapacity: true)
        bitBuffer.removeAll(keepingCapacity: true)
    }

    private func extractBits(_ bits: [Int], offset: Int, count: Int) -> UInt64 {
        var value: UInt64 = 0
        for i in 0..<count {
            let idx = offset + i
            if idx < bits.count && bits[idx] != 0 {
                value |= UInt64(1) << UInt64(count - 1 - i)
            }
        }
        return value
    }

    private func hammingDistance(_ a: UInt64, _ b: UInt64, bits: Int) -> Int {
        var x = a ^ b
        var dist = 0
        let mask = bits < 64 ? UInt64((1 << bits) - 1) : UInt64.max
        x &= mask
        while x != 0 {
            dist += 1
            x &= x - 1
        }
        return dist
    }

    private func decodeBurst(slot: Int) {
        let payloadStart = 0
        let payloadEnd = min(264, slotBits.count)

        guard payloadEnd > payloadStart else { return }

        var payloadData = Data()
        for i in stride(from: payloadStart, to: payloadEnd, by: 8) {
            var byte: UInt8 = 0
            for j in 0..<8 {
                if i + j < slotBits.count && slotBits[i + j] != 0 {
                    byte |= UInt8(1 << (7 - j))
                }
            }
            payloadData.append(byte)
        }

        if checkCRC9(payloadData) {
            currentSlot = slot
            let isVoice = detectBurstType(payloadData)

            if isVoice {
                onVoiceFrame?(slot, payloadData)
            } else {
                onDataFrame?(slot, payloadData)
            }
        } else {
            let isVoice = detectBurstType(payloadData)
            if isVoice {
                onVoiceFrame?(slot, payloadData)
            } else {
                onDataFrame?(slot, payloadData)
            }
        }
    }

    private func checkCRC9(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }

        var crc: UInt16 = 0
        for byte in data.dropLast(2) {
            let idx = Int((crc >> 1) ^ UInt16(byte))
            if idx >= 0 && idx < crc9Table.count {
                crc = (crc << 8) ^ crc9Table[idx]
            }
            crc &= 0x1FF
        }

        let receivedCRC = UInt16(data[data.count - 2]) << 1 | UInt16(data[data.count - 1]) >> 7
        return crc == receivedCRC & 0x1FF
    }

    private func detectBurstType(_ data: Data) -> Bool {
        guard data.count > 0 else { return true }
        let typeByte = data[0]
        let burstType = (typeByte >> 6) & 0x03
        return burstType == 0 || burstType == 3
    }

    public func reset() {
        prevPhase = 0
        symbolPhase = 0
        sampleIndex = 0
        earlySample = 0
        lateSample = 0
        midSample = 0
        prevSymbol = 0
        symbolBuffer.removeAll(keepingCapacity: true)
        bitBuffer.removeAll(keepingCapacity: true)
        slotBits.removeAll(keepingCapacity: true)
        burstDetected = false
        burstSymbolCount = 0
        syncDetected = false
        bitErrorRate = 0
        monitorFilter?.reset()
    }

    public func configure(params: [String: Any]) {
        if let sr = params["sampleRate"] as? Double {
            sampleRate = sr
            samplesPerSymbol = sr / symbolRate
            setupMonitorFilter()
        }
    }
}
