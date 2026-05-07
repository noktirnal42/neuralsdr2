//
// MapIntegration.swift
// NeuralSDR2
//
// Bridge between ADS-B/Satellite/Weather data and the Map UI
//

import Foundation
import MapKit
import CoreLocation

public struct ADSBSample {
    public var icao: String
    public var callsign: String
    public var lat: Double
    public var lon: Double
    public var alt: Int
    public var speed: Int
    public var heading: Double

    public init(icao: String, callsign: String, lat: Double, lon: Double, alt: Int, speed: Int, heading: Double) {
        self.icao = icao
        self.callsign = callsign
        self.lat = lat
        self.lon = lon
        self.alt = alt
        self.speed = speed
        self.heading = heading
    }
}

public class MapIntegrationManager {
    public private(set) var mapState: MapState
    public private(set) var adsbTraker: ADSBTraker
    public let adsbDecoder: ADSBDecoder
    public private(set) var tleManager: TLEManager
    public let weatherRadarManager: WeatherRadarManager

    public var observerLatitude: Double = 37.7749
    public var observerLongitude: Double = -122.4194

    public init(mapState: MapState) {
        self.mapState = mapState
        self.adsbTraker = ADSBTraker(mapState: mapState)
        self.adsbDecoder = ADSBDecoder()
        self.tleManager = TLEManager()
        self.weatherRadarManager = WeatherRadarManager(mapState: mapState)
    }

    // MARK: - ADS-B Integration

    public func processADSBSamples(_ samples: [ComplexFloat]) {
        let decoded = adsbDecoder.decode(samples: samples)
        DispatchQueue.main.async {
            if decoded.isEmpty {
                self.mapState.aircraftSourceStatus = "Monitoring 1090 MHz"
            } else {
                self.mapState.aircraftSourceStatus = "Receiving ADS-B traffic"
                self.mapState.lastAircraftUpdate = Date()
            }
        }
        for sample in decoded {
            let type = determineAircraftType(callsign: sample.callsign, altitude: sample.alt, speed: sample.speed)
            let aircraft = Aircraft(
                icao: sample.icao,
                callsign: sample.callsign,
                coordinate: CLLocationCoordinate2D(latitude: sample.lat, longitude: sample.lon),
                altitude: sample.alt,
                speed: sample.speed,
                heading: sample.heading,
                type: type,
                history: []
            )
            DispatchQueue.main.async {
                self.mapState.updateAircraft(aircraft)
            }
        }
    }

    public func processADSBRawMessage(_ bytes: [UInt8]) {
        guard let sample = adsbDecoder.decodeMessage(bytes) else { return }
        DispatchQueue.main.async {
            self.mapState.aircraftSourceStatus = "Receiving ADS-B traffic"
            self.mapState.lastAircraftUpdate = Date()
        }
        let type = determineAircraftType(callsign: sample.callsign, altitude: sample.alt, speed: sample.speed)
        let aircraft = Aircraft(
            icao: sample.icao,
            callsign: sample.callsign,
            coordinate: CLLocationCoordinate2D(latitude: sample.lat, longitude: sample.lon),
            altitude: sample.alt,
            speed: sample.speed,
            heading: sample.heading,
            type: type,
            history: []
        )
        DispatchQueue.main.async {
            self.mapState.updateAircraft(aircraft)
        }
    }

    public func cleanupStaleAircraft() {
        adsbDecoder.removeStaleAircraft(maxAge: mapState.aircraftExpirationInterval)
        DispatchQueue.main.async {
            self.mapState.removeStaleAircraft()
            if self.mapState.trackedAircraft.isEmpty {
                self.mapState.aircraftSourceStatus = "No recent aircraft"
            }
        }
    }

    public func determineAircraftType(callsign: String, altitude: Int, speed: Int) -> AircraftType {
        let upper = callsign.uppercased()
        let militaryPrefixes = ["AF", "RCH", "VMFAT", "NAV", "COAST"]
        for prefix in militaryPrefixes {
            if upper.hasPrefix(prefix) {
                return .military
            }
        }
        if altitude < 3000 && speed < 180 {
            return .helicopter
        }
        if upper.hasPrefix("N") {
            return .privateAviation
        }
        if speed > 250 || altitude > 18000 {
            return .commercial
        }
        return .unknown
    }

    // MARK: - Satellite Integration

