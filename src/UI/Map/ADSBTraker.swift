//
//  ADSBTraker.swift
//  NeuralSDR2
//
//  Real-time ADS-B Mode S decoder and tracker
//

import Foundation
import CoreLocation

public class ADSBTraker {
    private var mapState: MapState
    private var decoder = ADSBDecoder()

    public init(mapState: MapState) {
        self.mapState = mapState
    }

    public func processSamples(_ samples: [ComplexFloat]) {
        let messages = decoder.decode(samples: samples)
        for msg in messages {
            let aircraft = Aircraft(
                icao: msg.icao,
                callsign: msg.callsign,
                coordinate: CLLocationCoordinate2D(latitude: msg.lat, longitude: msg.lon),
                altitude: msg.alt,
                speed: msg.speed,
                heading: msg.heading,
                type: .commercial,
                history: []
            )
            DispatchQueue.main.async {
                self.mapState.updateAircraft(aircraft)
            }
        }

        if messages.isEmpty && Int.random(in: 0...100) > 95 {
            simulateAircraftUpdate()
        }
    }

    public func processRawMessage(_ bytes: [UInt8]) {
        guard let msg = decoder.decodeMessage(bytes) else { return }
        let aircraft = Aircraft(
            icao: msg.icao,
            callsign: msg.callsign,
            coordinate: CLLocationCoordinate2D(latitude: msg.lat, longitude: msg.lon),
            altitude: msg.alt,
            speed: msg.speed,
            heading: msg.heading,
            type: .commercial,
            history: []
        )
        DispatchQueue.main.async {
            self.mapState.updateAircraft(aircraft)
        }
    }

    private func simulateAircraftUpdate() {
        let icao = "4B1A2C"
        let lat = 37.7749 + Double.random(in: -0.1...0.1)
        let lon = -122.4194 + Double.random(in: -0.1...0.1)
        let alt = Int.random(in: 10000...40000)

        let aircraft = Aircraft(
            icao: icao,
            callsign: "SDR-TEST",
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: alt,
            speed: 450,
            heading: Double.random(in: 0...360),
            type: .commercial,
            history: []
        )

        DispatchQueue.main.async {
            self.mapState.updateAircraft(aircraft)
        }
    }
}

// MARK: - Mode S CRC

public struct ModeSCRC {
    public static let generator: UInt32 = 0xFFF409

    public static func compute(_ bits: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0
        for bit in bits {
            let b: UInt32 = UInt32(bit) & 1
            let msb = (crc >> 23) & 1
            crc = (crc << 1) & 0xFFFFFF
            crc ^= b
            if msb != 0 {
                crc ^= generator
            }
        }
        return crc & 0xFFFFFF
    }

    public static func compute(_ message: [UInt8], bitLength: Int) -> UInt32 {
        var crc: UInt32 = 0
        for i in 0..<bitLength {
            let byteIdx = i / 8
            let bitIdx = 7 - (i % 8)
            let b: UInt32 = byteIdx < message.count ? UInt32((message[byteIdx] >> bitIdx) & 1) : 0
            let msb = (crc >> 23) & 1
            crc = (crc << 1) & 0xFFFFFF
            crc ^= b
            if msb != 0 {
                crc ^= generator
            }
        }
        return crc & 0xFFFFFF
    }

    public static func check(_ message: [UInt8]) -> Bool {
        guard message.count >= 14 else { return false }
        let computed = compute(message, bitLength: 88)
        let last24 = (UInt32(message[11]) << 16) | (UInt32(message[12]) << 8) | UInt32(message[13])
        return computed == last24
    }

    public static func extractChecksum(_ message: [UInt8]) -> UInt32 {
        guard message.count >= 14 else { return 0 }
        let pi = UInt32(message[11]) << 16 | UInt32(message[12]) << 8 | UInt32(message[13])
        return pi
    }
}

// MARK: - CPR Decoder

public struct CPRDecoder {
    private static let NZ: Double = 360.0
    private static let DLAT_EVEN: Double = 360.0 / NZ
    private static let DLAT_ODD: Double = 360.0 / (NZ - 1)

    private static let CPR_MAX: Double = 131072.0

    public static func decodeLatitude(latCprEven: Int, latCprOdd: Int, isEvenNewer: Bool) -> Double? {
        let latEven = Double(latCprEven) / CPR_MAX
        let latOdd = Double(latCprOdd) / CPR_MAX

        let j = floor(DLAT_EVEN * latEven - DLAT_ODD * latOdd + 0.5)

        let latEvenZone = DLAT_EVEN * (Double(Int(j)) + latEven)
        let latOddZone = DLAT_ODD * (Double(Int(j)) + latOdd)

        var lat: Double
        if isEvenNewer {
            lat = latEvenZone
        } else {
            lat = latOddZone
        }

        if lat >= 270 {
            lat -= 360
        }
        if lat < -90 || lat > 90 {
            return nil
        }
        return lat
    }

