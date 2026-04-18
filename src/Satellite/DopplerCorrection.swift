//
//  DopplerCorrection.swift
//  NeuralSDR2
//
//  Doppler shift correction for satellite communications
//

import Foundation

/// Doppler correction calculator
public class DopplerCorrection {
    private let speedOfLight: Double = 299792458.0  // m/s
    
    /// Calculate Doppler shift
    /// - Parameters:
    ///   - rangeRate: Rate of change of range (km/s), positive = moving away
    ///   - frequency: Transmit/receive frequency (Hz)
    /// - Returns: Frequency shift in Hz
    public func calculateShift(rangeRate: Double, frequency: Double) -> Double {
        // Doppler formula: Δf = -f * v / c
        // rangeRate in km/s, convert to m/s
        let shift = -frequency * (rangeRate * 1000.0) / speedOfLight
        return shift
    }
    
    /// Calculate Doppler shift for specific satellite
    public func calculateSatelliteShift(satellite: SatellitePosition, frequency: Double) -> Double {
        return calculateShift(rangeRate: satellite.rangeRate, frequency: frequency)
    }
    
    /// Get corrected frequency
    public func getCorrectedFrequency(frequency: Double, rangeRate: Double) -> Double {
        let shift = calculateShift(rangeRate: rangeRate, frequency: frequency)
        return frequency + shift
    }
}

/// Auto Doppler tracking
public class AutoDopplerTracker {
    private var propagator: SGP4Propagator
    private var frequency: Double
    private var observerLat: Double
    private var observerLon: Double
    private var lastCorrection: Double = 0
    private var correctionInterval: TimeInterval = 1.0  // Update every second
    private var lastUpdateTime: Date = Date()
    
    // Callback for frequency updates
    public var onFrequencyUpdate: ((Double) -> Void)?
    
    public init(propagator: SGP4Propagator, frequency: Double, latitude: Double, longitude: Double) {
        self.propagator = propagator
        self.frequency = frequency
        self.observerLat = latitude
        self.observerLon = longitude
    }
    
    /// Update Doppler correction
    public func update() {
        let now = Date()
        guard now.timeIntervalSince(lastUpdateTime) >= correctionInterval else { return }
        lastUpdateTime = now
        
        // Get satellite position
        let pos = propagator.getPosition(at: now, observerLat: observerLat, observerLon: observerLon)
        
        // Calculate Doppler shift
        let doppler = DopplerCorrection()
        let shift = doppler.calculateShift(rangeRate: pos.rangeRate, frequency: frequency)
        let correctedFreq = frequency + shift
        
        if correctedFreq != lastCorrection {
            lastCorrection = correctedFreq
            onFrequencyUpdate?(correctedFreq)
        }
    }
    
    /// Start automatic tracking
    public func startTracking() {
        // Would start a timer to call update() periodically
    }
    
    /// Stop tracking
    public func stopTracking() {
        lastCorrection = 0
    }
    
    /// Set update interval
    public func setUpdateInterval(_ interval: TimeInterval) {
        correctionInterval = interval
    }
}

/// Doppler pre-compensation for uplink
public class DopplerPrecompensator {
    private var propagator: SGP4Propagator
    private var downlinkFreq: Double
    private var uplinkFreq: Double
    private var observerLat: Double
    private var observerLon: Double
    
    public init(propagator: SGP4Propagator, downlinkFreq: Double, uplinkFreq: Double, latitude: Double, longitude: Double) {
        self.propagator = propagator
        self.downlinkFreq = downlinkFreq
        self.uplinkFreq = uplinkFreq
        self.observerLat = latitude
        self.observerLon = longitude
    }
    
    /// Calculate uplink frequency with pre-compensation
    public func getUplinkFrequency() -> Double {
        let now = Date()
        let pos = propagator.getPosition(at: now, observerLat: observerLat, observerLon: observerLon)
        
        // Calculate Doppler for downlink
        let doppler = DopplerCorrection()
        let downlinkShift = doppler.calculateShift(rangeRate: pos.rangeRate, frequency: downlinkFreq)
        
        // Calculate required uplink shift (opposite sign)
        let uplinkShift = -downlinkShift * (uplinkFreq / downlinkFreq)
        
        return uplinkFreq + uplinkShift
    }
}
