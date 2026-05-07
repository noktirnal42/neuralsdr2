//
// UATDecoder.swift
// NeuralSDR2
//
// UAT (Universal Access Transceiver) Decoder for 978 MHz
// Real CPFSK demodulation, Reed-Solomon error correction,
// ADS-B position decoding, and FIS-B weather product extraction
//

import Foundation
import Accelerate

// MARK: - FIS-B Packet Types

public enum FISBPacketType: Equatable {
    case nexradRegional
    case nexradCONUS
    case sigmet
    case airmet
    case notam
    case metar
    case taf
    case windsAloft
    case pirep
    case suaprohibition
    case unknown(UInt16)

    public static var nexrad: FISBPacketType { .nexradRegional }

    init(productId: UInt16) {
        switch productId {
        case 0:  self = .nexradRegional
        case 1:  self = .nexradCONUS
        case 3:  self = .sigmet
        case 4:  self = .airmet
        case 5:  self = .notam
        case 8:  self = .metar
        case 9:  self = .taf
        case 10: self = .windsAloft
        case 11: self = .pirep
        case 13: self = .suaprohibition
        default: self = .unknown(productId)
        }
    }
}

// MARK: - FIS-B Frame

public struct FISBFrame {
    public let type: FISBPacketType
    public let lapIndex: Int
    public let totalLaps: Int
    public let data: Data
    public let timestamp: Date
    public let productId: UInt16
    public let productTime: UInt32

    public init(type: FISBPacketType, lapIndex: Int, totalLaps: Int,
                data: Data, timestamp: Date, productId: UInt16 = 0, productTime: UInt32 = 0) {
        self.type = type
        self.lapIndex = lapIndex
        self.totalLaps = totalLaps
        self.data = data
        self.timestamp = timestamp
        self.productId = productId
        self.productTime = productTime
    }
}

public struct FISBNEXRADBlock {
    public let key: String
    public let type: FISBPacketType
    public let productTime: UInt32
    public let latitudeNorth: Double
    public let longitudeWest: Double
    public let latitudeSize: Double
    public let longitudeSize: Double
    public let scaleFactor: Int
    public let bins: [Float]
    public let timestamp: Date

    public init(
        key: String,
        type: FISBPacketType,
        productTime: UInt32,
        latitudeNorth: Double,
        longitudeWest: Double,
        latitudeSize: Double,
        longitudeSize: Double,
        scaleFactor: Int,
        bins: [Float],
        timestamp: Date
    ) {
        self.key = key
        self.type = type
        self.productTime = productTime
        self.latitudeNorth = latitudeNorth
        self.longitudeWest = longitudeWest
        self.latitudeSize = latitudeSize
        self.longitudeSize = longitudeSize
        self.scaleFactor = scaleFactor
        self.bins = bins
        self.timestamp = timestamp
    }
}

// MARK: - ADS-B Decoded Message

public struct UATADSMessage {
    public let icao24: UInt32
    public let latitude: Double?
    public let longitude: Double?
    public let altitude: Int32?
    public let speedKnots: UInt16?
    public let track: UInt16?
    public let callsign: String?
    public let messageType: UInt8
}

// MARK: - GF(2^8) Arithmetic

private struct GF256 {
    static let primitivePoly: UInt8 = 0x87 // x^8 + x^7 + x^2 + x + 1 = 0x187, low 8 bits = 0x87
    static let generator: UInt8 = 0x02

    private static var expTable: [UInt8] = {
        var table = [UInt8](repeating: 0, count: 512)
        var x: UInt8 = 1
        for i in 0..<255 {
            table[i] = x
            table[i &+ 255] = x
            var hi = x & 0x80
            x &*= 2
            if hi != 0 {
                x ^= primitivePoly
            }
        }
        table[255] = 1
        return table
    }()

    private static var logTable: [UInt8] = {
        var table = [UInt8](repeating: 0, count: 256)
        for i in 0..<255 {
            table[Int(expTable[i])] = UInt8(i)
        }
        return table
    }()

    static func mul(_ a: UInt8, _ b: UInt8) -> UInt8 {
        guard a != 0 && b != 0 else { return 0 }
        return expTable[Int(logTable[Int(a)]) &+ Int(logTable[Int(b)])]
    }

