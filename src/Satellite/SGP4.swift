//
//  SGP4.swift
//  NeuralSDR2
//
//  SGP4-lite Satellite Orbit Propagation
//  Simplified General Perturbations satellite orbit model
//  Implements J2 secular perturbations, Kepler's equation, TEME output
//

import Foundation
import simd

public struct TLE {
    public var name: String
    public var line1: String
    public var line2: String

    public var satelliteNumber: Int
    public var classification: Character
    public var launchYear: Int
    public var launchNumber: Int
    public var epochYear: Int
    public var epochDay: Double
    public var meanMotion: Double
    public var inclination: Double
    public var raan: Double
    public var eccentricity: Double
    public var argPerigee: Double
    public var meanAnomaly: Double
    public var bstar: Double

    public init(name: String, line1: String, line2: String) {
        self.name = name
        self.line1 = line1
        self.line2 = line2

        // Normalize lines to exactly 69 chars (standard TLE format)
        // TLEs from different sources may have variant spacing;
        // normalization by whitespace-separated fields ensures robust parsing.
        let l1 = TLE.normalizeTLELine(line1)
        let l2 = TLE.normalizeTLELine(line2)

        // Line 1 fields (0-indexed column positions per CelesTrak TLE format):
        self.satelliteNumber = Int(TLE.substring(l1, from: 2, length: 5).trimmingCharacters(in: .whitespaces)) ?? 0
        let classIdx = l1.index(l1.startIndex, offsetBy: 7)
        self.classification = l1[classIdx].unicodeScalars.first.map { Character($0) } ?? "U"
        self.launchYear = Int(TLE.substring(l1, from: 9, length: 2).trimmingCharacters(in: .whitespaces)) ?? 0
        self.launchNumber = Int(TLE.substring(l1, from: 11, length: 3).trimmingCharacters(in: .whitespaces)) ?? 0
        self.epochYear = Int(TLE.substring(l1, from: 18, length: 2).trimmingCharacters(in: .whitespaces)) ?? 0
        self.epochDay = Double(TLE.substring(l1, from: 20, length: 12).trimmingCharacters(in: .whitespaces)) ?? 0.0
        // B* at columns 54-61 (1-indexed) = [53:61] (0-indexed), 8 chars
        self.bstar = TLE.parseDoubleWithExponent(TLE.substring(l1, from: 53, length: 8).trimmingCharacters(in: .whitespaces)) * 1e-5

        // Line 2 fields (0-indexed column positions per CelesTrak TLE format):
        self.inclination = Double(TLE.substring(l2, from: 8, length: 8).trimmingCharacters(in: .whitespaces)) ?? 0.0
        // RAAN at columns 18-25 (1-indexed) = [17:25] (0-indexed), 8 chars
        self.raan = Double(TLE.substring(l2, from: 17, length: 8).trimmingCharacters(in: .whitespaces)) ?? 0.0
        self.eccentricity = Double("0." + TLE.substring(l2, from: 26, length: 7).trimmingCharacters(in: .whitespaces)) ?? 0.0
        self.argPerigee = Double(TLE.substring(l2, from: 34, length: 8).trimmingCharacters(in: .whitespaces)) ?? 0.0
        self.meanAnomaly = Double(TLE.substring(l2, from: 43, length: 8).trimmingCharacters(in: .whitespaces)) ?? 0.0
        // Mean motion at columns 53-64 (1-indexed) = [52:64] (0-indexed), 12 chars
        self.meanMotion = Double(TLE.substring(l2, from: 52, length: 12).trimmingCharacters(in: .whitespaces)) ?? 0.0
    }

