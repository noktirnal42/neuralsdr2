//
//  SGP4.swift
//  NeuralSDR2
//
//  SGP4/SDP4 Satellite Orbit Propagation
//  Simplified General Perturbations satellite orbit model
//

import Foundation
import simd

/// TLE (Two-Line Element) data structure
public struct TLE {
    public var name: String
    public var line1: String
    public var line2: String
    
    // Parsed elements
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
        
        // Parse line 1
        self.satelliteNumber = Int(line1[7..<12].trimmingCharacters(in: .whitespaces)) ?? 0
        self.classification = line1[line1.index(line1.startIndex, offsetBy: 7)].unicodeScalars.first.map { Character($0) } ?? "U"
        self.launchYear = Int(line1[9..<11].trimmingCharacters(in: .whitespaces)) ?? 0
        self.launchNumber = Int(line1[14..<17].trimmingCharacters(in: .whitespaces)) ?? 0
        self.epochYear = Int(line1[18..<20].trimmingCharacters(in: .whitespaces)) ?? 0
        self.epochDay = Double(line1[20..<32].trimmingCharacters(in: .whitespaces)) ?? 0.0
        self.meanMotion = Double(line1[33..<43].trimmingCharacters(in: .whitespaces)) ?? 0.0
        self.bstar = Double(line1[44..<51].trimmingCharacters(in: .whitespaces)).map { $0 * 1e-5 } ?? 0.0
        
        // Parse line 2
        self.inclination = Double(line2[8..<16].trimmingCharacters(in: .whitespaces)) ?? 0.0
        self.raan = Double(line2[17..<25].trimmingCharacters(in: .whitespaces)) ?? 0.0
        self.eccentricity = Double("0." + line2[26..<33].trimmingCharacters(in: .whitespaces)) ?? 0.0
        self.argPerigee = Double(line2[34..<42].trimmingCharacters(in: .whitespaces)) ?? 0.0
        self.meanAnomaly = Double(line2[43..<51].trimmingCharacters(in: .whitespaces)) ?? 0.0
    }
}

/// Satellite position and velocity
public struct SatellitePosition {
    public var position: SIMD3<Double>  // km
    public var velocity: SIMD3<Double>  // km/s
    public var latitude: Double         // degrees
    public var longitude: Double        // degrees
    public var altitude: Double         // km
    public var range: Double            // km
    public var rangeRate: Double        // km/s
    public var elevation: Double        // degrees
    public var azimuth: Double          // degrees
    public var rightAscension: Double   // degrees
    public var declination: Double      // degrees
}

/// SGP4 propagator
public class SGP4Propagator {
    private var tle: TLE
    private var epoch: Date
    
    // Constants
    private let xj = 60.0 * 60.0 * 24.0  // Seconds in a day
    private let x2o3 = 2.0 / 3.0
    private let xke = 7.43669161e-2
    private let xkmper = 6378.135
    private let xmpfe = 60.0
    private let pi = Double.pi
    private let twopi = 2.0 * Double.pi
    
    public init(tle: TLE) {
        self.tle = tle
        self.epoch = Date()
    }
    
    /// Update TLE
    public func updateTLE(_ newTLE: TLE) {
        self.tle = newTLE
    }
    
    /// Get satellite position at given time
    public func getPosition(at date: Date, observerLat: Double = 0, observerLon: Double = 0) -> SatellitePosition {
        // Calculate time since epoch
        let timeSinceEpoch = date.timeIntervalSince(epoch) / 86400.0  // Days
        
        // SGP4 propagation
        let position = sgdp4(timeSinceEpoch)
        
        // Convert to lat/lon/alt
        let latLonAlt = positionToLatLonAlt(position: position.position)
        
        // Calculate look angles from observer
        let lookAngles = calculateLookAngles(
            satellitePos: position.position,
            observerLat: observerLat,
            observerLon: observerLon
        )
        
        return SatellitePosition(
            position: position.position,
            velocity: position.velocity,
            latitude: latLonAlt.0,
            longitude: latLonAlt.1,
            altitude: latLonAlt.2,
            range: lookAngles.range,
            rangeRate: 0,  // Would need velocity for this
            elevation: lookAngles.elevation,
            azimuth: lookAngles.azimuth,
            rightAscension: 0,
            declination: 0
        )
    }
    
    private func sgdp4(_ tsince: Double) -> (position: SIMD3<Double>, velocity: SIMD3<Double>) {
        // Simplified SGP4 implementation
        // Full implementation would go here
        
        // Calculate mean motion
        let n = tle.meanMotion * twopi / xj
        
        // Calculate semi-major axis
        let a = pow(xke * xj / n, x2o3) - 1.0
        
        // Calculate position in orbital plane
        let meanAnomaly = tle.meanAnomaly * twopi / 360.0 + n * tsince * twopi
        let eccentricAnomaly = meanAnomaly + tle.eccentricity * sin(meanAnomaly)
        let trueAnomaly = 2.0 * atan2(
            sqrt(1.0 + tle.eccentricity) * sin(eccentricAnomaly / 2.0),
            sqrt(1.0 - tle.eccentricity) * cos(eccentricAnomaly / 2.0)
        )
        
        // Position in orbital plane
        let r = a * (1.0 - tle.eccentricity * cos(eccentricAnomaly))
        let x = r * cos(trueAnomaly)
        let y = r * sin(trueAnomaly)
        let z = 0.0
        
        // Rotate to equatorial coordinates
        let omega = tle.argPerigee * twopi / 360.0
        let node = tle.raan * twopi / 360.0
        let incl = tle.inclination * twopi / 360.0
        
        let cosNode = cos(node)
        let sinNode = sin(node)
        let cosInc = cos(incl)
        let sinInc = sin(incl)
        let cosOmega = cos(omega)
        let sinOmega = sin(omega)
        
        let xEq = x * (cosNode * cosOmega - sinNode * sinOmega * cosInc) -
                  y * (cosNode * sinOmega + sinNode * cosOmega * cosInc)
        let yEq = x * (sinNode * cosOmega + cosNode * sinOmega * cosInc) +
                  y * (-sinNode * sinOmega + cosNode * cosOmega * cosInc)
        let zEq = x * (sinOmega * sinInc) + y * (cosOmega * sinInc)
        
        return (SIMD3<Double>(xEq, yEq, zEq), SIMD3<Double>(0, 0, 0))
    }
    
