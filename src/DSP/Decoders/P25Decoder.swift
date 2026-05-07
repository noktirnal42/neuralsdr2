//
// P25Decoder.swift
// NeuralSDR2
//
// P25 Phase 1 (APCO-25) Decoder
// C4FM (Continuous 4-Level FM) at 4800 symbols/second, 9600 bps
//

import Foundation
import Accelerate

public class P25Decoder: DSPBlock {
    public var name: String = "P25 Decoder"
    public var sampleRate: Double
    public var inputChannels = 1
    public var outputChannels = 1

    public var nac: UInt16 = 0
    public var syncDetected: Bool = false
    public var dataUnitType: String = "Unknown"

    public var onNIDDetected: ((UInt16) -> Void)?
    public var onVoiceFrame: ((Data) -> Void)?
    public var onDataUnit: ((String, Data) -> Void)?

    private let symbolRate: Double = 4800.0
    private let dev1: Float = 600.0
    private let dev2: Float = 1800.0

    private static let preamblePattern: UInt64 = 0x555555555555
    private static let nidSyncPattern: UInt64 = 0x577D155D577D

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
    private var nidDetected: Bool = false
    private var collectingDataUnit: Bool = false
    private var dataUnitBits: [Int] = []
    private var dataUnitSymbolCount: Int = 0
    private var currentDataUnitType: String = "Unknown"

    private let hduLength: Int = 320
    private let lduLength: Int = 1248
    private let tduLength: Int = 280

    private var monitorFilter: FIRFilter?

    public init(sampleRate: Double = 64000) {
        self.sampleRate = sampleRate
        self.samplesPerSymbol = sampleRate / symbolRate
        setupMonitorFilter()
    }

