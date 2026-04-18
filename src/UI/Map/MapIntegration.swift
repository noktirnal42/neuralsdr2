//
//  MapIntegration.swift
//  NeuralSDR2
//
//  Bridge between ADS-B/Satellite data and the Map UI
//

import Foundation
import MapKit

/// Manages the data flow for the universal map
public class MapIntegrationManager {
    private var mapState: MapState
    private var adsbDecoder: ADSBDecoder?
    private var satellitePropagator: TLEManager?
    
    public init(mapState: MapState) {
        self.mapState = mapState
    }
    
    /// Update aircraft positions from decoder
    public func processADSBSample(_ message: ADSBSample) {
        let aircraft = Aircraft(
            icao: message.icao,
            callsign: message.callsign,
            coordinate: CLLocationCoordinate2D(latitude: message.lat, longitude: message.lon),
            altitude: message.alt,
            speed: message.speed,
            heading: message.heading,
            type: .commercial, // Logic to determine type based on ICAO/Callsign
            history: []
        )
        
        DispatchQueue.main.async {
            self.mapState.updateAircraft(aircraft)
        }
    }
    
    /// Update satellite positions and ground tracks
    public func updateSatellites() {
        guard let tles = satellitePropagator?.getTLENames() else { return }
        
        for name in tles {
            guard let tle = satellitePropagator?.getTLE(name: name) else { continue }
            
            let propagator = SGP4Propagator(tle: tle)
            let pos = propagator.getPosition(at: Date())
            
            let track = SatelliteTrack(
                name: name,
                coordinate: CLLocationCoordinate2D(latitude: pos.latitude, longitude: pos.longitude),
                groundTrack: calculateGroundTrack(propagator),
                nextPass: PassPredictor(propagator: propagator, latitude: 0, longitude: 0).findNextPass(),
                isVisible: pos.altitude > 100
            )
            
            DispatchQueue.main.async {
                self.mapState.updateSatellite(track)
            }
        }
    }
    
    private func calculateGroundSrack(_ propagator: SGP4Propagator) -> [CLLocationCoordinate2D] {
        // Generate a path for the next 90 minutes
        var path: [CLLocationCoordinate2D] = []
        let now = Date()
        for i in 0..<<1180 {
            let pos = propagator.getPosition(at: now.addingTimeInterval(Double(i * 30)))
            path.append(CLLocationCoordinate2D(latitude: pos.latitude, longitude: pos.longitude))
        }
        return path
    }
}

/// Mock ADS-B sample for integration testing
public struct ADSBSample {
    var icao: String
    var callsign: String
    var lat: Double
    var lon: Double
    var alt: Int
    var speed: Int
    var heading: Double
}