    static func div(_ a: UInt8, _ b: UInt8) -> UInt8 {
        guard a != 0 && b != 0 else { return 0 }
        return expTable[Int(logTable[Int(a)]) &+ 255 &- Int(logTable[Int(b)])]
    }

    static func exp(_ a: UInt8) -> UInt8 {
        return expTable[Int(a)]
    }

    static func log(_ a: UInt8) -> UInt8 {
        guard a != 0 else { return 0 }
        return logTable[Int(a)]
    }

    static func inv(_ a: UInt8) -> UInt8 {
        guard a != 0 else { return 0 }
        return expTable[255 &- Int(logTable[Int(a)])]
    }

    static func polyMul(_ p: [UInt8], _ q: [UInt8]) -> [UInt8] {
        let rLen = p.count + q.count - 1
        var r = [UInt8](repeating: 0, count: rLen)
        for i in 0..<p.count {
            for j in 0..<q.count {
                r[i + j] ^= mul(p[i], q[j])
            }
        }
        return r
    }
}

// MARK: - Reed-Solomon Decoder

private struct RSDecoder {
    let n: Int
    let k: Int
    let t: Int
    let npar: Int
    let gfpoly: [UInt8]

    static func generatorPoly(npar: Int) -> [UInt8] {
        var g = [UInt8]([1])
        for i in 0..<npar {
            let term: [UInt8] = [1, GF256.exp(UInt8(i))]
            g = GF256.polyMul(g, term)
        }
        return g
    }

    init(n: Int, k: Int) {
        self.n = n
        self.k = k
        self.npar = n - k
        self.t = self.npar / 2
        self.gfpoly = RSDecoder.generatorPoly(npar: self.npar)
    }

    func syndromes(_ received: [UInt8]) -> [UInt8] {
        var synd = [UInt8](repeating: 0, count: npar)
        for i in 0..<npar {
            var val: UInt8 = 0
            for j in 0..<received.count {
                val ^= GF256.mul(received[j], GF256.exp(UInt8(i) * UInt8(j)))
            }
            synd[i] = val
        }
        return synd
    }

    func berlekampMassey(_ synd: [UInt8]) -> [UInt8]? {
        var errLoc = [UInt8]([1])
        var oldLoc = [UInt8]([1])
        var _ = 1

        for i in 0..<npar {
            var delta: UInt8 = synd[i]
            for j in 1..<errLoc.count {
                delta ^= GF256.mul(errLoc[errLoc.count - 1 - j], synd[i &- j])
            }
            oldLoc.append(0)
            if delta != 0 {
                if errLoc.count < oldLoc.count {
                    let newLoc = scalePoly(oldLoc, delta)
                    let newOld = scalePoly(errLoc, GF256.inv(delta))
                    errLoc = newLoc
                    oldLoc = newOld
                    _ = i
                } else {
                    let shifted = shiftPoly(oldLoc, 1)
                    let scaled = scalePoly(shifted, delta)
                    errLoc = addPoly(errLoc, scaled)
                }
            }
        }

        while errLoc.count > 1 && errLoc[0] == 0 {
            errLoc.removeFirst()
        }

        let numErrors = errLoc.count - 1
        guard numErrors <= t else { return nil }

        return errLoc
    }

    private func scalePoly(_ p: [UInt8], _ s: UInt8) -> [UInt8] {
        return p.map { GF256.mul($0, s) }
    }

    private func shiftPoly(_ p: [UInt8], _ shift: Int) -> [UInt8] {
        return [UInt8](repeating: 0, count: shift) + p
    }

    private func addPoly(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] {
        let maxLen = max(a.count, b.count)
        var result = [UInt8](repeating: 0, count: maxLen)
        for i in 0..<a.count {
            result[maxLen - a.count + i] ^= a[i]
        }
        for i in 0..<b.count {
            result[maxLen - b.count + i] ^= b[i]
        }
        return result
    }

    func findErrors(_ errLoc: [UInt8], n: Int) -> [Int]? {
        var positions = [Int]()
        let numErrors = errLoc.count - 1
        for i in 0..<n {
            var val: UInt8 = 0
            for j in 0..<errLoc.count {
                val ^= GF256.mul(errLoc[j], GF256.exp(UInt8((errLoc.count - 1 - j) * i) & 0xFF))
            }
            if val == 0 {
                let pos = (n - 1 - i) % n
                positions.append(pos)
            }
        }
        if positions.count == numErrors {
            return positions.sorted()
        }
        return nil
    }