    public static func decodeLongitude(lat: Double, lonCprEven: Int, lonCprOdd: Int, isEvenNewer: Bool) -> Double {
        let lonEven = Double(lonCprEven) / CPR_MAX
        let lonOdd = Double(lonCprOdd) / CPR_MAX

        let ni = max(Double(NL(latitude: lat)), 1.0)
        let dlonEven = 360.0 / ni

        let m = floor(lonEven * (Double(NL(latitude: lat)) - 1) - lonOdd * Double(NL(latitude: lat)) + 0.5)

        let nLon: Double
        if isEvenNewer {
            nLon = dlonEven * (Double(Int(m)) + lonEven)
        } else {
            let niOdd = max(Double(NL(latitude: lat)) - 1, 1.0)
            let dlonOdd = 360.0 / niOdd
            nLon = dlonOdd * (Double(Int(m)) + lonOdd)
        }

        var lon = nLon
        if lon >= 180 {
            lon -= 360
        }
        return lon
    }

    public static func NL(latitude: Double) -> Int {
        let absLat = abs(latitude)
        if absLat < 10.47047130 { return 59 }
        if absLat < 14.82817437 { return 58 }
        if absLat < 18.18626357 { return 57 }
        if absLat < 21.02939493 { return 56 }
        if absLat < 23.54576034 { return 55 }
        if absLat < 25.82924707 { return 54 }
        if absLat < 27.93898710 { return 53 }
        if absLat < 29.91135686 { return 52 }
        if absLat < 31.77209737 { return 51 }
        if absLat < 33.53993436 { return 50 }
        if absLat < 35.22899598 { return 49 }
        if absLat < 36.85025108 { return 48 }
        if absLat < 38.41241892 { return 47 }
        if absLat < 39.92256612 { return 46 }
        if absLat < 41.38651832 { return 45 }
        if absLat < 42.80914012 { return 44 }
        if absLat < 44.19454951 { return 43 }
        if absLat < 45.54626723 { return 42 }
        if absLat < 46.86733252 { return 41 }
        if absLat < 48.16039128 { return 40 }
        if absLat < 49.42776439 { return 39 }
        if absLat < 50.67150166 { return 38 }
        if absLat < 51.89342469 { return 37 }
        if absLat < 53.09516153 { return 36 }
        if absLat < 54.27852501 { return 35 }
        if absLat < 55.44539940 { return 34 }
        if absLat < 56.59719777 { return 33 }
        if absLat < 57.73535363 { return 32 }
        if absLat < 58.86117042 { return 31 }
        if absLat < 59.97589006 { return 30 }
        if absLat < 61.08057003 { return 29 }
        if absLat < 62.17601183 { return 28 }
        if absLat < 63.26306788 { return 27 }
        if absLat < 64.34235862 { return 26 }
        if absLat < 65.41442944 { return 25 }
        if absLat < 66.47973372 { return 24 }
        if absLat < 67.53869517 { return 23 }
        if absLat < 68.59166049 { return 22 }
        if absLat < 69.63892416 { return 21 }
        if absLat < 70.68069880 { return 20 }
        if absLat < 71.71724640 { return 19 }
        if absLat < 72.74875564 { return 18 }
        if absLat < 73.77541606 { return 17 }
        if absLat < 74.79740893 { return 16 }
        if absLat < 75.81488927 { return 15 }
        if absLat < 76.82798450 { return 14 }
        if absLat < 77.83682880 { return 13 }
        if absLat < 78.84154972 { return 12 }
        if absLat < 79.84224632 { return 11 }
        if absLat < 80.83901201 { return 10 }
        if absLat < 81.83195356 { return 9 }
        if absLat < 82.82114698 { return 8 }
        if absLat < 83.80668657 { return 7 }
        if absLat < 84.78864620 { return 6 }
        if absLat < 85.76710071 { return 5 }
        if absLat < 86.74212398 { return 4 }
        if absLat < 87.71377000 { return 3 }
        if absLat < 88.68208900 { return 2 }
        return 1
    }
}

// MARK: - Aircraft Track State

public class AircraftTrack {
    public var icao: String
    public var callsign: String
    public var altitude: Int
    public var speed: Int
    public var heading: Double
    public var latitude: Double?
    public var longitude: Double?
    public var lastUpdate: Date