        /// Normalize a TLE line to exactly 69 characters by reformatting
    /// whitespace-separated fields into their standard column positions.
    /// This handles TLEs from different sources that may have variant spacing.
    private static func normalizeTLELine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return trimmed }

        let lineNum = trimmed.first ?? "1"

        // Split by whitespace, filtering empties
        let fields = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count >= 2 else { return trimmed }

        if lineNum == "1" {
            return normalizeLine1(fields: fields)
        } else {
            return normalizeLine2(fields: fields)
        }
    }

    /// Normalize TLE Line 1 to 69 chars.
    /// Expected fields (split by whitespace): line#, sat#+class, designator, epoch, 1st deriv, 2nd deriv, B*, ephemeris, elem#, checksum
    /// But the actual split depends on the source formatting.
    private static func normalizeLine1(fields: [String]) -> String {
        var buf = [Character](repeating: " ", count: 69)
        buf[0] = "1"

        // Field 0: "1" (line number) — already set
        // Field 1: "25544U" = satellite number + classification
        if fields.count > 1 {
            let satClass = fields[1]
            let satNum = String(satClass.prefix(5))
            let cls = satClass.count > 5 ? satClass[satClass.index(satClass.startIndex, offsetBy: 5)] : "U"
            for (i, c) in satNum.enumerated() { if 2+i < 69 { buf[2+i] = c } }
            buf[7] = cls
        }

        // Field 2: "98067A" = international designator
        if fields.count > 2 {
            let desig = fields[2]
            for (i, c) in desig.enumerated() { if 9+i < 69 { buf[9+i] = c } }
        }

        // Field 3: "24001.50000000" = epoch year + day
        if fields.count > 3 {
            let epoch = fields[3]
            if epoch.count >= 2 {
                let epochYear = epoch.prefix(2)
                for (i, c) in epochYear.enumerated() { if 18+i < 69 { buf[18+i] = c } }
            }
            if epoch.count > 2 {
                let epochDay = epoch.dropFirst(2)
                for (i, c) in epochDay.enumerated() { if 20+i < 69 { buf[20+i] = c } }
            }
        }

        // Field 4: ".00016717" or "0.00016717" = 1st derivative of mean motion (10 chars at [33:43])
        if fields.count > 4 {
            let deriv1 = fields[4]
            // Right-justify in 10-char field
            let padded = String(deriv1.reversed()).padding(toLength: 10, withPad: " ", startingAt: 0)
            let rightJustified = String(padded.reversed())
            for (i, c) in rightJustified.enumerated() { if 33+i < 69 { buf[33+i] = c } }
        }

        // Field 5: "00000-0" = 2nd derivative (8 chars at [44:52])
        if fields.count > 5 {
            let deriv2 = fields[5]
            let padded = String(deriv2.reversed()).padding(toLength: 8, withPad: " ", startingAt: 0)
            let rightJustified = String(padded.reversed())
            for (i, c) in rightJustified.enumerated() { if 44+i < 69 { buf[44+i] = c } }
        }

        // Field 6: "30200-3" = B* (8 chars at [53:61])
        if fields.count > 6 {
            let bstar = fields[6]
            let padded = String(bstar.reversed()).padding(toLength: 8, withPad: " ", startingAt: 0)
            let rightJustified = String(padded.reversed())
            for (i, c) in rightJustified.enumerated() { if 53+i < 69 { buf[53+i] = c } }
        }

        // Field 7: "0" = ephemeris type (1 char at [62])
        if fields.count > 7 {
            let eph = fields[7]
            if let c = eph.first { buf[62] = c }
        }

        // Field 8: "9993" or similar = element number (4 chars at [64:68])
        if fields.count > 8 {
            let elem = fields[8]
            let padded = String(elem.reversed()).padding(toLength: 4, withPad: " ", startingAt: 0)
            let rightJustified = String(padded.reversed())
            for (i, c) in rightJustified.enumerated() { if 64+i < 69 { buf[64+i] = c } }
        }

        // Field 9: checksum (1 char at [68])
        if fields.count > 9 {
            if let c = fields[9].first { buf[68] = c }
        }

        return String(buf)
    }

    /// Normalize TLE Line 2 to 69 chars.
    /// Expected fields: line#, sat#, inclination, RAAN, eccentricity, argPerigee, meanAnomaly, meanMotion, revNumber, checksum
    private static func normalizeLine2(fields: [String]) -> String {
        var buf = [Character](repeating: " ", count: 69)
        buf[0] = "2"

        // Field 0: "2" (line number) — already set
        // Field 1: "25544" = satellite number
        if fields.count > 1 {
            let satNum = fields[1]
            let padded = String(satNum.reversed()).padding(toLength: 5, withPad: " ", startingAt: 0)
            let rightJustified = String(padded.reversed())
            for (i, c) in rightJustified.enumerated() { if 2+i < 69 { buf[2+i] = c } }
        }

        // Field 2: "51.6416" = inclination (8 chars at [8:16])
        if fields.count > 2 {
            let incl = fields[2]
            let padded = String(incl.reversed()).padding(toLength: 8, withPad: " ", startingAt: 0)
            let rightJustified = String(padded.reversed())
            for (i, c) in rightJustified.enumerated() { if 8+i < 69 { buf[8+i] = c } }
        }

        // Field 3: "247.4627" = RAAN (8 chars at [17:25])
        if fields.count > 3 {
            let raan = fields[3]
            let padded = String(raan.reversed()).padding(toLength: 8, withPad: " ", startingAt: 0)
            let rightJustified = String(padded.reversed())
            for (i, c) in rightJustified.enumerated() { if 17+i < 69 { buf[17+i] = c } }
        }

        // Field 4: "0006703" = eccentricity (7 chars at [26:33])
        if fields.count > 4 {
            let ecc = fields[4]
            let padded = String(ecc.reversed()).padding(toLength: 7, withPad: " ", startingAt: 0)
            let leftJustified = String(padded.reversed())
            for (i, c) in leftJustified.enumerated() { if 26+i < 69 { buf[26+i] = c } }
        }

        // Field 5: "130.5360" = argument of perigee (8 chars at [34:42])
        if fields.count > 5 {
            let argp = fields[5]
            let padded = String(argp.reversed()).padding(toLength: 8, withPad: " ", startingAt: 0)
            let rightJustified = String(padded.reversed())
            for (i, c) in rightJustified.enumerated() { if 34+i < 69 { buf[34+i] = c } }
        }

        // Field 6: "325.0288" = mean anomaly (8 chars at [43:51])
        if fields.count > 6 {
            let ma = fields[6]
            let padded = String(ma.reversed()).padding(toLength: 8, withPad: " ", startingAt: 0)
            let rightJustified = String(padded.reversed())
            for (i, c) in rightJustified.enumerated() { if 43+i < 69 { buf[43+i] = c } }
        }

        // Field 7: "15.49560572424919" = mean motion (12 chars at [52:64])
        if fields.count > 7 {
            let mm = fields[7]
            // Take first 12 chars if longer, pad right if shorter
            let truncated = mm.count > 12 ? String(mm.prefix(12)) : mm.padding(toLength: 12, withPad: " ", startingAt: 0)
            for (i, c) in truncated.enumerated() { if 52+i < 69 { buf[52+i] = c } }
        }

        // Field 8: "4919" = revolution number (4 chars at [64:68])
        if fields.count > 8 {
            let rev = fields[8]
            let padded = String(rev.reversed()).padding(toLength: 4, withPad: " ", startingAt: 0)
            let rightJustified = String(padded.reversed())
            for (i, c) in rightJustified.enumerated() { if 64+i < 69 { buf[64+i] = c } }
        }

        // Field 9: checksum (1 char at [68])
        if fields.count > 9 {
            if let c = fields[9].first { buf[68] = c }
        }

        return String(buf)
    }

    private static func substring(_ s: String, from: Int, length: Int) -> String {
        let start = s.index(s.startIndex, offsetBy: from, limitedBy: s.endIndex) ?? s.endIndex
        let end = s.index(start, offsetBy: length, limitedBy: s.endIndex) ?? s.endIndex
        return String(s[start..<end])
    }

    private static func parseDoubleWithExponent(_ s: String) -> Double {
        var str = s.trimmingCharacters(in: .whitespaces)
        if str.isEmpty { return 0.0 }

        let digits = CharacterSet.decimalDigits
        let first = str[str.startIndex]
        if first == "-" || first == "+" || digits.contains(first.unicodeScalars.first!) {
            if let signIdx = str.firstIndex(where: { $0 == "-" || $0 == "+" }), signIdx != str.startIndex {
                str.insert("E", at: signIdx)
            }
        }
        return Double(str) ?? 0.0
    }
}