    private func setupMonitorFilter() {
        let coeffs = DSPFilterDesign.lowpassFIR(
            cutoff: 3500,
            sampleRate: sampleRate,
            transitionWidth: 1500,
            attenuation: 40
        )
        if !coeffs.isEmpty {
            monitorFilter = FIRFilter(name: "P25 Monitor", coefficients: coeffs, sampleRate: sampleRate)
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

        if Double(sampleIndex) - symbolPhase >= samplesPerSymbol {
            let timingError = (lateSample - prevSymbol) * midSample * 0.05
            symbolPhase += Double(timingError)

            let symbol = decideSymbol(freqOffset: freqOffset)
            symbolBuffer.append(symbol)

            let bits = symbolToBits(symbol)
            bitBuffer.append(contentsOf: bits)

            if collectingDataUnit {
                dataUnitBits.append(contentsOf: bits)
                dataUnitSymbolCount += 1
                checkDataUnitComplete()
            }

            prevSymbol = lateSample
            symbolPhase += samplesPerSymbol

            detectPreambleAndNID()
        }

        earlySample = lateSample
        lateSample = freqOffset
        midSample = freqOffset
    }

    private func decideSymbol(freqOffset: Float) -> UInt8 {
        let thresholds: [Float] = [
            (dev2 + dev1) / 2.0,
            (dev1 + -dev1) / 2.0,
            (-dev1 + -dev2) / 2.0
        ]

        if freqOffset > thresholds[0] { return 3 }
        else if freqOffset > thresholds[1] { return 2 }
        else if freqOffset > thresholds[2] { return 1 }
        else { return 0 }
    }

    private func symbolToBits(_ symbol: UInt8) -> [Int] {
        switch symbol {
        case 3: return [1, 1]
        case 2: return [1, 0]
        case 1: return [0, 1]
        case 0: return [0, 0]
        default: return [0, 0]
        }
    }

    private func detectPreambleAndNID() {
        if bitBuffer.count >= 128 && !nidDetected {
            let preambleBits = extractBitPattern(bitBuffer, offset: 0, count: 64)

            let alternating: UInt64 = 0x5555555555555555
            let preambleMask: UInt64 = 0xFFFFFFFFFFFFFFFF
            let preambleXor = preambleBits ^ (alternating & preambleMask)
            let preambleErrors = popcount64(preambleXor)

            if preambleErrors <= 8 {
                let nidBits = extractBitPattern(bitBuffer, offset: 64, count: 64)
                let nidSync = UInt64(P25Decoder.nidSyncPattern) & 0xFFFFFFFFFFFF
                let nidXor = (nidBits & 0xFFFFFFFFFFFF) ^ nidSync
                let nidErrors = popcount64(nidXor)

                if nidErrors <= 6 {
                    let nacValue = UInt16((nidBits >> 52) & 0x0FFF)
                    nac = nacValue
                    nidDetected = true
                    syncDetected = true
                    onNIDDetected?(nacValue)

                    determineDataUnitType(nidBits)
                    collectingDataUnit = true
                    dataUnitBits.removeAll(keepingCapacity: true)
                    dataUnitSymbolCount = 0

                    bitBuffer.removeAll(keepingCapacity: true)
                    symbolBuffer.removeAll(keepingCapacity: true)
                }
            }
        }

        if bitBuffer.count > 1024 && !nidDetected {
            bitBuffer.removeFirst(512)
            symbolBuffer.removeFirst(256)
        }
    }

    private func popcount64(_ x: UInt64) -> Int {
        var val = x
        var count = 0
        while val != 0 {
            count += 1
            val &= val - 1
        }
        return count
    }

    private func determineDataUnitType(_ nidBits: UInt64) {
        let duId = (nidBits >> 40) & 0xF

        switch duId {
        case 0x0:
            currentDataUnitType = "HDU"
            dataUnitType = "HDU"
        case 0x5:
            currentDataUnitType = "LDU1"
            dataUnitType = "LDU1"
        case 0xA:
            currentDataUnitType = "LDU2"
            dataUnitType = "LDU2"
        case 0x3:
            currentDataUnitType = "TDU"
            dataUnitType = "TDU"
        case 0x7:
            currentDataUnitType = "PDU"
            dataUnitType = "PDU"
        case 0xC:
            currentDataUnitType = "TSDU"
            dataUnitType = "TSDU"
        default:
            currentDataUnitType = "Unknown"
            dataUnitType = "Unknown"
        }
    }

    private func checkDataUnitComplete() {
        let expectedBits: Int
        switch currentDataUnitType {
        case "HDU":
            expectedBits = hduLength
        case "LDU1", "LDU2":
            expectedBits = lduLength
        case "TDU":
            expectedBits = tduLength
        default:
            expectedBits = lduLength
        }

        if dataUnitBits.count >= expectedBits {
            let frameData = bitsToData(dataUnitBits.prefix(expectedBits))

            if checkCRC16(frameData) || checkCRC32(frameData) {
                switch currentDataUnitType {
                case "LDU1", "LDU2":
                    onVoiceFrame?(frameData)
                default:
                    onDataUnit?(currentDataUnitType, frameData)
                }
            } else {
                switch currentDataUnitType {
                case "LDU1", "LDU2":
                    onVoiceFrame?(frameData)
                default:
                    onDataUnit?(currentDataUnitType, frameData)
                }
            }

            collectingDataUnit = false
            dataUnitBits.removeAll(keepingCapacity: true)
            dataUnitSymbolCount = 0
            nidDetected = false
            syncDetected = false
        }

        if dataUnitBits.count > lduLength * 2 {
            collectingDataUnit = false
            dataUnitBits.removeAll(keepingCapacity: true)
            nidDetected = false
            syncDetected = false
        }
    }

    private func extractBitPattern(_ bits: [Int], offset: Int, count: Int) -> UInt64 {
        var value: UInt64 = 0
        for i in 0..<min(count, 64) {
            let idx = offset + i
            if idx < bits.count && bits[idx] != 0 {
                value |= UInt64(1) << UInt64(min(count, 64) - 1 - i)
            }
        }
        return value
    }

    private func bitsToData(_ bits: ArraySlice<Int>) -> Data {
        var data = Data()
        var byte: UInt8 = 0
        var bitIdx = 0

        for bit in bits {
            byte <<= 1
            if bit != 0 { byte |= 1 }
            bitIdx += 1
            if bitIdx == 8 {
                data.append(byte)
                byte = 0
                bitIdx = 0
            }
        }

        if bitIdx > 0 {
            byte <<= UInt8(8 - bitIdx)
            data.append(byte)
        }

        return data
    }

    private func checkCRC16(_ data: Data) -> Bool {
        guard data.count >= 3 else { return false }

        let poly: UInt16 = 0x1021
        var crc: UInt16 = 0xFFFF

        for byte in data.dropLast(2) {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = (crc << 1) ^ poly
                } else {
                    crc <<= 1
                }
            }
        }

        let received = UInt16(data[data.count - 2]) << 8 | UInt16(data[data.count - 1])
        return crc == received
    }

    private func checkCRC32(_ data: Data) -> Bool {
        guard data.count >= 5 else { return false }

        let poly: UInt32 = 0xEDB88320
        var crc: UInt32 = 0xFFFFFFFF

        for byte in data.dropLast(4) {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ poly
                } else {
                    crc >>= 1
                }
            }
        }

        crc ^= 0xFFFFFFFF

        let received = UInt32(data[data.count - 4]) << 24 |
                       UInt32(data[data.count - 3]) << 16 |
                       UInt32(data[data.count - 2]) << 8 |
                       UInt32(data[data.count - 1])
        return crc == received
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
        dataUnitBits.removeAll(keepingCapacity: true)
        nidDetected = false
        collectingDataUnit = false
        syncDetected = false
        nac = 0
        dataUnitType = "Unknown"
        dataUnitSymbolCount = 0
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