    func errorEvaluator(_ synd: [UInt8], _ errLoc: [UInt8]) -> [UInt8] {
        let product = GF256.polyMul(errLoc, [UInt8](repeating: 0, count: 1) + synd)
        let remainder = [UInt8](product.suffix(npar + 1))
        return remainder
    }

    func correct(_ received: inout [UInt8]) -> Bool {
        guard received.count == n else { return false }

        let synd = syndromes(received)
        let allZero = synd.allSatisfy { $0 == 0 }
        if allZero { return true }

        guard let errLoc = berlekampMassey(synd) else { return false }

        guard let errorPos = findErrors(errLoc, n: n) else { return false }

        let omega = errorEvaluator(synd, errLoc)

        for pos in errorPos {
            let xiInv = GF256.exp(UInt8((n - 1 - pos) % 255))
            var errDeriv: UInt8 = 0
            for j in stride(from: 1, to: errLoc.count, by: 2) {
                if j < errLoc.count {
                    errDeriv ^= GF256.mul(errLoc[errLoc.count - 1 - j], UInt8(j))
                }
            }
            guard errDeriv != 0 else { return false }

            var errVal: UInt8 = 0
            for j in 0..<omega.count {
                errVal ^= GF256.mul(omega[omega.count - 1 - j], GF256.exp(UInt8((n - 1 - pos) * j) & 0xFF))
            }

            let magnitude = GF256.div(errVal, GF256.mul(xiInv, errDeriv))
            received[pos] ^= magnitude
        }

        let verifySynd = syndromes(received)
        return verifySynd.allSatisfy { $0 == 0 }
    }
}

// MARK: - CPFSK Demodulator

private class CPFSKDemodulator {
    private var prevPhase: Float = 0
    private var sampleCounter: Int = 0
    private let samplesPerSymbol: Int
    private var demodBits: [Bool] = []
    private let symbolDeviation: Float = Float.pi / 2.0

    init(samplesPerSymbol: Int) {
        self.samplesPerSymbol = samplesPerSymbol
    }

    func reset() {
        prevPhase = 0
        sampleCounter = 0
        demodBits.removeAll()
    }

    func process(_ sample: ComplexFloat) {
        let phase = sample.phase
        let dPhase = phase - prevPhase
        prevPhase = phase

        let wrapped = dPhase > .pi ? dPhase - 2 * .pi : (dPhase < -.pi ? dPhase + 2 * .pi : dPhase)

        sampleCounter += 1
        if sampleCounter >= samplesPerSymbol {
            sampleCounter = 0
            let bit = wrapped > 0
            demodBits.append(bit)
        }
    }

    func extractBits() -> [Bool] {
        let bits = demodBits
        demodBits.removeAll()
        return bits
    }
}

// MARK: - Sync Word Correlator

private class SyncCorrelator {
    static let syncWord: [Bool] = [
        false,false,true,true,false,true,false,false,true,false,false,true,false,true,true,false,
        true,false,true,false,false,true,true,false,true,false,true,false,true,true,false,false
    ]
    static let syncWordBits = 36
    static let threshold: Int = 5

    private(set) var bitBuffer: [Bool] = []
    private var correlations: [(position: Int, errors: Int)] = []

    func reset() {
        bitBuffer.removeAll()
        correlations.removeAll()
    }

    func pushBits(_ bits: [Bool]) {
        bitBuffer.append(contentsOf: bits)
    }

    func search() -> [Int] {
        var positions = [Int]()
        let sync = SyncCorrelator.syncWord

        guard bitBuffer.count >= sync.count else { return positions }

        let searchLen = bitBuffer.count - sync.count + 1
        for i in 0..<searchLen {
            var errors = 0
            for j in 0..<sync.count {
                if bitBuffer[i + j] != sync[j] {
                    errors += 1
                    if errors > SyncCorrelator.threshold { break }
                }
            }
            if errors <= SyncCorrelator.threshold {
                positions.append(i + sync.count)
            }
        }
        return positions
    }

    func consume(upTo position: Int) {
        guard position <= bitBuffer.count else {
            bitBuffer.removeAll()
            return
        }
        bitBuffer.removeFirst(position)
    }

    var availableBits: Int { bitBuffer.count }
}

// MARK: - UAT Frame Types

private enum UATFrameType {
    case short
    case long

    var totalBits: Int {
        switch self {
        case .short: return 240
        case .long:  return 384
        }
    }