public struct SatellitePosition {
    public var position: SIMD3<Double>
    public var velocity: SIMD3<Double>
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double
    public var range: Double
    public var rangeRate: Double
    public var elevation: Double
    public var azimuth: Double
    public var rightAscension: Double
    public var declination: Double
}

public struct OrbitalElements {
    public var semiMajorAxis: Double
    public var eccentricity: Double
    public var inclination: Double
    public var raan: Double
    public var argPerigee: Double
    public var meanAnomaly: Double
    public var meanMotion: Double
    public var bstar: Double
}

public struct LookAngle {
    public var azimuth: Double
    public var elevation: Double
    public var range: Double
    public var rangeRate: Double
}

public class SGP4Propagator {
    public var tle: TLE

    private let re = 6378.137
    private let muS = 398600.8          // km^3/s^2
    private var mu: Double = 0          // km^3/min^2 (set in initialize)
    private let j2 = 1.082616e-3
    private let j3 = -2.53881e-6
    private let j4 = -1.65597e-6
    private let omegaEarth = 7.2921151467e-5
    private let pi = Double.pi
    private let twopi = 2.0 * Double.pi
    private let deg2rad = Double.pi / 180.0
    private let rad2deg = 180.0 / Double.pi

    private var epoch: Date
    private var initialized = false