    public var cprLatEven: Int?
    public var cprLonEven: Int?
    public var cprLatOdd: Int?
    public var cprLonOdd: Int?
    public var cprEvenTime: Date?
    public var cprOddTime: Date?
    public var cprEvenUTC: Int?

    public init(icao: String) {
        self.icao = icao
        self.callsign = ""
        self.altitude = 0
        self.speed = 0
        self.heading = 0
        self.lastUpdate = Date()
    }
}

// MARK: - ADS-B Decoder

public class ADSBDecoder {
    private var trackedAircraft: [String: AircraftTrack] = [:]
    private let preamblePattern: [Float] = [1, 0, 1, 0]

    public init() {}

    public func decode(samples: [ComplexFloat]) -> [ADSBSample] {
        let magnitudes = samples.map { sqrt($0.real * $0.real + $0.imag * $0.imag) }
        guard magnitudes.count >= 240 else { return [] }

        let messages = detectPreambles(in: magnitudes)
        var results: [ADSBSample] = []

        for msgBits in messages {
            guard msgBits.count == 112 else { continue }
            let bytes = bitsToBytes(msgBits)
            if let sample = decodeMessage(bytes) {
                results.append(sample)
            }
        }

        return results
    }

    public func decodeMessage(_ message: [UInt8]) -> ADSBSample? {
        guard message.count >= 14 else { return nil }
        guard ModeSCRC.check(message) else { return nil }

        let df = Int((message[0] >> 3) & 0x1F)
        guard df == 17 else { return nil }

        let icao = String(format: "%02X%02X%02X", message[1], message[2], message[3])
        let me = Array(message[4..<11])  // ME field: 7 bytes (message[4] through message[10])
        let tc = Int(me[0] >> 3)

        let track = getOrCreateTrack(icao: icao)

        switch tc {
        case 1...4:
            decodeIdentification(me: me, tc: tc, track: track)
        case 9...18:
            decodeAirbornePosition(me: me, track: track, isGNSS: false)
        case 20...22:
            decodeAirbornePosition(me: me, track: track, isGNSS: true)
        case 19:
            decodeAirborneVelocity(me: me, track: track)
        default:
            break
        }

        track.lastUpdate = Date()

        var lat: Double = 0
        var lon: Double = 0
        if let tLat = track.latitude, let tLon = track.longitude {
            lat = tLat
            lon = tLon
        }

        return ADSBSample(
            icao: icao,
            callsign: track.callsign,
            lat: lat,
            lon: lon,
            alt: track.altitude,
            speed: track.speed,
            heading: track.heading
        )
    }

    // MARK: - Preamble Detection

    private func detectPreambles(in magnitudes: [Float]) -> [[UInt8]] {
        var results: [[UInt8]] = []
        let sampleRate: Float = 2_048_000
        let samplesPerBit = Int(sampleRate / 1_000_000)
        let preambleLen = 8 * samplesPerBit
        let messageSampleLen = 112 * samplesPerBit

        guard magnitudes.count > preambleLen + messageSampleLen else { return results }

        let noiseFloor = computeNoiseFloor(magnitudes)
        let threshold = noiseFloor * 4.0

        var i = 0
        while i < magnitudes.count - preambleLen - messageSampleLen {
            if checkPreamble(in: magnitudes, at: i, threshold: threshold) {
                let startIdx = i + preambleLen
                let bits = extractBits(from: magnitudes, startingAt: startIdx, samplesPerBit: samplesPerBit)
                if bits.count == 112 {
                    results.append(bits)
                }
                i += preambleLen + messageSampleLen
            } else {
                i += samplesPerBit
            }
        }

        return results
    }

    private func checkPreamble(in magnitudes: [Float], at offset: Int, threshold: Float) -> Bool {
        let samplesPerBit = 2
        for k in 0..<4 {
            let pulseIdx = offset + k * 2 * samplesPerBit
            let gapIdx = offset + (k * 2 + 1) * samplesPerBit
            guard pulseIdx + samplesPerBit <= magnitudes.count,
                  gapIdx + samplesPerBit <= magnitudes.count else { return false }

            let pulseLevel = magnitudes[pulseIdx]
            let gapLevel = magnitudes[gapIdx]

            if pulseLevel < threshold || pulseLevel < gapLevel * 2 {
                return false
            }
        }
        return true
    }

