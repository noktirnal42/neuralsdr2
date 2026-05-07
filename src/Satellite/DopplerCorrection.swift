//
//  DopplerCorrection.swift
//  NeuralSDR2
//
//  Doppler shift correction for satellite communications
//

import Foundation

public class DopplerCorrection {
    private let speedOfLightKmPerS: Double = 299792.458

    public func calculateShift(rangeRate: Double, frequency: Double) -> Double {
        return -frequency * rangeRate / speedOfLightKmPerS
    }

    public func calculateSatelliteShift(satellite: SatellitePosition, frequency: Double) -> Double {
        return calculateShift(rangeRate: satellite.rangeRate, frequency: frequency)
    }

    public func getCorrectedFrequency(frequency: Double, rangeRate: Double) -> Double {
        let shift = calculateShift(rangeRate: rangeRate, frequency: frequency)
        return frequency + shift
    }

    public func getDopplerCurve(
        propagator: SGP4Propagator,
        frequency: Double,
        observerLat: Double,
        observerLon: Double,
        pass: SatellitePass,
        steps: Int = 100
    ) -> [(time: Date, shift: Double, correctedFreq: Double)] {
        var result: [(time: Date, shift: Double, correctedFreq: Double)] = []
        let duration = pass.los.timeIntervalSince(pass.aos)
        let stepSize = duration / Double(steps)

        for i in 0...steps {
            let t = pass.aos.addingTimeInterval(stepSize * Double(i))
            let pos = propagator.getPosition(at: t, observerLat: observerLat, observerLon: observerLon)
            let shift = calculateShift(rangeRate: pos.rangeRate, frequency: frequency)
            result.append((time: t, shift: shift, correctedFreq: frequency + shift))
        }

        return result
    }
}

public class AutoDopplerTracker {
    private var propagator: SGP4Propagator
    private var frequency: Double
    private var observerLat: Double
    private var observerLon: Double
    private var lastCorrection: Double = 0
    private var correctionInterval: TimeInterval = 1.0
    private var lastUpdateTime: Date = Date()

    public var onFrequencyUpdate: ((Double) -> Void)?

    public init(propagator: SGP4Propagator, frequency: Double, latitude: Double, longitude: Double) {
        self.propagator = propagator
        self.frequency = frequency
        self.observerLat = latitude
        self.observerLon = longitude
    }

    public func update() {
        let now = Date()
        guard now.timeIntervalSince(lastUpdateTime) >= correctionInterval else { return }
        lastUpdateTime = now

        let pos = propagator.getPosition(at: now, observerLat: observerLat, observerLon: observerLon)

        let doppler = DopplerCorrection()
        let shift = doppler.calculateShift(rangeRate: pos.rangeRate, frequency: frequency)
        let correctedFreq = frequency + shift

        if correctedFreq != lastCorrection {
            lastCorrection = correctedFreq
            onFrequencyUpdate?(correctedFreq)
        }
    }

    public func getCurrentCorrection() -> Double {
        let pos = propagator.getPosition(at: Date(), observerLat: observerLat, observerLon: observerLon)
        let doppler = DopplerCorrection()
        return doppler.calculateShift(rangeRate: pos.rangeRate, frequency: frequency)
    }

    public func getCurrentRangeRate() -> Double {
        let pos = propagator.getPosition(at: Date(), observerLat: observerLat, observerLon: observerLon)
        return pos.rangeRate
    }

    public func startTracking() {
    }

    public func stopTracking() {
        lastCorrection = 0
    }

    public func setUpdateInterval(_ interval: TimeInterval) {
        correctionInterval = interval
    }
}

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

    public func getUplinkFrequency() -> Double {
        let now = Date()
        let pos = propagator.getPosition(at: now, observerLat: observerLat, observerLon: observerLon)

        let doppler = DopplerCorrection()
        let downlinkShift = doppler.calculateShift(rangeRate: pos.rangeRate, frequency: downlinkFreq)

        let uplinkShift = -downlinkShift * (uplinkFreq / downlinkFreq)

        return uplinkFreq + uplinkShift
    }

    public func getDownlinkCorrection() -> Double {
        let now = Date()
        let pos = propagator.getPosition(at: now, observerLat: observerLat, observerLon: observerLon)
        let doppler = DopplerCorrection()
        return doppler.calculateShift(rangeRate: pos.rangeRate, frequency: downlinkFreq)
    }

    public func getUplinkCorrection() -> Double {
        let now = Date()
        let pos = propagator.getPosition(at: now, observerLat: observerLat, observerLon: observerLon)
        let doppler = DopplerCorrection()
        let downlinkShift = doppler.calculateShift(rangeRate: pos.rangeRate, frequency: downlinkFreq)
        return -downlinkShift * (uplinkFreq / downlinkFreq)
    }
}