    private var a0: Double = 0
    private var n0: Double = 0
    private var n0dp: Double = 0
    private var n0pp: Double = 0
    private var cosi0: Double = 0
    private var sini0: Double = 0
    private var raan0: Double = 0
    private var argp0: Double = 0
    private var m0: Double = 0
    private var ecc0: Double = 0
    private var incl0: Double = 0
    private var bstar: Double = 0
    private var raandot: Double = 0
    private var argpdot: Double = 0
    private var a1: Double = 0
    private var delO: Double = 0
    private var a0dp: Double = 0
    private var p0: Double = 0
    private var q0: Double = 0
    private var s0: Double = 0

    public init(tle: TLE) {
        self.tle = tle
        self.epoch = Self.computeEpochDate(epochYear: tle.epochYear, epochDay: tle.epochDay)
        initialize()
    }

    public func updateTLE(_ newTLE: TLE) {
        self.tle = newTLE
        self.epoch = Self.computeEpochDate(epochYear: newTLE.epochYear, epochDay: newTLE.epochDay)
        initialize()
    }

    private static func computeEpochDate(epochYear: Int, epochDay: Double) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let fullYear: Int
        if epochYear < 57 {
            fullYear = 2000 + epochYear
        } else {
            fullYear = 1900 + epochYear
        }

        var comps = DateComponents()
        comps.year = fullYear
        comps.month = 1
        comps.day = 1
        comps.hour = 0
        comps.minute = 0
        comps.second = 0