    var dataBytes: Int {
        switch self {
        case .short: return 144
        case .long:  return 208
        }
    }

    var parityBytes: Int {
        switch self {
        case .short: return 96
        case .long:  return 176
        }
    }

    var rsN: Int {
        switch self {
        case .short: return 184
        case .long:  return 272
        }
    }

    var rsK: Int {
        switch self {
        case .short: return 144
        case .long:  return 208
        }
    }
}

// MARK: - UAT Message Types

private enum UATMessageType: UInt8 {
    case basicADS_B = 0
    case longADS_B = 1
    case groundStation = 2
    case tIS_B = 3
    case reserved = 4
    case auxiliary = 5
    case uplinkInfoFIS_B = 6
    case uplinkInfoFIS_BLong = 7
    case uplinkInfoFIS_BLong2 = 8

    static func fromByte(_ byte: UInt8) -> UATMessageType {
        let msgType = (byte >> 2) & 0x3F
        return UATMessageType(rawValue: msgType) ?? .reserved
    }
}

// MARK: - UAT Decoder

public class UATDecoder: DSPBlock {
    public var name: String = "UAT/FIS-B Decoder"
    public var sampleRate: Double
    public var inputChannels = 1
    public var outputChannels = 1

    private var demodulator: CPFSKDemodulator
    private var syncCorrelator: SyncCorrelator
    private let rsShort: RSDecoder
    private let rsLong: RSDecoder

    private var bitBuffer: [Bool] = []
    private var assemblerMap: [UInt16: FISBAssembler] = [:]

    public var onWeatherUpdate: ((FISBFrame) -> Void)?
    public var onNEXRADBlock: ((FISBNEXRADBlock) -> Void)?
    public var onMessageDecoded: ((String) -> Void)?

    public init(sampleRate: Double = 2_048_000) {
        self.sampleRate = sampleRate
        let sps = max(1, Int(sampleRate / 1_000_000))
        self.demodulator = CPFSKDemodulator(samplesPerSymbol: sps)
        self.syncCorrelator = SyncCorrelator()
        self.rsShort = RSDecoder(n: 184, k: 144)
        self.rsLong = RSDecoder(n: 272, k: 208)
    }

    public func process(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        for i in 0..<count {
            output[i] = input[i]
            demodulator.process(input[i])
        }

        let newBits = demodulator.extractBits()
        guard !newBits.isEmpty else { return }

        syncCorrelator.pushBits(newBits)

        let positions = syncCorrelator.search()
        for syncEnd in positions {
            tryDecodeFrame(atBitOffset: syncEnd)
        }

        if syncCorrelator.availableBits > 600 {
            syncCorrelator.consume(upTo: syncCorrelator.availableBits - 500)
        }
    }

    private func tryDecodeFrame(atBitOffset offset: Int) {
        let available = syncCorrelator.availableBits - offset
        guard available >= 240 else { return }

        for frameType in [UATFrameType.long, .short] {
            guard available >= frameType.totalBits else { continue }

            let bits = (0..<frameType.totalBits).map { syncCorrelator.bitBuffer[offset + $0] }
            let rawBytes = bitsToBytes(bits)

            var rsData = rawBytes
            let corrected: Bool

            switch frameType {
            case .short:
                var rsBlock = [UInt8](repeating: 0, count: rsShort.n)
                rsBlock[0..<144] = rsData[0..<144]
                rsBlock[144..<184] = rsData[144..<184]
                corrected = rsShort.correct(&rsBlock)
                if corrected { rsData = [UInt8](rsBlock[0..<144]) }
            case .long:
                var rsBlock = [UInt8](repeating: 0, count: rsLong.n)
                rsBlock[0..<208] = rsData[0..<208]
                rsBlock[208..<272] = rsData[208..<240]
                corrected = rsLong.correct(&rsBlock)
                if corrected { rsData = [UInt8](rsBlock[0..<208]) }
            }

            if corrected {
                dispatchMessage(rsData, frameType: frameType)
                return
            }
        }
    }

    private func bitsToBytes(_ bits: [Bool]) -> [UInt8] {
        let byteCount = bits.count / 8
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for i in 0..<byteCount {
            var byte: UInt8 = 0
            for j in 0..<8 {
                if bits[i * 8 + j] {
                    byte |= UInt8(1 << (7 - j))
                }
            }
            bytes[i] = byte
        }
        return bytes
    }

