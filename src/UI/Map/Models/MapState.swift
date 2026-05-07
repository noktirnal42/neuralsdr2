//
//  MapState.swift
//  NeuralSDR2
//
//  State management for the universal map system
//

import SwiftUI
import MapKit
import CoreLocation

/// Universal Map State managing aircraft, satellites, and weather
public class MapState: NSObject, ObservableObject, CLLocationManagerDelegate {
    // User Location
    @Published public var userLocation: CLLocationCoordinate2D?
    @Published public var isLocationEnabled = false
    @Published public var isUsingCurrentLocation = true
    @Published public var lastLocationUpdate: Date?
    @Published public var locationStatusMessage: String = "Waiting for location"

    // Aircraft Tracking
    @Published public var trackedAircraft: [Aircraft] = []
    @Published public var aircraftFilter: AircraftFilter = AircraftFilter()
    @Published public var aircraftSourceStatus: String = "Idle"
    @Published public var lastAircraftUpdate: Date?
    @Published public var lastAircraftCleanup: Date?

    // Satellite Tracking
    @Published public var trackedSatellites: [SatelliteTrack] = []
    @Published public var showOrbits = true
    @Published public var showGroundTracks = true
    @Published public var showDecodedNOAA = true
    @Published public var satelliteSourceStatus: String = "Idle"
    @Published public var lastSatelliteRefresh: Date?
    @Published public var observerLatitude: Double = 37.7749
    @Published public var observerLongitude: Double = -122.4194
    @Published public var decodedNOAAArtifacts: [DecodedNOAAArtifact] = []
    @Published public var selectedDecodedNOAAArtifactID: String?
    @Published public var decodedNOAAFocusRequestToken: Int = 0
    @Published public var minimumNOAAQualityTier: NOAAArtifactQualityTier = .weak

    // Weather Radar
    @Published public var weatherOverlayEnabled = false
    @Published public var weatherRadarData: WeatherRadarData?
    @Published public var weatherRadarBlocks: [WeatherRadarData] = []

    // Map Configuration
    @Published public var mapStyle: MapStyle = .hybrid
    @Published public var showRangeRings = true
    @Published public var rangeRingRadius: Double = 50.0 // km

    // Aircraft Expiration
    public var aircraftExpirationInterval: TimeInterval = 60.0
    public var onObserverLocationChanged: ((Double, Double) -> Void)?

    private let locationManager = CLLocationManager()
    private var locationRetryWorkItem: DispatchWorkItem?

    public enum MapStyle: String {
        case standard, satellite, hybrid, muted
    }

    public override init() {
        super.init()
        setupLocationManager()
    }

    private func setupLocationManager() {
        guard CLLocationManager.locationServicesEnabled() else {
            isLocationEnabled = false
            locationStatusMessage = "Location services disabled in macOS"
            return
        }

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 50

        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationStatusMessage = "Waiting for location permission"
            locationManager.requestWhenInUseAuthorization()
        }
        handleAuthorizationStatus(status)
    }

    private func handleAuthorizationStatus(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            isLocationEnabled = true
            locationStatusMessage = isUsingCurrentLocation ? "Acquiring current location" : "Using manual observer location"
            beginSearchingForLocation()
            if let location = locationManager.location {
                applyLocation(location)
            }
        case .notDetermined:
            isLocationEnabled = false
            locationStatusMessage = "Waiting for location permission"
        case .restricted, .denied:
            isLocationEnabled = false
            locationStatusMessage = "Location access denied"
            locationManager.stopUpdatingLocation()
        @unknown default:
            isLocationEnabled = false
            locationStatusMessage = "Location unavailable"
        }
    }

    private func applyLocation(_ location: CLLocation) {
        let coordinate = location.coordinate
        DispatchQueue.main.async {
            self.userLocation = coordinate
            self.isLocationEnabled = true
            self.lastLocationUpdate = Date()
            self.locationStatusMessage = String(
                format: "Using current location %.4f, %.4f",
                coordinate.latitude,
                coordinate.longitude
            )
            guard self.isUsingCurrentLocation else { return }
            self.observerLatitude = coordinate.latitude
            self.observerLongitude = coordinate.longitude
            self.onObserverLocationChanged?(coordinate.latitude, coordinate.longitude)
        }
    }

    public func setManualObserverLocation(lat: Double, lon: Double) {
        isUsingCurrentLocation = false
        observerLatitude = lat
        observerLongitude = lon
        locationStatusMessage = String(format: "Using manual observer %.4f, %.4f", lat, lon)
        onObserverLocationChanged?(lat, lon)
    }

    public func resumeAutomaticObserverLocation() {
        isUsingCurrentLocation = true
        locationStatusMessage = "Acquiring current location"
        if let location = locationManager.location {
            applyLocation(location)
        } else {
            beginSearchingForLocation()
        }
    }

    public func restoreObserverPreference(
        lat: Double,
        lon: Double,
        useCurrentLocation: Bool
    ) {
        if useCurrentLocation {
            isUsingCurrentLocation = true
            if let location = locationManager.location {
                applyLocation(location)
            } else {
                observerLatitude = lat
                observerLongitude = lon
                locationStatusMessage = "Waiting for current location"
                onObserverLocationChanged?(lat, lon)
                beginSearchingForLocation()
            }
        } else {
            setManualObserverLocation(lat: lat, lon: lon)
        }
    }

    private func beginSearchingForLocation() {
        locationRetryWorkItem?.cancel()
        locationManager.startUpdatingLocation()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.locationManager.requestLocation()
        }
        locationRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        handleAuthorizationStatus(manager.authorizationStatus)
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        locationRetryWorkItem?.cancel()
        applyLocation(location)
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            if let clError = error as? CLError, clError.code == .locationUnknown {
                self.locationStatusMessage = "Searching for current location"
                self.beginSearchingForLocation()
                return
            }

            self.locationStatusMessage = "Location update failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Aircraft Management

    public func updateAircraft(_ aircraft: Aircraft) {
        if let index = trackedAircraft.firstIndex(where: { $0.icao == aircraft.icao }) {
            var updated = aircraft
            if !trackedAircraft[index].history.isEmpty {
                updated.history = trackedAircraft[index].history + [aircraft.coordinate]
            } else {
                updated.history = [aircraft.coordinate]
            }
            trackedAircraft[index] = updated
        } else {
            trackedAircraft.append(aircraft)
        }
        lastAircraftUpdate = aircraft.lastSeen
    }

    public func removeAircraft(icao: String) {
        trackedAircraft.removeAll { $0.icao == icao }
    }

    public func removeStaleAircraft() {
        let now = Date()
        trackedAircraft.removeAll { aircraft in
            now.timeIntervalSince(aircraft.lastSeen) > aircraftExpirationInterval
        }
        lastAircraftCleanup = now
    }

    // MARK: - Satellite Management

    public func updateSatellite(_ satellite: SatelliteTrack) {
        if let index = trackedSatellites.firstIndex(where: { $0.name == satellite.name }) {
            trackedSatellites[index] = satellite
        } else {
            trackedSatellites.append(satellite)
        }
    }
}