        guard let jan1 = calendar.date(from: comps) else { return Date() }
        let dayFraction = epochDay - 1.0
        let secondsInDay = dayFraction * 86400.0
        return jan1.addingTimeInterval(secondsInDay)
    }

    private func initialize() {
        // SGP4 uses angular velocities in rad/min and mu in km^3/min^2
        // TLE mean motion is in rev/day
        mu = muS * 3600.0  // Convert mu from km^3/s^2 to km^3/min^2
        let noKozai = tle.meanMotion * twopi / 1440.0  // rad/min

        let inclRad = tle.inclination * deg2rad
        incl0 = inclRad
        raan0 = tle.raan * deg2rad
        argp0 = tle.argPerigee * deg2rad
        m0 = tle.meanAnomaly * deg2rad
        ecc0 = tle.eccentricity
        bstar = tle.bstar

        cosi0 = cos(incl0)
        sini0 = sin(incl0)

        let a1tmp = pow(mu / (noKozai * noKozai), 1.0 / 3.0)
        let theta2 = cosi0 * cosi0
        let x3thm1 = 3.0 * theta2 - 1.0

        let delta1 = (3.0 / 4.0) * (j2 / a1tmp * a1tmp) * x3thm1 / (1.0 - ecc0 * ecc0)
        let delta0 = delta1 * (1.0 / a1tmp)

        a0dp = a1tmp * (1.0 - (1.0 / 3.0) * delta0 - delta0 * delta0 - (134.0 / 81.0) * delta0 * delta0 * delta0)
        delO = (3.0 / 4.0) * (j2 / (a0dp * a0dp)) * x3thm1 / (1.0 - ecc0 * ecc0)

        n0dp = noKozai / (1.0 + delO)
        n0pp = n0dp

        a0 = pow(mu / (n0dp * n0dp), 1.0 / 3.0)
        n0 = n0dp

        s0 = (1.0 + (3.0 / 2.0) * j2 / (a0 * a0) * x3thm1 / (1.0 - ecc0 * ecc0))
        p0 = a0 * (1.0 - ecc0 * ecc0) * s0
        q0 = a0 * (1.0 - ecc0 * ecc0) * s0

        let perigee = a0 * (1.0 - ecc0) - re
        if perigee < 156.0 {
            let s4 = perigee < 98.0 ? re + 78.0 : re + perigee
            let q0ms4 = q0 - s4
            let pinv = 1.0 / (a0 * (1.0 - ecc0 * ecc0))
            let pinvsq = pinv * pinv
            let tsi = 1.0 / (a0 - s4)
            let etasq = ecc0 * ecc0 * pinvsq
            let eta = sqrt(etasq)
            let coef = q0ms4 * tsi
            let coef1 = coef * coef

            let _ = -j3 / j2
            let e3 = ecc0 * ecc0 * ecc0
            let psisq = (1.0 - ecc0 * ecc0) * (1.0 - ecc0 * ecc0)
            let omegaCoef = q0ms4 * tsi / psisq

            let C1 = bstar * coef * tsi * (3.0 * (1.0 + (3.0 / 2.0) * etasq + e3 * (1.0 + etasq * ecc0)) + (3.0 / 4.0) * coef1 * (1.0 + 1.5 * etasq + e3 * (1.0 + 3.0 * etasq * ecc0)) / 8.0)
            let C2 = coef1 * tsi * (1.0 + 1.5 * etasq + e3 * (1.0 + 3.0 * etasq * ecc0))
            let _ = coef * tsi * bstar / (eta * eta)

            let _ = 2.0 * n0dp * q0ms4 * tsi / re
            let _ = eta * (2.0 + 0.5 * etasq)

            let D2 = 4.0 * a0 * tsi * C1 * C1
            let D3 = D2 * (4.0 / 3.0) * a0 * tsi * (17.0 * C1 + 2.0 * C2)
            let D4 = D2 * D2 * (2.0 / 3.0) * a0 * tsi * (221.0 * C1 + 31.0 * C2)

            let mdot = n0dp + (1.0 / 3.0) * n0dp * D2 + (2.0 / 3.0) * n0dp * D2 * D2 + (1.0 / 4.0) * n0dp * D3 + (1.0 / 5.0) * n0dp * D4
            let argpdotLoc = (-0.5 * j2 / (a0 * a0) * x3thm1 / (1.0 - ecc0 * ecc0) + omegaCoef * (1.0 + 3.0 / 4.0 * (1.0 - theta2)) * (1.0 + 3.0 / 4.0 * (1.0 - theta2)) * 3.0 / 2.0 * j2 / (a0 * a0) / (1.0 - ecc0 * ecc0)) * n0dp
            let raandotLoc = -1.5 * j2 / (a0 * a0) * cosi0 / (1.0 - ecc0 * ecc0) * n0dp

            argpdot = argpdotLoc
            raandot = raandotLoc
            a1 = mdot
        } else {
            raandot = -1.5 * (j2 / (a0 * a0)) * cosi0 / (1.0 - ecc0 * ecc0) * n0dp
            argpdot = 0.75 * (j2 / (a0 * a0)) * (1.0 - 5.0 * theta2) / (1.0 - ecc0 * ecc0) * n0dp
            a1 = n0dp
        }

        initialized = true
    }

    public func getPosition(at date: Date, observerLat: Double = 0, observerLon: Double = 0) -> SatellitePosition {
        let timeSinceEpoch = date.timeIntervalSince(epoch) / 60.0  // minutes from epoch

        let result = propagate(tsince: timeSinceEpoch)

        let latLonAlt = positionToLatLonAlt(position: result.position, date: date)

        let lookAngle = calculateLookAngles(
            satellitePos: result.position,
            satelliteVel: result.velocity,
            observerLat: observerLat,
            observerLon: observerLon,
            date: date
        )

        let ra = atan2(result.position.y, result.position.x) * rad2deg
        let dec = atan2(result.position.z, sqrt(result.position.x * result.position.x + result.position.y * result.position.y)) * rad2deg

        return SatellitePosition(
            position: result.position,
            velocity: result.velocity,
            latitude: latLonAlt.0,
            longitude: latLonAlt.1,
            altitude: latLonAlt.2,
            range: lookAngle.range,
            rangeRate: lookAngle.rangeRate,
            elevation: lookAngle.elevation,
            azimuth: lookAngle.azimuth,
            rightAscension: ra,
            declination: dec
        )
    }

    private func propagate(tsince: Double) -> (position: SIMD3<Double>, velocity: SIMD3<Double>) {
        let em = ecc0
        let cosi = cosi0
        let sini = sini0

        let omega = argp0 + argpdot * tsince
        let nodep = raan0 + raandot * tsince
        let mp = m0 + n0dp * tsince

        let axnl = em * cos(omega)
        let aynl = em * sin(omega)

        let u = mp + omega

        let eccSq = axnl * axnl + aynl * aynl
        let pl = a0 * (1.0 - eccSq)

        let capu = u - nodep - axnl

        var eAnom = capu
        for _ in 0..<20 {
            let sinePW = sin(eAnom)
            let cosePW = cos(eAnom)
            let ecose = axnl * cosePW + aynl * sinePW
            let esine = axnl * sinePW - aynl * cosePW
            let denom = 1.0 - ecose / a0
            if abs(denom) < 1e-20 { break }
            let delE = (capu - eAnom + esine) / denom
            eAnom += delE
            if abs(delE) < 1e-12 { break }
        }

        let sinePW = sin(eAnom)
        let cosePW = cos(eAnom)
        let ecose = axnl * cosePW + aynl * sinePW
        let esine = axnl * sinePW - aynl * cosePW

        let uPqw = eAnom + esine

        let suPqw = sin(uPqw)
        let cuPqw = cos(uPqw)

        let rk = pl / (1.0 + ecose)

        let xUK = rk * cuPqw
        let yUK = rk * suPqw

        let sinNode = sin(nodep)
        let cosNode = cos(nodep)

        let xGK = xUK * cosNode - yUK * sinNode * cosi
        let yGK = xUK * sinNode + yUK * cosNode * cosi
        let zGK = yUK * sini

        let pos = SIMD3<Double>(xGK, yGK, zGK)

        let rdot = sqrt(mu / pl) * esine
        let rfdot = sqrt(mu / pl) * (1.0 + ecose)

        let vxPqw = rdot * cuPqw - rfdot * suPqw
        let vyPqw = rdot * suPqw + rfdot * cuPqw

        let vxGK = vxPqw * cosNode - vyPqw * sinNode * cosi
        let vyGK = vxPqw * sinNode + vyPqw * cosNode * cosi
        let vzGK = vyPqw * sini

        // Convert velocity from km/min to km/s
        let vel = SIMD3<Double>(vxGK / 60.0, vyGK / 60.0, vzGK / 60.0)

        return (pos, vel)
    }

    private func positionToLatLonAlt(position: SIMD3<Double>, date: Date) -> (Double, Double, Double) {
        let r = sqrt(position.x * position.x + position.y * position.y + position.z * position.z)
        let lat = asin(position.z / r) * rad2deg
        let lon = atan2(position.y, position.x) * rad2deg

        let sinLat = sin(lat * deg2rad)
        let rlat = re * (1.0 - 0.00335281) / sqrt(1.0 - 0.006694372 * sinLat * sinLat)
        let alt = r > rlat ? r - rlat : r - re

        return (lat, lon, alt)
    }

    private func calculateLookAngles(
        satellitePos: SIMD3<Double>,
        satelliteVel: SIMD3<Double>,
        observerLat: Double,
        observerLon: Double,
        date: Date
    ) -> LookAngle {
        let thetaDeg = greenwichSiderealTime(date: date)
        let thetaRad = (thetaDeg + observerLon) * deg2rad
        let latRad = observerLat * deg2rad

        let sinLat = sin(latRad)
        let cosLat = cos(latRad)
        let sinTheta = sin(thetaRad)
        let cosTheta = cos(thetaRad)

        let xObs = re * cosLat * cosTheta
        let yObs = re * cosLat * sinTheta
        let zObs = re * sinLat

        let rx = satellitePos.x - xObs
        let ry = satellitePos.y - yObs
        let rz = satellitePos.z - zObs

        let rangeVal = sqrt(rx * rx + ry * ry + rz * rz)

        let ecefX = satellitePos.x * cosTheta + satellitePos.y * sinTheta
        let ecefY = -satellitePos.x * sinTheta + satellitePos.y * cosTheta
        let ecefZ = satellitePos.z

        let ecefObsX = re * cosLat
        let ecefObsY = 0.0
        let ecefObsZ = re * sinLat

        let dx = ecefX - ecefObsX
        let dy = ecefY - ecefObsY
        let dz = ecefZ - ecefObsZ

        let east = -sinTheta * dx + cosTheta * dy
        let north = -sinLat * cosTheta * dx - sinLat * sinTheta * dy + cosLat * dz
        let up = cosLat * cosTheta * dx + cosLat * sinTheta * dy + sinLat * dz

        let az = atan2(east, north) * rad2deg
        let azNorm = az < 0 ? az + 360.0 : az
        let el = atan2(up, sqrt(east * east + north * north)) * rad2deg

        let vxEcef = satelliteVel.x * cosTheta + satelliteVel.y * sinTheta + omegaEarth * satellitePos.y
        let vyEcef = -satelliteVel.x * sinTheta + satelliteVel.y * cosTheta - omegaEarth * satellitePos.x
        let vzEcef = satelliteVel.z

        let rxEcef = rangeVal > 0.001 ? dx / rangeVal : 0
        let ryEcef = rangeVal > 0.001 ? dy / rangeVal : 0
        let rzEcef = rangeVal > 0.001 ? dz / rangeVal : 0

        let rangeRate = vxEcef * rxEcef + vyEcef * ryEcef + vzEcef * rzEcef

        return LookAngle(
            azimuth: azNorm,
            elevation: el,
            range: rangeVal,
            rangeRate: rangeRate
        )
    }

    public func greenwichSiderealTime(date: Date) -> Double {
        let j2000 = Date(timeIntervalSince1970: 978307200.0)
        let daysSinceJ2000 = date.timeIntervalSince(j2000) / 86400.0

        let t = daysSinceJ2000 / 36525.0
        var theta = 280.46061837 + 360.98564736629 * daysSinceJ2000
            + 0.000387933 * t * t
            - t * t * t / 38710000.0

        theta = theta.truncatingRemainder(dividingBy: 360.0)
        if theta < 0 { theta += 360.0 }
        return theta
    }

    public func getOrbitalElements() -> OrbitalElements {
        // n0dp is in rad/min; convert to rev/day for output
        let meanMotionRevPerDay = n0dp / twopi * 1440.0
        return OrbitalElements(
            semiMajorAxis: a0,
            eccentricity: ecc0,
            inclination: incl0 * rad2deg,
            raan: raan0 * rad2deg,
            argPerigee: argp0 * rad2deg,
            meanAnomaly: m0 * rad2deg,
            meanMotion: meanMotionRevPerDay,
            bstar: bstar
        )
    }
}