    private func dispatchMessage(_ data: [UInt8], frameType: UATFrameType) {
        guard !data.isEmpty else { return }
        let msgType = UATMessageType.fromByte(data[0])

        switch msgType {
        case .basicADS_B:
            decodeBasicADS_B(data)
        case .longADS_B:
            decodeLongADS_B(data)
        case .uplinkInfoFIS_B, .uplinkInfoFIS_BLong, .uplinkInfoFIS_BLong2:
            decodeFIS_B(data)
        default:
            break
        }
    }

    private func decodeBasicADS_B(_ data: [UInt8]) {
        guard data.count >= 18 else { return }

        let icao24 = (UInt32(data[1]) << 16) | (UInt32(data[2]) << 8) | UInt32(data[3])

        let altitudeRaw = (UInt16(data[5]) << 4) | (UInt16(data[6]) >> 4)
        let altitude: Int32? = altitudeRaw > 0 ? Int32(altitudeRaw) * 25 - 1000 : nil

        let latRaw = (UInt32(data[7]) << 16) | (UInt32(data[8]) << 8) | UInt32(data[9])
        let lonRaw = (UInt32(data[10]) << 16) | (UInt32(data[11]) << 8) | UInt32(data[12])

        let latitude = latRaw > 0 ? Double(latRaw) * 360.0 / 16777216.0 - 90.0 : nil
        let longitude = lonRaw > 0 ? Double(lonRaw) * 360.0 / 16777216.0 - 180.0 : nil

        let speedEwRaw = (UInt16(data[13]) << 4) | (UInt16(data[14]) >> 4)
        let speedNsRaw = ((UInt16(data[14]) & 0x0F) << 8) | UInt16(data[15])
        let speedKnots: UInt16? = speedEwRaw > 0 || speedNsRaw > 0 ?
            UInt16(sqrt(Float(speedEwRaw) * Float(speedEwRaw) + Float(speedNsRaw) * Float(speedNsRaw))) : nil

        let trackRaw = (UInt16(data[16]) << 2) | (UInt16(data[17]) >> 6)
        let track: UInt16? = trackRaw > 0 ? UInt16(Float(trackRaw) * 360.0 / 256.0) : nil

        let _ = UATADSMessage(icao24: icao24, latitude: latitude, longitude: longitude,
                              altitude: altitude, speedKnots: speedKnots, track: track,
                              callsign: nil, messageType: 0)

        let hex = String(format: "%06X", icao24)
        var desc = "ADS-B \(hex)"
        if let lat = latitude, let lon = longitude {
            desc += String(format: " %.4f/%.4f", lat, lon)
        }
        if let alt = altitude {
            desc += " \(alt)ft"
        }
        if let spd = speedKnots {
            desc += " \(spd)kt"
        }
        onMessageDecoded?(desc)
    }

    private func decodeLongADS_B(_ data: [UInt8]) {
        guard data.count >= 26 else { return }

        let icao24 = (UInt32(data[1]) << 16) | (UInt32(data[2]) << 8) | UInt32(data[3])

        let callsignBytes = data[7..<13].map { $0 & 0x3F }
        let callsign = String(callsignBytes.map { byte in
            let c: UInt8
            switch byte {
            case 1...26:  c = UInt8(0x40 + byte)
            case 27...36: c = UInt8(0x30 - 27 + byte)
            case 0:       c = UInt8(ascii: " ")
            default:      c = byte
            }
            return Character(UnicodeScalar(c))
        }).trimmingCharacters(in: .whitespaces)

        let altitudeRaw = (UInt16(data[13]) << 4) | (UInt16(data[14]) >> 4)
        let altitude: Int32? = altitudeRaw > 0 ? Int32(altitudeRaw) * 25 - 1000 : nil

        let latRaw = (UInt32(data[15]) << 16) | (UInt32(data[16]) << 8) | UInt32(data[17])
        let lonRaw = (UInt32(data[18]) << 16) | (UInt32(data[19]) << 8) | UInt32(data[20])

        let latitude = latRaw > 0 ? Double(latRaw) * 360.0 / 16777216.0 - 90.0 : nil
        let longitude = lonRaw > 0 ? Double(lonRaw) * 360.0 / 16777216.0 - 180.0 : nil

        var desc = "ADS-B \(String(format: "%06X", icao24)) \(callsign)"
        if let lat = latitude, let lon = longitude {
            desc += String(format: " %.4f/%.4f", lat, lon)
        }
        if let alt = altitude {
            desc += " \(alt)ft"
        }
        onMessageDecoded?(desc)
    }

