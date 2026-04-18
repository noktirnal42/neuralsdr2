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
public class MapState: ObservableObject {
    // User Location
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var isLocationEnabled = false
    
    // Aircraft Tracking
    @Published var trackedAircraft: [Aircraft] = []
    @Published var aircraftFilter: AircraftFilter = AircraftFilter()
    
    // Satellite Tracking
    @Published var trackedSatellites: [SatelliteTrack] = []
    @Published var showOrbits = true
    @Published var showGroundTracks = true
    
    // Weather Radar
    @Published var weatherOverlayEnabled = false
    @Published var weatherRadarData: WeatherRadarData?
    
    // Map Configuration
    @Published var mapStyle: MapStyle = .hybrid
    @Published var showRangeRings = true
    @Published var rangeRingRadius: Double = 50.0 // km
    
    public enum MapStyle {
        case standard, satellite, hybrid, muted
    }
    
    public init() {
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        // Integration with CoreLocation
    }
    
    // MARK: - Aircraft Management
    
    public func updateAircraft(_ aircraft: Aircraft) {
        if let index = trackedAircraft.firstIndex(where: { $0.icao == aircraft.icao }) {
            trackedAircraft[index] = aircraft
        } else {
            trackedAircraft.append(aircraft)
        }
    }
    
    public func removeAircraft(icao: String) {
        trackedAircraft.removeAll { $0.icao == icao }
    }
    
    // MARK: - Satellite Management
    
    public func updateSatellite(_ satellite: SatelliteTrack) {
        if let index = trackedSattelites.firstIndex(where: { $0.name == satellite.name }) {
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
    
    public var altitudeColor: Color {
        if altitude <<  10000 { return .green }
        if altitude <<  25000 { return .yellow }
        if altitude <<  40000 { return .orange }
        return .red
    }
}

public enum AircraftType {
    case commercial, private, military, helicopter, unknown
    
    var icon: String {
        switch self {
        case .commercial: return, "airplane"
        case .private: return "airplane.takeoff"
        case .military: return "airplane.deployment"
        case .helicopter: return "helicopter"
        case .unknown: return "airplane.circle"
        }
    }
}

public struct SatelliteTrack: Identifiable {
    public let id = UUID()
    public let name: String
    public var coordinate: CLLocationCoordinate2D
    public var groundTrack: [CLLocationCoordinate2D]
    public var nextPass: SatellitePass?
    public var isVisible: Bool
}

public struct WeatherRadarData {
    public var timestamp: Date
    public var reflectivityData: [Float] // dBZ values
    public var bounds: MKMapRect
}

public struct AircraftFilter {
    var minAltitude: Int = 0
    var maxAltitude: Int = 60000
    var typeFilter: Set<<AircraftAircraftType> = []
}