    private func positionToLatLonAlt(position: SIMD3<Double>) -> (Double, Double, Double) {
        // Convert ECI to lat/lon/alt
        let r = sqrt(position.x * position.x + position.y * position.y + position.z * position.z)
        let lat = asin(position.z / r) * 180.0 / pi
        let lon = atan2(position.y, position.x) * 180.0 / pi
        let alt = r - xkmper
        
        return (lat, lon, alt)
    }
    
    private func calculateLookAngles(satellitePos: SIMD3<Double>, observerLat: Double, observerLon: Double) -> (elevation: Double, azimuth: Double, range: Double) {
        // Simplified look angle calculation
        return (0, 0, 0)
    }
}

/// Satellite pass prediction
public struct SatellitePass {
    public var satellite: String
    public var aos: Date           // Acquisition of Signal (rise time)
    public var los: Date           // Loss of Signal (set time)
    public var tca: Date           // Time of Closest Approach
    public var maxElevation: Double
    public var maxElevationTime: Date
    public var visible: Bool       // Is pass visible (not in eclipse)?
    public var duration: TimeInterval
}

/// Pass predictor
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
    
    /// Find next pass
    public func findNextPass(from date: Date = Date(), maxDays: Int = 3) -> SatellitePass? {
        let step: TimeInterval = 60  // 1 minute steps
        var currentTime = date
        var inView = false
        var aos = Date()
        var maxElev: Double = 0
        var maxElevTime = Date()
        
        while currentTime < date.addingTimeInterval(Double(maxDays * 24 * 3600)) {
            let pos = propagator.getPosition(at: currentTime, observerLat: observerLat, observerLon: observerLon)
            
            if pos.elevation > 0 {
                if !inView {
                    // AOS
                    aos = currentTime
                    inView = true
                    maxElev = 0
                }
                
                if pos.elevation > maxElev {
                    maxElev = pos.elevation
                    maxElevTime = currentTime
                }
            } else if inView {
                // LOS - found a pass
                return SatellitePass(
                    satellite: propagator.tle.name,
                    aos: aos,
                    los: currentTime,
                    tca: maxElevTime,
                    maxElevation: maxElev,
                    maxElevationTime: maxElevTime,
                    visible: true,
                    duration: currentTime.timeIntervalSince(aos)
                )
            }
            
            currentTime += step
        }
        
        return nil
    }
    
    /// Find all passes in next N days
    public func findPasses(days: Int = 3) -> [SatellitePass] {
        var passes: [SatellitePass] = []
        var currentDate = Date()
        
        while let pass = findNextPass(from: currentDate) {
            passes.append(pass)
            currentDate = pass.los.addingTimeInterval(1)  // Start searching after LOS
        }
        
        return passes
    }
}

/// TLE Manager
public class TLEManager {
    private var tles: [String: TLE] = [:]
    
    /// Add TLE from lines
    public func addTLE(name: String, line1: String, line2: String) {
        let tle = TLE(name: name, line1: line1, line2: line2)
        tles[name] = tle
    }
    
    /// Get TLE by name
    public func getTLE(name: String) -> TLE? {
        return tles[name]
    }
    
    /// Remove TLE
    public func removeTLE(name: String) {
        tles.removeValue(forKey: name)
    }
    
    /// Get all TLE names
    public func getTLENames() -> [String] {
        return Array(tles.keys)
    }
    
    /// Clear all TLEs
    public func clear() {
        tles.removeAll()
    }
    
    /// Load TLEs from Celestrak URL
    public func loadFromCelestrak(url: String) async throws {
        let (data, _) = try await URLSession.shared.data(from: URL(string: url)!)
        let content = String(data: data, encoding: .utf8) ?? ""
        parseTLEContent(content)
    }
    
    private func parseTLEContent(_ content: String) {
        // Parse TLE file format
        let lines = content.components(separatedBy: "\n")
        var i = 0
        while i < lines.count - 2 {
            let name = lines[i].trimmingCharacters(in: .whitespaces)
            let line1 = lines[i + 1].trimmingCharacters(in: .whitespaces)
            let line2 = lines[i + 2].trimmingCharacters(in: .whitespaces)
            
            if line1.hasPrefix("1") && line2.hasPrefix("2") {
                addTLE(name: name.isEmpty ? "Unknown" : name, line1: line1, line2: line2)
                i += 3
            } else {
                i += 1
            }
        }
    }
}