public struct SatellitePass {
    public var satellite: String
    public var aos: Date
    public var los: Date
    public var tca: Date
    public var maxElevation: Double
    public var maxElevationTime: Date
    public var visible: Bool
    public var duration: TimeInterval
}

public class PassPredictor {
    private var propagator: SGP4Propagator
    private var observerLat: Double
    private var observerLon: Double
    private var observerAlt: Double

    public init(propagator: SGP4Propagator, latitude: Double, longitude: Double, altitude: Double = 0) {
        self.propagator = propagator
        self.observerLat = latitude
        self.observerLon = longitude
        self.observerAlt = altitude
    }

    public func findNextPass(from date: Date = Date(), maxDays: Int = 3) -> SatellitePass? {
        let coarseStep: TimeInterval = 30
        let fineStep: TimeInterval = 1.0
        let endTime = date.addingTimeInterval(Double(maxDays) * 86400.0)

        var currentTime = date
        var prevElev: Double? = nil
        var inView = false
        var aos: Date? = nil
        var maxElev: Double = 0
        var maxElevTime: Date? = nil

        while currentTime < endTime {
            let pos = propagator.getPosition(at: currentTime, observerLat: observerLat, observerLon: observerLon)
            let elev = pos.elevation

            if elev > 0 {
                if !inView {
                    if let pElev = prevElev, pElev <= 0 {
                        var loTime = currentTime.addingTimeInterval(-coarseStep)
                        var hiTime = currentTime
                        for _ in 0..<20 {
                            let midTime = loTime.addingTimeInterval(hiTime.timeIntervalSince(loTime) / 2.0)
                            let midPos = propagator.getPosition(at: midTime, observerLat: observerLat, observerLon: observerLon)
                            if midPos.elevation > 0 {
                                hiTime = midTime
                            } else {
                                loTime = midTime
                            }
                        }
                        aos = hiTime
                    } else {
                        aos = currentTime
                    }
                    inView = true
                    maxElev = elev
                    maxElevTime = currentTime
                } else {
                    if elev > maxElev {
                        maxElev = elev
                        maxElevTime = currentTime
                    }
                }
            } else if inView {
                var loTime = currentTime.addingTimeInterval(-coarseStep)
                var hiTime = currentTime
                for _ in 0..<20 {
                    let midTime = loTime.addingTimeInterval(hiTime.timeIntervalSince(loTime) / 2.0)
                    let midPos = propagator.getPosition(at: midTime, observerLat: observerLat, observerLon: observerLon)
                    if midPos.elevation > 0 {
                        loTime = midTime
                    } else {
                        hiTime = midTime
                    }
                }
                let losTime = loTime

                if let aosTime = aos, var mElevTime = maxElevTime {
                    var searchStart = aosTime
                    var searchEnd = losTime
                    for _ in 0..<30 {
                        let midTime = searchStart.addingTimeInterval(searchEnd.timeIntervalSince(searchStart) / 2.0)
                        let midPos = propagator.getPosition(at: midTime, observerLat: observerLat, observerLon: observerLon)
                        let prevPos = propagator.getPosition(at: midTime.addingTimeInterval(-fineStep), observerLat: observerLat, observerLon: observerLon)
                        if midPos.elevation > prevPos.elevation {
                            searchStart = midTime
                        } else {
                            searchEnd = midTime
                        }
                    }
                    mElevTime = searchStart
                    let mPos = propagator.getPosition(at: mElevTime, observerLat: observerLat, observerLon: observerLon)
                    maxElev = mPos.elevation

                    return SatellitePass(
                        satellite: propagator.tle.name,
                        aos: aosTime,
                        los: losTime,
                        tca: mElevTime,
                        maxElevation: maxElev,
                        maxElevationTime: mElevTime,
                        visible: true,
                        duration: losTime.timeIntervalSince(aosTime)
                    )
                }
                inView = false
                aos = nil
                maxElev = 0
                maxElevTime = nil
            }

            prevElev = elev
            currentTime = currentTime.addingTimeInterval(coarseStep)
        }

        return nil
    }

