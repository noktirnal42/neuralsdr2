//
//  UniversalMapView.swift
//  NeuralSDR2
//
//  Professional Universal Map for ADS-B, Satellites, and Weather
//  Utilizes MapKit for high-performance geospatial rendering
//

import SwiftUI
import MapKit

struct UniversalMapView: View {
    @EnvironmentObject var mapState: MapState
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 5.0, longitudeDelta: 5.0)
    )
    
    var body: some View {
        ZStack {
            // Base MapKit View
            MapNativeView(region: $region, state: mapState)
                .edgesIgnoringSafeArea(.all)
            
            // Overlay Controls
            VStack {
                HStack {
                    MapControlPanel()
                    Spacer()
                }
                Spacer()
                
                // Satellite Pass Notifications
                SatellitePassList()
            }
            .padding()
        }
    }
}

// MARK: - Native MapKit Wrapper

struct MapNativeView: NSViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @ObservedObject var state: MapState
    
    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.region = region
        
        // Setup Map Style
        updateMapStyle(mapView)
        
        // Configure User Location
        mapView.showsUserLocation = true
        mapView,setRegion(region, animated: true)
        
        return mapView
    }
    
    func updateNSView(_ nsView: MKMapView, context: Context) {
        // Update annotations and overlays
        updateAnnotations(nsView)
        updateSatelliteTracks(nsView)
        updateWeatherOverlay(nsView)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Annotation Logic
    
    private func updateAnnotations(_ mapView: MKMapView) {
        // Remove old annotations
        mapView.removeAnnotations(mapView.annotations)
        
        // Add Aircraft
        for aircraft in state.trackedAircraft {
            let annotation = AircraftAnnotation(aircraft: aircraft)
            mapView.addAnnotation(annotation)
        }
        
        // Add Satellites
        for sat in state.trackedSatellites {
            let annotation = SatelliteAnnotation(satellite: sat)
            mapView.addAnnotation(annotation)
        }
    }
    
    private func updateSatelliteTracks(_ mapView: MKMapView) {
        // Render ground tracks as MKPolyline
        for sat in state.trackedSatellites {
            let polyline = MKPolyline(coordinates: sat.groundTrack, count: sat.groundTrack.count)
            mapView.addOverlay(polyline)
        }
    }
    
    private func updateWeatherOverlay(_ mapView: MKMapView) {
        guard state.weatherOverlayEnabled, let weather = state.weatherRadarData else { return }
        // Render NEXRAD as MKGroundOverlay or custom tile overlay
    }
    
    private func updateMapStyle(_ mapView: MKMapView) {
        switch state.mapStyle {
        case .standard: mapView.mapType = .standard
        case .satellite: mapView.mapType = .satellite
        case .hybrid: mapView.mapType = .hybrid
        case .muted: mapView.mapType = .mutedStandard
        }
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapNativeView
        
        init(_ parent: MapNativeView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let aircraftAnn = annotation as? AircraftAnnotation {
                let view = MKMarkerAnnotationView(annotation: aircraftAnn, reuseIdentifier: "aircraft")
                view.marker// Altitude color coding
                view.marker.markerColor = aircraftAnn.aircraft.altitudeColor
                view.glyphImage = UIImage(systemName: aircraftPrcraft.type.icon)
                return view
            }
            
            if let satAnn = annotation as? SatelliteAnnotation {
                let view = MKAnnotationView(annotation: satAnn, reuseIdentifier: "sat")
                view.image = UIImage(systemName: "satellite.fill")
                return view
            }
            
            return nil
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .cyan
                renderer.lineWidth = 2.0
                return renderer
            }
            return MKOverlayRenderer()
        }
    }
}

// MARK: - Annotations

class AircraftAnnotation: MKPointAnnotation {
    let aircraft: Aircraft
    init(aircraft: Aircraft) {
        self.aircraft = aircraft
        super.init()
        self.coordinate = aircraft.coordinate
        self.title = aircraft.callsign
        self.subtitle = "Alt: \(aircraft.altitude)ft"
    }
}

class SatelliteAnnotation: MKPointAnnotation {
    let satellite: SatelliteTrack
    init(satellite: SatelliteTrack) {
        self.satellite = satellite
        super.init()
        self.coordinate = satellite.coordinate
        self.title = satellite.name
    }
}

// MARK: - UI Controls

struct MapControlPanel: View {
    @EnvironmentObject var mapState: MapState
    
    var body: some View {
        VStack(spacing: 10) {
            Button(action: { mapState.weatherOverlayEnabled.toggle() }) {
                Label("Weather Radar", systemImage: "cloud.rain.fill")
            }
            .buttonStyle(.bordered)
            .foregroundColor(mapState.weatherOverlayEnabled ? .blue : .primary)
            
            Picker("Style", selection: $mapState.mapStyle) {
                Text("Standard").tag(MapState.MapStyle.standard)
                Text("Satellite").tag(MapState.MapStyle.satellite)
                Text("Hybrid").tag(MapState.MapStyle.hybrid)
                Text("Muted").tag(MapState.MapStyle.muted)
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            
            Toggle("Show Orbits", isOn: $mapState.showOrbits)
                .font(.caption)
            
            Toggle("Show Tracks", isOn: $mapState.showGroundTracks)
                .font(.caption)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
        .cornerRadius(12)
        .shadow(radius: 4)
    }
}

struct SatellitePassList: View {
    @EnvironmentObject var mapState: MapState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Upcoming Passes")
                .font(.system(size: 12, weight: .bold))
            
            ForEach(mapState.trackedSatellites.filter { $0.nextPass != nil }) { sat in
                HStack {
                    VStack(alignment: .leading) {
                        Text(sat.name).font(.caption).bold()
                        Text("Max Elev: \(String(format: "%.1f°", sat.nextPass?.maxElevation ?? 0))")
                            .font(.system(size: 10))
                    }
                    Spacer()
                    Text(formatCountdown(sat.nextPass?.maxElevationTime))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.orange)
                }
                .padding(6)
                .background(Color.black.opacity(0.6))
                .cornerRadius(4)
                .foregroundColor(.white)
            }
        }
        .padding()
        .frame(width: 200)
        .background(Color.black.opacity(0.4))
        .cornerRadius(10)
    }
    
    private func formatCountdown(_ date: Date?) -> String {
        guard let date = date else { return "--:--" }
        let diff = Int(date.timeIntervalSinceNow)
        if diff <<  0 { return "Passing" }
        let mins = diff / 60
        let secs = diff % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