    private func decodeFIS_B(_ data: [UInt8]) {
        guard data.count >= 10 else { return }

        let msgType = UATMessageType.fromByte(data[0])
        let isDoubleFrame = (msgType == .uplinkInfoFIS_BLong || msgType == .uplinkInfoFIS_BLong2)

        let payloadOffset: Int
        if isDoubleFrame {
            payloadOffset = 10
        } else {
            payloadOffset = 1
        }

        guard data.count > payloadOffset else { return }

        let _ = data[1]
        let _ = (UInt32(data[2]) << 16) | (UInt32(data[3]) << 8) | UInt32(data[4])
        let _ = isDoubleFrame ? 2 : 1

        let payload = [UInt8](data[payloadOffset..<min(data.count, data.count)])

        var offset = 0
        while offset + 8 <= payload.count {
            let productId = (UInt16(payload[offset]) << 8) | UInt16(payload[offset + 1])
            let productTime = (UInt32(payload[offset + 2]) << 24) | (UInt32(payload[offset + 3]) << 16) |
                              (UInt32(payload[offset + 4]) << 8) | UInt32(payload[offset + 5])
            let lapNum = Int(payload[offset + 6])
            let totalLaps = Int(payload[offset + 7])

            offset += 8

            guard totalLaps > 0 else { break }

        var _ = 0
        if lapNum == 0 {
            if offset + 2 <= payload.count {
                _ = (Int(payload[offset]) << 8) | Int(payload[offset + 1])
                    offset += 2
                }
            }

            var lapDataLen = (payload.count - offset) / totalLaps
            if totalLaps == 1 || lapNum == totalLaps - 1 {
                lapDataLen = payload.count - offset
            }
            lapDataLen = min(lapDataLen, payload.count - offset)

            guard lapDataLen > 0 else { break }

            let lapData = Data(payload[offset..<(offset + lapDataLen)])
            offset += lapDataLen

            let packetType = FISBPacketType(productId: productId)

            let frame = FISBFrame(
                type: packetType,
                lapIndex: lapNum,
                totalLaps: totalLaps,
                data: lapData,
                timestamp: Date(),
                productId: productId,
                productTime: productTime
            )

            onWeatherUpdate?(frame)
            for block in FISBNEXRADBlockDecoder.decode(frame: frame) {
                onNEXRADBlock?(block)
            }

            if packetType == .nexradRegional || packetType == .nexradCONUS {
                if assemblerMap[productId] == nil {
                    assemblerMap[productId] = FISBAssembler(totalLaps: totalLaps)
                }
                if let image = assemblerMap[productId]?.addFrame(frame) {
                    onMessageDecoded?("NEXRAD image assembled: \(image.count) cells, product \(productId)")
                }
            } else if packetType == .metar {
                if let text = parseTextProduct(lapData) {
                    onMessageDecoded?("METAR: \(text)")
                }
            } else if packetType == .taf {
                if let text = parseTextProduct(lapData) {
                    onMessageDecoded?("TAF: \(text)")
                }
            } else if packetType == .sigmet {
                onMessageDecoded?("SIGMET received")
            } else if packetType == .airmet {
                onMessageDecoded?("AIRMET received")
            }

            if offset >= payload.count { break }
        }
    }

    private func parseTextProduct(_ data: Data) -> String? {
        guard data.count > 0 else { return nil }
        var text = String(data: data, encoding: .ascii)
            ?? String(data: data, encoding: .utf8)
            ?? nil
        text = text?.trimmingCharacters(in: .controlCharacters.union(.whitespaces))
        guard let t = text, !t.isEmpty else { return nil }
        return t
    }

    public func reset() {
        demodulator.reset()
        syncCorrelator.reset()
        bitBuffer.removeAll()
        assemblerMap.removeAll()
    }

    public func configure(params: [String: Any]) {
        if let sr = params["sampleRate"] as? Double {
            sampleRate = sr
            let sps = max(1, Int(sr / 1_000_000))
            demodulator = CPFSKDemodulator(samplesPerSymbol: sps)
        }
    }