    public func findPasses(days: Int = 3) -> [SatellitePass] {
        var passes: [SatellitePass] = []
        var currentDate = Date()

        let maxSearchDays = days
        var safetyCount = 0
        while safetyCount < 50 {
            guard let pass = findNextPass(from: currentDate, maxDays: maxSearchDays) else { break }
            passes.append(pass)
            currentDate = pass.los.addingTimeInterval(60)
            safetyCount += 1

            if currentDate > Date().addingTimeInterval(Double(days) * 86400.0) { break }
        }

        return passes
    }
}

public class TLEManager {
    private var tles: [String: TLE] = [:]

    public func addTLE(name: String, line1: String, line2: String) {
        let tle = TLE(name: name, line1: line1, line2: line2)
        tles[name] = tle
    }

    public func getTLE(name: String) -> TLE? {
        return tles[name]
    }

    public func removeTLE(name: String) {
        tles.removeValue(forKey: name)
    }

    public func getTLENames() -> [String] {
        return Array(tles.keys)
    }

    public func clear() {
        tles.removeAll()
    }

    public func allTLEs() -> [String: TLE] {
        tles
    }

    public func loadFromCelestrak(url: String) async throws {
        let (data, _) = try await URLSession.shared.data(from: URL(string: url)!)
        let content = String(data: data, encoding: .utf8) ?? ""
        parseTLEContent(content)
    }

    public func loadCatalogNumber(_ catalogNumber: Int, preferredName: String? = nil) async throws {
        let urlString = "https://celestrak.org/NORAD/elements/gp.php?CATNR=\(catalogNumber)&FORMAT=TLE"
        let (data, _) = try await URLSession.shared.data(from: URL(string: urlString)!)
        let content = String(data: data, encoding: .utf8) ?? ""
        parseTLEContent(content, preferredName: preferredName)
    }

    private func parseTLEContent(_ content: String, preferredName: String? = nil) {
        let lines = content.components(separatedBy: "\n")
        var i = 0
        while i < lines.count - 2 {
            let name = lines[i].trimmingCharacters(in: .whitespaces)
            let line1 = lines[i + 1].trimmingCharacters(in: .whitespaces)
            let line2 = lines[i + 2].trimmingCharacters(in: .whitespaces)

            if line1.hasPrefix("1") && line2.hasPrefix("2") {
                addTLE(name: preferredName ?? (name.isEmpty ? "Unknown" : name), line1: line1, line2: line2)
                i += 3
            } else {
                i += 1
            }
        }
    }
}