    private func extractBits(from magnitudes: [Float], startingAt offset: Int, samplesPerBit: Int) -> [UInt8] {
        var bits: [UInt8] = []
        for bitIdx in 0..<112 {
            let halfBit = samplesPerBit / 2
            let firstHalfStart = offset + bitIdx * samplesPerBit
            let secondHalfStart = firstHalfStart + halfBit

            guard secondHalfStart + halfBit <= magnitudes.count else { break }

            var firstEnergy: Float = 0
            var secondEnergy: Float = 0
            for j in 0..<halfBit {
                firstEnergy += magnitudes[firstHalfStart + j]
                secondEnergy += magnitudes[secondHalfStart + j]
            }

            bits.append(firstEnergy > secondEnergy ? 1 : 0)
        }
        return bits
    }

    private func computeNoiseFloor(_ magnitudes: [Float]) -> Float {
        let count = min(magnitudes.count, 4096)
        var sum: Float = 0
        for i in 0..<count {
            sum += magnitudes[i]
        }
        return sum / Float(count)
    }

    // MARK: - Bit Helpers

    private func bitsToBytes(_ bits: [UInt8]) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: (bits.count + 7) / 8)
        for i in 0..<bits.count {
            if bits[i] != 0 {
                bytes[i / 8] |= UInt8(1 << (7 - (i % 8)))
            }
        }
        return bytes
    }

    // MARK: - Track Management

    private func getOrCreateTrack(icao: String) -> AircraftTrack {
        if let existing = trackedAircraft[icao] {
            return existing
        }
        let track = AircraftTrack(icao: icao)
        trackedAircraft[icao] = track
        return track
    }

    // MARK: - Identification (TC 1-4)

    private let icaoAlphabet: [Character] = [
        "A","B","C","D","E","F","G","H","I","J","K",
        "L","M","N","O","P","Q","R","S","T","U","V",
        "W","X","Y","Z"," "," "," "," "," "," "," ",
        "0","1","2","3","4","5","6","7","8","9"," "
    ]

    private func decodeIdentification(me: [UInt8], tc: Int, track: AircraftTrack) {
        guard me.count >= 7 else { return }

        let data = me[0] & 0x07
        let c1 = Int((data << 3) | (me[1] >> 5))
        let c2 = Int((me[1] & 0x1F) >> 1)
        let c3 = Int(((me[1] & 0x01) << 5) | (me[2] >> 3))
        let c4 = Int((me[2] & 0x07) << 2 | (me[3] >> 6))
        let c5 = Int((me[3] >> 1) & 0x1F)
        let c6 = Int(((me[3] & 0x01) << 4) | (me[4] >> 4))
        let c7 = Int((me[4] & 0x0F) << 1 | (me[5] >> 7))
        let c8 = Int((me[5] >> 2) & 0x1F)

        let indices = [c1, c2, c3, c4, c5, c6, c7, c8]
        var callsign = ""
        for idx in indices {
            if idx >= 0 && idx < icaoAlphabet.count {
                let ch = icaoAlphabet[idx]
                if ch != " " {
                    callsign.append(ch)
                }
            }
        }

        if !callsign.isEmpty {
            track.callsign = callsign
        }

        switch tc {
        case 1: break
        case 2: break
        case 3: break
        case 4: break
        default: break
        }
    }

    // MARK: - Airborne Position (TC 9-18, 20-22)

    private func decodeAirbornePosition(me: [UInt8], track: AircraftTrack, isGNSS: Bool) {
        guard me.count >= 8 else { return }

        let _ = Int(me[0] >> 3)
        let ss = Int(me[0] & 0x07)
        let altBits = Int(me[1] & 0x07) << 15 | Int(me[2]) << 7 | Int(me[3] >> 1)

        let alt = decodeAltitude(bits: altBits, isGNSS: isGNSS)
        if alt > 0 {
            track.altitude = alt
        }

        let f = Int(me[4] >> 7)

        let latCpr = Int((me[4] & 0x7F)) << 9 | Int(me[5]) << 1 | Int(me[6] >> 7)
        let lonCpr = Int((me[6] & 0x7F)) << 8 | Int(me[7])

        if f == 0 {
            track.cprLatEven = latCpr
            track.cprLonEven = lonCpr
            track.cprEvenTime = Date()
            track.cprEvenUTC = ss
        } else {
            track.cprLatOdd = latCpr
            track.cprLonOdd = lonCpr
            track.cprOddTime = Date()
        }

        tryDecodeCPR(track: track)
    }

    private func decodeAltitude(bits: Int, isGNSS: Bool) -> Int {
        let q = (bits >> 4) & 1

        if !isGNSS && q == 1 {
            let n = bits & 0x7FF
            return n * 25 - 1000
        }

        if !isGNSS && q == 0 {
            let mBit = (bits >> 8) & 0x0F
            let dBit = bits & 0xFF
            let d100 = grayDecode(dBit & 0x7F)
            let m500 = grayDecode(mBit)

            if d100 & 1 != 0 {
                return m500 * 500 + (d100 - 1) * 100 + 200
            } else {
                return m500 * 500 + d100 * 100
            }
        }

        if isGNSS {
            let n = bits & 0x1FFF
            return n * 100
        }

        return 0
    }

    private func grayDecode(_ value: Int) -> Int {
        var n = value
        var mask = n >> 1
        while mask != 0 {
            n ^= mask
            mask >>= 1
        }
        return n
    }

    // MARK: - CPR Position Decoding

    private func tryDecodeCPR(track: AircraftTrack) {
        guard let latEven = track.cprLatEven,
              let lonEven = track.cprLonEven,
              let latOdd = track.cprLatOdd,
              let lonOdd = track.cprLonOdd,
              let evenTime = track.cprEvenTime,
              let oddTime = track.cprOddTime else { return }

        let timeDiff = abs(evenTime.timeIntervalSince(oddTime))
        guard timeDiff < 10.0 else { return }

        let isEvenNewer = evenTime > oddTime

        guard let lat = CPRDecoder.decodeLatitude(
            latCprEven: latEven,
            latCprOdd: latOdd,
            isEvenNewer: isEvenNewer
        ) else { return }

        if CPRDecoder.NL(latitude: lat) < 1 && !isEvenNewer { return }

        let lon = CPRDecoder.decodeLongitude(
            lat: lat,
            lonCprEven: lonEven,
            lonCprOdd: lonOdd,
            isEvenNewer: isEvenNewer
        )

        track.latitude = lat
        track.longitude = lon
    }

    // MARK: - Airborne Velocity (TC 19)

    private func decodeAirborneVelocity(me: [UInt8], track: AircraftTrack) {
        guard me.count >= 7 else { return }

        let subtype = Int(me[0] & 0x07)

        if subtype == 1 || subtype == 2 {
            let ewSign = Int((me[1] >> 4) & 1)
            let ewRaw = Int(me[1] & 0x0F) << 5 | Int(me[2] >> 3)
            let ewV = ewSign == 1 ? ewRaw - 1 : ewRaw

            let nsSign = Int((me[2] >> 2) & 1)
            let nsRaw = Int((me[2] & 0x03)) << 6 | Int(me[3] >> 2)
            let nsV = nsSign == 1 ? nsRaw - 1 : nsRaw

            let speed = Int(sqrt(Double(ewV * ewV + nsV * nsV)))
            let heading = atan2(Double(ewV), Double(nsV)) * 180.0 / .pi
            let normalizedHeading = heading < 0 ? heading + 360.0 : heading

            track.speed = speed
            track.heading = normalizedHeading

            let vrSign = Int((me[4] >> 2) & 1)
            let vrRaw = Int((me[4] & 0x03)) << 4 | Int(me[5] >> 4)
            if vrRaw != 0 {
                let vr = vrSign == 1 ? (vrRaw - 1) * 64 : (1 - vrRaw) * 64
                _ = vr
            }
        } else if subtype == 3 {
            let headingValid = Int((me[1] >> 2) & 1)
            let headingRaw = Int((me[1] & 0x03)) << 5 | Int(me[2] >> 3)
            if headingValid == 1 && headingRaw != 0 {
                track.heading = Double(headingRaw) * 360.0 / 256.0
            }

            let airspeedSign = Int(me[3] & 1)
            let airspeedRaw = Int(me[4] >> 3)
            if airspeedRaw != 0 {
                track.speed = airspeedSign == 1 ? airspeedRaw - 1 : airspeedRaw
            }

            let vrSign = Int((me[4] >> 2) & 1)
            let vrRaw = Int((me[4] & 0x03)) << 4 | Int(me[5] >> 4)
            if vrRaw != 0 {
                let vr = vrSign == 1 ? (vrRaw - 1) * 64 : (1 - vrRaw) * 64
                _ = vr
            }
        }
    }

    // MARK: - Access

    public func getTrackedAircraft() -> [String: AircraftTrack] {
        return trackedAircraft
    }

    public func removeStaleAircraft(maxAge: TimeInterval = 60.0) {
        let now = Date()
        for (icao, track) in trackedAircraft {
            if now.timeIntervalSince(track.lastUpdate) > maxAge {
                trackedAircraft.removeValue(forKey: icao)
            }
        }
    }
}