// MARK: - Models

public struct Aircraft: Identifiable {
    public let id = UUID()
    public let icao: String
    public var callsign: String
    public var coordinate: CLLocationCoordinate2D
    public var altitude: Int // Feet
    public var speed: Int // Knots
    public var heading: Double // Degrees
    public var type: AircraftType
    public var history: [CLLocationCoordinate2D]
    public var lastSeen: Date = Date()

    public var altitudeColor: Color {
        if altitude < 10000 { return .green }
        if altitude < 25000 { return .yellow }
        if altitude < 40000 { return .orange }
        return .red
    }
}

public enum AircraftType {
    case commercial, privateAviation, military, helicopter, unknown

    public var icon: String {
        switch self {
        case .commercial: return "airplane"
        case .privateAviation: return "airplane.takeoff"
        case .military: return "airplane.deployment"
        case .helicopter: return "helicopter"
        case .unknown: return "airplane.circle"
        }
    }
}

public struct SatelliteTrack: Identifiable {
    public let id = UUID()
    public var name: String
    public var coordinate: CLLocationCoordinate2D
    public var groundTrack: [CLLocationCoordinate2D]
    public var nextPass: SatellitePass?
    public var isVisible: Bool
}

public struct WeatherRadarData: Identifiable {
    public var id: String { key }
    public var timestamp: Date
    public var key: String
    public var reflectivityData: [Float] // dBZ values
    public var bounds: MKMapRect
    public var gridWidth: Int
    public var gridHeight: Int
    public var center: CLLocationCoordinate2D
    public var latitudeSpan: Double
    public var longitudeSpan: Double
    public var source: String

    public init(
        timestamp: Date,
        key: String,
        reflectivityData: [Float],
        bounds: MKMapRect,
        gridWidth: Int,
        gridHeight: Int,
        center: CLLocationCoordinate2D,
        latitudeSpan: Double,
        longitudeSpan: Double,
        source: String
    ) {
        self.timestamp = timestamp
        self.key = key
        self.reflectivityData = reflectivityData
        self.bounds = bounds
        self.gridWidth = gridWidth
        self.gridHeight = gridHeight
        self.center = center
        self.latitudeSpan = latitudeSpan
        self.longitudeSpan = longitudeSpan
        self.source = source
    }
}

public struct DecodedNOAAArtifact: Identifiable {
    public let id: String
    public let satellite: String
    public let imagePath: String
    public let createdAt: Date
    public let samplePoints: [CLLocationCoordinate2D]
    public let estimatedSwathWidthKilometers: Double
    public let centerCoordinate: CLLocationCoordinate2D
    public let qualityScore: Double
    public let qualityTier: NOAAArtifactQualityTier
}

public struct AircraftFilter {
    var minAltitude: Int = 0
    var maxAltitude: Int = 60000
    var typeFilter: Set<AircraftType> = []
}