    public func ingestRawMessageBytes(_ bytes: [UInt8], isUplink: Bool) {
        let inferredType: UATFrameType
        if isUplink {
            inferredType = .long
        } else {
            inferredType = bytes.count > 18 ? .long : .short
        }
        dispatchMessage(bytes, frameType: inferredType)
    }

    public func ingestDump978RawLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let prefix = trimmed.first, prefix == "+" || prefix == "-" else { return }

        let payloadSection = trimmed.dropFirst().split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first ?? Substring()
        let hex = payloadSection.trimmingCharacters(in: .whitespaces)
        guard !hex.isEmpty else { return }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)

        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard next > index else { break }
            let pair = hex[index..<next]
            guard pair.count == 2, let byte = UInt8(pair, radix: 16) else { return }
            bytes.append(byte)
            index = next
        }

        ingestRawMessageBytes(bytes, isUplink: prefix == "+")
    }
}

// MARK: - FIS-B NEXRAD Assembler

public class FISBAssembler {
    public static let defaultLapWidth = 128
    private var laps: [Int: Data] = [:]
    private let totalLaps: Int

    public init(totalLaps: Int = 11) {
        self.totalLaps = totalLaps
    }

    public func addFrame(_ frame: FISBFrame) -> [Float]? {
        guard frame.type == .nexradRegional || frame.type == .nexradCONUS else { return nil }

        laps[frame.lapIndex] = frame.data

        if laps.count >= totalLaps {
            return assembleImage()
        }

        if frame.lapIndex == frame.totalLaps - 1 && laps.count == frame.totalLaps {
            return assembleImage()
        }

        return nil
    }

    private func assembleImage() -> [Float] {
        var fullImage: [Float] = []

        for i in 0..<totalLaps {
            if let lapData = laps[i] {
                var values = decodeLapReflectivity(lapData)
                if values.count < Self.defaultLapWidth {
                    values.append(contentsOf: [Float](repeating: -33.0, count: Self.defaultLapWidth - values.count))
                } else if values.count > Self.defaultLapWidth {
                    values = Array(values.prefix(Self.defaultLapWidth))
                }
                fullImage.append(contentsOf: values)
            } else {
                fullImage.append(contentsOf: [Float](repeating: -33.0, count: Self.defaultLapWidth))
            }
        }

        laps.removeAll()
        return fullImage
    }

    private func decodeLapReflectivity(_ data: Data) -> [Float] {
        var values: [Float] = []
        var offset = 0

        while offset + 1 < data.count {
            let count = Int(data[offset])
            let rawDbz = data[offset + 1]
            offset += 2

            let dbz = Float(rawDbz) * 0.5 - 10.0

            for _ in 0..<count {
                values.append(dbz)
            }

            if count == 0 { break }
        }

        return values
    }

    public func reset() {
        laps.removeAll()
    }
}

public enum FISBNEXRADBlockDecoder {
    private static let blockWidth: Double = 48.0 / 60.0
    private static let wideBlockWidth: Double = 96.0 / 60.0
    private static let blockHeight: Double = 4.0 / 60.0
    private static let blockThreshold = 405_000
    private static let blocksPerRing = 450

    public static func decode(frame: FISBFrame) -> [FISBNEXRADBlock] {
        guard frame.type == .nexradRegional || frame.type == .nexradCONUS else { return [] }
        let bytes = [UInt8](frame.data)
        guard bytes.count >= 4 else { return [] }

        let rleFlag = (bytes[0] & 0x80) != 0
        let nsFlag = (bytes[0] & 0x40) != 0
        let scaleFactor = Int((bytes[0] & 0x30) >> 4)
        let blockNum = (Int(bytes[0] & 0x0F) << 16) | (Int(bytes[1]) << 8) | Int(bytes[2])

        if rleFlag {
            let bins = decodeRLEBins(bytes: bytes, start: 3)
            guard bins.count == 128 else { return [] }
            return [makeBlock(frame: frame, blockNum: blockNum, nsFlag: nsFlag, scaleFactor: scaleFactor, bins: bins)]
        }

        return decodeEmptyBlocks(frame: frame, bytes: bytes, baseBlockNum: blockNum, nsFlag: nsFlag, scaleFactor: scaleFactor)
    }