    public func updateSatellitePositions() {
        let names = tleManager.getTLENames()
        let now = Date()
        DispatchQueue.main.async {
            self.mapState.satelliteSourceStatus = names.isEmpty ? "No loaded satellites" : "Updating satellite positions"
        }

        for name in names {
            guard let tle = tleManager.getTLE(name: name) else { continue }
            let propagator = SGP4Propagator(tle: tle)
            let pos = propagator.getPosition(at: now, observerLat: observerLatitude, observerLon: observerLongitude)

            let groundTrack = calculateGroundTrack(propagator)
            let nextPass = findNextPass(propagator: propagator)

            let track = SatelliteTrack(
                name: name,
                coordinate: CLLocationCoordinate2D(latitude: pos.latitude, longitude: pos.longitude),
                groundTrack: groundTrack,
                nextPass: nextPass,
                isVisible: pos.elevation > 0
            )
            DispatchQueue.main.async {
                self.mapState.updateSatellite(track)
            }
        }

        DispatchQueue.main.async {
            self.mapState.satelliteSourceStatus = self.mapState.trackedSatellites.isEmpty ? "No visible satellite data" : "Tracking \(self.mapState.trackedSatellites.count) satellites"
        }
    }

    public func addSatellite(name: String, line1: String, line2: String) {
        tleManager.addTLE(name: name, line1: line1, line2: line2)
    }

    public func removeSatellite(name: String) {
        tleManager.removeTLE(name: name)
        DispatchQueue.main.async {
            self.mapState.trackedSatellites.removeAll { $0.name == name }
        }
    }

    public func loadDefaultSatellites() {
        tleManager.clear()
        tleManager.addTLE(
            name: "ISS (ZARYA)",
            line1: "1 25544U 98067A   25093.52552151  .00016717  00000+0  30164-3 0  9993",
            line2: "2 25544  51.6416 200.0014 0006703  40.5984 319.5620 15.49569750492847"
        )
        tleManager.addTLE(
            name: "NOAA 19",
            line1: "1 33591U 09005A   25093.50000000  .00000123  00000+0  11564-3 0  9991",
            line2: "2 33591  99.1889  22.6654 0013095 157.9310 202.1713 14.12462885830294"
        )
        tleManager.addTLE(
            name: "NOAA 15",
            line1: "1 25338U 98030A   25093.50000000  .00000068  00000+0  75921-4 0  9992",
            line2: "2 25338  98.7301  58.1271 0010785 126.5355 233.6171 14.25931759403165"
        )
        tleManager.addTLE(
            name: "AO-91 (FOX-1B)",
            line1: "1 43017U 17074A   25093.50000000  .00000456  00000+0  27846-3 0  9994",
            line2: "2 43017  97.4742  48.2545 0012658 319.3255  40.6867 15.09347517404700"
        )
        tleManager.addTLE(
            name: "AO-92 (FOX-1D)",
            line1: "1 43137U 18004A   25093.50000000  .00000378  00000+0  23164-3 0  9995",
            line2: "2 43137  97.5303  52.1187 0012986 308.4124  51.5677 15.10495877386541"
        )
        tleManager.addTLE(
            name: "SO-50 (SAUDISAT 1C)",
            line1: "1 27607U 02058C   25093.50000000  .00000312  00000+0  19832-3 0  9996",
            line2: "2 27607  64.5564  68.1241 0079474 230.7434 128.3815 14.73826648120137"
        )
    }

    public func refreshTrackedSatellitesFromCelesTrak() async throws {
        await MainActor.run {
            self.mapState.satelliteSourceStatus = "Refreshing TLEs"
        }
        let trackedCatalogs: [(name: String, catalogNumber: Int)] = [
            ("ISS (ZARYA)", 25544),
            ("NOAA 19", 33591),
            ("NOAA 15", 25338),
            ("AO-91 (FOX-1B)", 43017),
            ("AO-92 (FOX-1D)", 43137),
            ("SO-50 (SAUDISAT 1C)", 27607)
        ]

        for satellite in trackedCatalogs {
            try await tleManager.loadCatalogNumber(satellite.catalogNumber, preferredName: satellite.name)
        }

        await MainActor.run {
            self.mapState.lastSatelliteRefresh = Date()
            self.mapState.satelliteSourceStatus = "TLEs refreshed from CelesTrak"
        }
    }

    private func calculateGroundTrack(_ propagator: SGP4Propagator) -> [CLLocationCoordinate2D] {
        let now = Date()
        let stepInterval: TimeInterval = 30.0
        let totalDuration: TimeInterval = 90.0 * 60.0
        let steps = Int(totalDuration / stepInterval)
        var path: [CLLocationCoordinate2D] = []

        for i in 0...steps {
            let time = now.addingTimeInterval(Double(i) * stepInterval)
            let pos = propagator.getPosition(at: time)
            path.append(CLLocationCoordinate2D(latitude: pos.latitude, longitude: pos.longitude))
        }

        return path
    }

    private func findNextPass(propagator: SGP4Propagator) -> SatellitePass? {
        let predictor = PassPredictor(
            propagator: propagator,
            latitude: observerLatitude,
            longitude: observerLongitude
        )
        return predictor.findNextPass()
    }

    // MARK: - Weather Integration

    public func setUATDecoder(_ decoder: UATDecoder) {
        weatherRadarManager.setDecoder(decoder)
    }

    // MARK: - Observer Location

    public func updateObserverLocation(lat: Double, lon: Double) {
        observerLatitude = lat
        observerLongitude = lon
    }
}