    private static func decodeRLEBins(bytes: [UInt8], start: Int) -> [Float] {
        var bins: [Float] = []
        bins.reserveCapacity(128)

        for index in start..<bytes.count {
            let intensity = Int(bytes[index] & 0x07)
            let runLength = Int(bytes[index] >> 3) + 1
            for _ in 0..<runLength where bins.count < 128 {
                bins.append(mapIntensityToDBZ(intensity))
            }
            if bins.count >= 128 { break }
        }

        if bins.count < 128 {
            bins.append(contentsOf: [Float](repeating: mapIntensityToDBZ(0), count: 128 - bins.count))
        }
        return bins
    }

    private static func decodeEmptyBlocks(frame: FISBFrame, bytes: [UInt8], baseBlockNum: Int, nsFlag: Bool, scaleFactor: Int) -> [FISBNEXRADBlock] {
        let length = Int(bytes[3] & 0x0F)
        guard length > 0 else { return [] }

        let rowStart: Int
        let rowSize: Int
        if baseBlockNum >= blockThreshold {
            rowStart = baseBlockNum - ((baseBlockNum - blockThreshold) % 225)
            rowSize = 225
        } else {
            rowStart = baseBlockNum - (baseBlockNum % 450)
            rowSize = 450
        }
        let rowOffset = baseBlockNum - rowStart

        var blocks: [FISBNEXRADBlock] = []
        for i in 0..<length {
            let byteValue: Int
            if i == 0 {
                byteValue = Int(bytes[3] & 0xF0) | 0x08
            } else if (i + 3) < bytes.count {
                byteValue = Int(bytes[i + 3])
            } else {
                break
            }

            for j in 0..<8 {
                if (byteValue & (1 << j)) == 0 { continue }
                let rowX = (rowOffset + 8 * i + j - 3) % rowSize
                let blockNum = rowStart + rowX
                let fillIntensity = frame.type == .nexradRegional ? 0 : 1
                let bins = [Float](repeating: mapIntensityToDBZ(fillIntensity), count: 128)
                blocks.append(makeBlock(frame: frame, blockNum: blockNum, nsFlag: nsFlag, scaleFactor: scaleFactor, bins: bins))
            }
        }
        return blocks
    }

    private static func makeBlock(frame: FISBFrame, blockNum: Int, nsFlag: Bool, scaleFactor: Int, bins: [Float]) -> FISBNEXRADBlock {
        let geometry = blockLocation(blockNum: blockNum, nsFlag: nsFlag, scaleFactor: scaleFactor)
        let lonWestNormalized = geometry.lonWest > 180 ? geometry.lonWest - 360 : geometry.lonWest
        let key = "\(frame.productTime):\(frame.type):\(blockNum):\(nsFlag ? 1 : 0):\(scaleFactor)"
        return FISBNEXRADBlock(
            key: key,
            type: frame.type,
            productTime: frame.productTime,
            latitudeNorth: geometry.latNorth,
            longitudeWest: lonWestNormalized,
            latitudeSize: geometry.latSize,
            longitudeSize: geometry.lonSize,
            scaleFactor: scaleFactor,
            bins: bins,
            timestamp: frame.timestamp
        )
    }

    private static func blockLocation(blockNum: Int, nsFlag: Bool, scaleFactor: Int) -> (latNorth: Double, lonWest: Double, latSize: Double, lonSize: Double) {
        let scale: Double
        switch scaleFactor {
        case 1: scale = 5.0
        case 2: scale = 9.0
        default: scale = 1.0
        }

        var normalizedBlockNum = blockNum
        if normalizedBlockNum >= blockThreshold {
            normalizedBlockNum &= ~1
        }

        let rawLat = blockHeight * trunc(Double(normalizedBlockNum) / Double(blocksPerRing))
        let rawLon = Double(normalizedBlockNum % blocksPerRing) * blockWidth
        let lonSize = (normalizedBlockNum >= blockThreshold ? wideBlockWidth : blockWidth) * scale
        let latSize = blockHeight * scale
        let latNorth = nsFlag ? (0.0 - rawLat) : (rawLat + blockHeight)
        return (latNorth: latNorth, lonWest: rawLon, latSize: latSize, lonSize: lonSize)
    }

    private static func mapIntensityToDBZ(_ intensity: Int) -> Float {
        switch intensity {
        case 0: return 0
        case 1: return 8
        case 2: return 18
        case 3: return 28
        case 4: return 38
        case 5: return 48
        case 6: return 58
        case 7: return 68
        default: return 0
        }
    }
}
