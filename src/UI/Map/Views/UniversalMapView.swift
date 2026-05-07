//
//  UniversalMapView.swift
//  NeuralSDR2
//
//  Professional Universal Map for ADS-B, Satellites, and Weather
//  Utilizes MapKit for high-performance geospatial rendering
//

import SwiftUI
import MapKit

public struct UniversalMapView: View {

    public init() {}
    @EnvironmentObject var mapState: MapState
    @EnvironmentObject var appState: AppState
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 5.0, longitudeDelta: 5.0)
    )
    
    public var body: some View {
        ZStack {
            // Base MapKit View
            MapNativeView(region: $region, state: mapState, appState: appState)
                .edgesIgnoringSafeArea(.all)
            
            // Overlay Controls
            VStack {
                HStack {
                    MapControlPanel()
                    Spacer()
                    if selectedDecodedNOAAArtifact != nil {
                        DecodedNOAADetailDrawer()
                    }
                }
                Spacer()
                
                // Satellite Pass Notifications
                SatellitePassList()
            }
            .padding()
        }
    }

    private var selectedDecodedNOAAArtifact: APTDecodedArtifact? {
        guard let selectedID = mapState.selectedDecodedNOAAArtifactID else { return nil }
        return appState.decodedAPTArtifacts.first(where: { $0.imagePath == selectedID })
    }
}

// MARK: - Native MapKit Wrapper

public struct MapNativeView: NSViewRepresentable {
    @Binding public var region: MKCoordinateRegion
    @ObservedObject public var state: MapState
    @ObservedObject public var appState: AppState
    
    public func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.region = region
        context.coordinator.installInteraction(on: mapView)
        
        // Setup Map Style
        updateMapStyle(mapView)
        
        // Configure User Location
        mapView.showsUserLocation = false
        mapView.setRegion(region, animated: true)

        return mapView
    }
    
    public func updateNSView(_ nsView: MKMapView, context: Context) {
        // Update annotations and overlays
        syncUserLocationAnnotation(nsView, context: context)
        updateAnnotations(nsView)
        updateSatelliteTracks(nsView)
        updateDecodedNOAAOverlays(nsView)
        updateWeatherOverlay(nsView)
        syncUserLocation(nsView, context: context)
        syncDecodedNOAASelection(nsView)
        syncDecodedNOAAFocus(nsView, context: context)
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Annotation Logic
    
    private func updateAnnotations(_ mapView: MKMapView) {
        syncAircraftAnnotations(mapView)
        syncSatelliteAnnotations(mapView)
        syncDecodedNOAAAnnotations(mapView)
    }

    private func syncUserLocationAnnotation(_ mapView: MKMapView, context: Context) {
        let fallbackCoordinate = CLLocationCoordinate2D(
            latitude: state.observerLatitude,
            longitude: state.observerLongitude
        )
        let hasFallbackCoordinate = CLLocationCoordinate2DIsValid(fallbackCoordinate)
            && abs(fallbackCoordinate.latitude) > 0.0001
            && abs(fallbackCoordinate.longitude) > 0.0001
        let coordinate = state.userLocation ?? (hasFallbackCoordinate ? fallbackCoordinate : nil)

        guard let coordinate else {
            if let existing = context.coordinator.userLocationAnnotation {
                mapView.removeAnnotation(existing)
                context.coordinator.userLocationAnnotation = nil
            }
            return
        }

        let title = state.isUsingCurrentLocation ? "My Location" : "Observer"
        let subtitle: String?
        if state.userLocation != nil {
            subtitle = "Live device location"
        } else if state.isUsingCurrentLocation {
            subtitle = "Using observer fallback"
        } else {
            subtitle = "Manual observer location"
        }

        if let existing = context.coordinator.userLocationAnnotation {
            existing.update(coordinate: coordinate, title: title, subtitle: subtitle)
        } else {
            let annotation = UserLocationAnnotation(coordinate: coordinate, title: title, subtitle: subtitle)
            context.coordinator.userLocationAnnotation = annotation
            mapView.addAnnotation(annotation)
        }
    }

    private func syncAircraftAnnotations(_ mapView: MKMapView) {
        let existing: [String: AircraftAnnotation] = Dictionary(
            uniqueKeysWithValues: mapView.annotations.compactMap { annotation in
                guard let aircraftAnnotation = annotation as? AircraftAnnotation else { return nil }
                return (aircraftAnnotation.aircraft.icao, aircraftAnnotation)
            }
        )
        let desired = Dictionary(uniqueKeysWithValues: state.trackedAircraft.map { ($0.icao, $0) })

        let toRemove = existing.keys.filter { desired[$0] == nil }.compactMap { existing[$0] }
        if !toRemove.isEmpty {
            mapView.removeAnnotations(toRemove)
        }

        for aircraft in state.trackedAircraft {
            if let annotation = existing[aircraft.icao] {
                annotation.update(with: aircraft)
            } else {
                mapView.addAnnotation(AircraftAnnotation(aircraft: aircraft))
            }
        }
    }

    private func syncSatelliteAnnotations(_ mapView: MKMapView) {
        let existing: [String: SatelliteAnnotation] = Dictionary(
            uniqueKeysWithValues: mapView.annotations.compactMap { annotation in
                guard let satelliteAnnotation = annotation as? SatelliteAnnotation else { return nil }
                return (satelliteAnnotation.satellite.name, satelliteAnnotation)
            }
        )
        let desired = Dictionary(uniqueKeysWithValues: state.trackedSatellites.map { ($0.name, $0) })

        let toRemove = existing.keys.filter { desired[$0] == nil }.compactMap { existing[$0] }
        if !toRemove.isEmpty {
            mapView.removeAnnotations(toRemove)
        }

        for satellite in state.trackedSatellites {
            if let annotation = existing[satellite.name] {
                annotation.update(with: satellite)
            } else {
                mapView.addAnnotation(SatelliteAnnotation(satellite: satellite))
            }
        }
    }

    private func syncDecodedNOAAAnnotations(_ mapView: MKMapView) {
        let visibleArtifacts = state.decodedNOAAArtifacts.filter { $0.qualityTier.rank >= state.minimumNOAAQualityTier.rank }
        let existing: [String: DecodedNOAAAnnotation] = Dictionary(
            uniqueKeysWithValues: mapView.annotations.compactMap { annotation in
                guard let decodedAnnotation = annotation as? DecodedNOAAAnnotation else { return nil }
                return (decodedAnnotation.artifact.id, decodedAnnotation)
            }
        )
        let desired = Dictionary(uniqueKeysWithValues: visibleArtifacts.map { ($0.id, $0) })

        let toRemove = existing.keys.filter { desired[$0] == nil }.compactMap { existing[$0] }
        if !toRemove.isEmpty {
            mapView.removeAnnotations(toRemove)
        }

        for artifact in visibleArtifacts {
            if let annotation = existing[artifact.id] {
                annotation.update(with: artifact)
            } else {
                mapView.addAnnotation(DecodedNOAAAnnotation(artifact: artifact))
            }
        }
    }

    private func syncDecodedNOAASelection(_ mapView: MKMapView) {
        guard let selectedID = state.selectedDecodedNOAAArtifactID else {
            for annotation in mapView.selectedAnnotations.compactMap({ $0 as? DecodedNOAAAnnotation }) {
                mapView.deselectAnnotation(annotation, animated: false)
            }
            return
        }
        guard let annotation = mapView.annotations.compactMap({ $0 as? DecodedNOAAAnnotation }).first(where: { $0.artifact.id == selectedID }) else {
            return
        }
        if mapView.selectedAnnotations.contains(where: { ($0 as? DecodedNOAAAnnotation)?.artifact.id == selectedID }) == false {
            mapView.selectAnnotation(annotation, animated: false)
        }
    }

    private func syncDecodedNOAAFocus(_ mapView: MKMapView, context: Context) {
        guard context.coordinator.lastDecodedNOAAFocusRequestToken != state.decodedNOAAFocusRequestToken else {
            return
        }
        context.coordinator.lastDecodedNOAAFocusRequestToken = state.decodedNOAAFocusRequestToken
        guard let selectedID = state.selectedDecodedNOAAArtifactID,
              let overlay = mapView.overlays.compactMap({ $0 as? DecodedNOAAOverlay }).first(where: { $0.imagePath == selectedID }) else {
            return
        }

        let insetX = max(overlay.boundingMapRect.size.width * -0.25, -5000)
        let insetY = max(overlay.boundingMapRect.size.height * -0.25, -5000)
        let focusedRect = overlay.boundingMapRect.insetBy(dx: insetX, dy: insetY)
        mapView.setVisibleMapRect(
            focusedRect,
            edgePadding: NSEdgeInsets(top: 80, left: 80, bottom: 80, right: 80),
            animated: true
        )
    }
    
    private func updateSatelliteTracks(_ mapView: MKMapView) {
        let existingPolylines = mapView.overlays.compactMap { $0 as? MKPolyline }
        mapView.removeOverlays(existingPolylines)

        guard state.showGroundTracks else { return }

        // Render ground tracks as MKPolyline
        for sat in state.trackedSatellites {
            let polyline = MKPolyline(coordinates: sat.groundTrack, count: sat.groundTrack.count)
            mapView.addOverlay(polyline)
        }
    }

    private func updateDecodedNOAAOverlays(_ mapView: MKMapView) {
        let existing = mapView.overlays.compactMap { $0 as? DecodedNOAAOverlay }
        mapView.removeOverlays(existing)

        guard state.showDecodedNOAA else { return }

        for artifact in state.decodedNOAAArtifacts
        where artifact.samplePoints.count >= 2 && artifact.qualityTier.rank >= state.minimumNOAAQualityTier.rank {
            let overlay = DecodedNOAAOverlay(
                satellite: artifact.satellite,
                imagePath: artifact.imagePath,
                createdAt: artifact.createdAt,
                coordinates: artifact.samplePoints,
                estimatedSwathWidthKilometers: artifact.estimatedSwathWidthKilometers,
                qualityScore: artifact.qualityScore,
                qualityTier: artifact.qualityTier,
                isSelected: artifact.id == state.selectedDecodedNOAAArtifactID
            )
            mapView.addOverlay(overlay)
        }
    }
    
    private func updateWeatherOverlay(_ mapView: MKMapView) {
        let existingWeather = mapView.overlays.compactMap { $0 as? NEXRADOverlay }
        mapView.removeOverlays(existingWeather)

        guard state.weatherOverlayEnabled else { return }

        for weather in state.weatherRadarBlocks {
            let overlay = NEXRADOverlay(
                reflectivityData: weather.reflectivityData,
                gridWidth: weather.gridWidth,
                gridHeight: weather.gridHeight,
                center: weather.center,
                latitudeSpan: weather.latitudeSpan,
                longitudeSpan: weather.longitudeSpan,
                timestamp: weather.timestamp
            )
            mapView.addOverlay(overlay)
        }
    }
    
    private func updateMapStyle(_ mapView: MKMapView) {
        switch state.mapStyle {
        case .standard: mapView.mapType = .standard
        case .satellite: mapView.mapType = .satellite
        case .hybrid: mapView.mapType = .hybrid
        case .muted: mapView.mapType = .mutedStandard
        }
    }

    private func syncUserLocation(_ mapView: MKMapView, context: Context) {
        guard let userLocation = state.userLocation else { return }
        guard state.isUsingCurrentLocation else { return }
        guard context.coordinator.hasCenteredOnUserLocation == false else { return }

        context.coordinator.hasCenteredOnUserLocation = true
        let centeredRegion = MKCoordinateRegion(
            center: userLocation,
            latitudinalMeters: 180_000,
            longitudinalMeters: 180_000
        )
        mapView.setRegion(centeredRegion, animated: true)
        region = centeredRegion
    }
    
    public class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapNativeView
        var lastDecodedNOAAFocusRequestToken: Int = -1
        var hasCenteredOnUserLocation = false
        var userLocationAnnotation: UserLocationAnnotation?
        weak var mapView: MKMapView?
        
        init(_ parent: MapNativeView) {
            self.parent = parent
        }

        func installInteraction(on mapView: MKMapView) {
            self.mapView = mapView
            let clickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(handleMapClick(_:)))
            clickRecognizer.buttonMask = 0x1
            clickRecognizer.numberOfClicksRequired = 1
            mapView.addGestureRecognizer(clickRecognizer)
        }

        @objc private func handleMapClick(_ recognizer: NSClickGestureRecognizer) {
            guard let mapView = mapView else { return }
            let point = recognizer.location(in: mapView)

            if selectDecodedNOAAOverlay(at: point, in: mapView) {
                return
            }

            if let selectedID = parent.state.selectedDecodedNOAAArtifactID,
               mapView.annotations.compactMap({ $0 as? DecodedNOAAAnnotation }).contains(where: { $0.artifact.id == selectedID }) == false {
                parent.state.selectedDecodedNOAAArtifactID = nil
            }
        }

        private func selectDecodedNOAAOverlay(at point: CGPoint, in mapView: MKMapView) -> Bool {
            let overlays = mapView.overlays.compactMap { $0 as? DecodedNOAAOverlay }.reversed()
            for overlay in overlays {
                guard let renderer = mapView.renderer(for: overlay) as? DecodedNOAAOverlayRenderer else {
                    continue
                }
                if renderer.containsScreenPoint(point) {
                    parent.state.selectedDecodedNOAAArtifactID = overlay.imagePath
                    parent.appState.selectDecodedNOAAArtifact(id: overlay.imagePath)
                    if let annotation = mapView.annotations.compactMap({ $0 as? DecodedNOAAAnnotation }).first(where: { $0.artifact.id == overlay.imagePath }) {
                        mapView.selectAnnotation(annotation, animated: true)
                    }
                    return true
                }
            }
            return false
        }
        
        public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let userAnn = annotation as? UserLocationAnnotation {
                let identifier = "user-location"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: userAnn, reuseIdentifier: identifier)
                view.annotation = userAnn
                view.markerTintColor = .systemBlue
                view.glyphImage = NSImage(systemSymbolName: "location.fill", accessibilityDescription: "Your location")
                view.titleVisibility = .visible
                view.subtitleVisibility = .hidden
                view.displayPriority = .required
                view.canShowCallout = false
                return view
            }

            if let aircraftAnn = annotation as? AircraftAnnotation {
                let identifier = "aircraft"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: aircraftAnn, reuseIdentifier: identifier)
                view.annotation = aircraftAnn
                // Altitude color coding via markerTintColor — convert SwiftUI Color to NSColor
                view.markerTintColor = NSColor(aircraftAnn.aircraft.altitudeColor)
                view.glyphImage = NSImage(systemSymbolName: aircraftAnn.aircraft.type.icon, accessibilityDescription: "Aircraft")
                return view
            }

            if let satAnn = annotation as? SatelliteAnnotation {
                let identifier = "sat"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                    ?? MKAnnotationView(annotation: satAnn, reuseIdentifier: identifier)
                view.annotation = satAnn
                view.image = NSImage(systemSymbolName: "satellite.fill", accessibilityDescription: "Satellite")
                return view
            }

            if let decodedAnn = annotation as? DecodedNOAAAnnotation {
                let identifier = "decoded-noaa"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: decodedAnn, reuseIdentifier: identifier)
                view.annotation = decodedAnn
                switch decodedAnn.artifact.qualityTier {
                case .strong:
                    view.markerTintColor = .systemGreen
                    view.glyphImage = NSImage(systemSymbolName: "star.fill", accessibilityDescription: "Strong decoded NOAA")
                case .usable:
                    view.markerTintColor = .systemOrange
                    view.glyphImage = NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: "Usable decoded NOAA")
                case .weak:
                    view.markerTintColor = .systemRed
                    view.glyphImage = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Weak decoded NOAA")
                }
                view.alphaValue = decodedAnn.artifact.qualityTier == .weak ? 0.72 : 1.0
                view.canShowCallout = true
                return view
            }
            
            return nil
        }

        public func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let decodedAnn = view.annotation as? DecodedNOAAAnnotation {
                parent.state.selectedDecodedNOAAArtifactID = decodedAnn.artifact.id
                parent.appState.selectDecodedNOAAArtifact(id: decodedAnn.artifact.id)
            }
        }

        public func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            if view.annotation is DecodedNOAAAnnotation {
                parent.state.selectedDecodedNOAAArtifactID = nil
            }
        }
        
        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .cyan
                renderer.lineWidth = 2.0
                return renderer
            }
            if let decoded = overlay as? DecodedNOAAOverlay {
                return DecodedNOAAOverlayRenderer(overlay: decoded)
            }
            if let nexrad = overlay as? NEXRADOverlay {
                return NEXRADOverlayRenderer(overlay: nexrad)
            }
            return MKOverlayRenderer()
        }
    }
}

// MARK: - Annotations

public class UserLocationAnnotation: MKPointAnnotation {
    public init(coordinate: CLLocationCoordinate2D, title: String, subtitle: String? = nil) {
        super.init()
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
    }

    public func update(coordinate: CLLocationCoordinate2D, title: String, subtitle: String?) {
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
    }
}

public class AircraftAnnotation: MKPointAnnotation {
    public private(set) var aircraft: Aircraft
    public init(aircraft: Aircraft) {
        self.aircraft = aircraft
        super.init()
        self.coordinate = aircraft.coordinate
        self.title = aircraft.callsign
        self.subtitle = "Alt: \(aircraft.altitude)ft"
    }

    public func update(with aircraft: Aircraft) {
        self.aircraft = aircraft
        self.coordinate = aircraft.coordinate
        self.title = aircraft.callsign
        self.subtitle = "Alt: \(aircraft.altitude)ft"
    }
}

public class SatelliteAnnotation: MKPointAnnotation {
    public private(set) var satellite: SatelliteTrack
    public init(satellite: SatelliteTrack) {
        self.satellite = satellite
        super.init()
        self.coordinate = satellite.coordinate
        self.title = satellite.name
    }

    public func update(with satellite: SatelliteTrack) {
        self.satellite = satellite
        self.coordinate = satellite.coordinate
        self.title = satellite.name
    }
}

public class DecodedNOAAAnnotation: MKPointAnnotation {
    public private(set) var artifact: DecodedNOAAArtifact

    public init(artifact: DecodedNOAAArtifact) {
        self.artifact = artifact
        super.init()
        self.coordinate = artifact.centerCoordinate
        self.title = artifact.satellite
        self.subtitle = (artifact.imagePath as NSString).lastPathComponent
    }

    public func update(with artifact: DecodedNOAAArtifact) {
        self.artifact = artifact
        self.coordinate = artifact.centerCoordinate
        self.title = artifact.satellite
        self.subtitle = (artifact.imagePath as NSString).lastPathComponent
    }
}

// MARK: - UI Controls

public struct MapControlPanel: View {
    @EnvironmentObject var mapState: MapState
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var weatherRadarManager: WeatherRadarManager
    
    public var body: some View {
        VStack(spacing: 10) {
            Button(action: {
                appState.setWeatherOverlayEnabled(!mapState.weatherOverlayEnabled)
            }) {
                Label("Weather Radar", systemImage: "cloud.rain.fill")
            }
            .buttonStyle(.bordered)
            .foregroundColor(mapState.weatherOverlayEnabled ? .blue : .primary)

            if mapState.weatherOverlayEnabled {
                Text(weatherRadarManager.dump978StateDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 180, alignment: .leading)

                Text(weatherSummary)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 180, alignment: .leading)

                WeatherAgeLegend()
                    .frame(maxWidth: 180, alignment: .leading)

                Button("Reconnect dump978") {
                    appState.connectToDump978()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            
            Picker(
                "Style",
                selection: Binding(
                    get: { mapState.mapStyle },
                    set: { appState.setMapStyle($0) }
                )
            ) {
                Text("Standard").tag(MapState.MapStyle.standard)
                Text("Satellite").tag(MapState.MapStyle.satellite)
                Text("Hybrid").tag(MapState.MapStyle.hybrid)
                Text("Muted").tag(MapState.MapStyle.muted)
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            
            Toggle(
                "Show Orbits",
                isOn: Binding(
                    get: { mapState.showOrbits },
                    set: { appState.setShowOrbits($0) }
                )
            )
                .font(.caption)
            
            Toggle(
                "Show Tracks",
                isOn: Binding(
                    get: { mapState.showGroundTracks },
                    set: { appState.setShowGroundTracks($0) }
                )
            )
                .font(.caption)

            Toggle(
                "Decoded NOAA",
                isOn: Binding(
                    get: { mapState.showDecodedNOAA },
                    set: { appState.setShowDecodedNOAA($0) }
                )
            )
                .font(.caption)

            Picker(
                "NOAA Filter",
                selection: Binding(
                    get: { mapState.minimumNOAAQualityTier },
                    set: { appState.setMinimumNOAAQualityTier($0) }
                )
            ) {
                Text("All").tag(NOAAArtifactQualityTier.weak)
                Text("Usable+").tag(NOAAArtifactQualityTier.usable)
                Text("Strong").tag(NOAAArtifactQualityTier.strong)
            }
            .pickerStyle(.menu)
            .controlSize(.small)

            if let selectedArtifact = selectedDecodedNOAAArtifact,
               let selectedMapArtifact = selectedDecodedNOAAMapArtifact {
                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected NOAA")
                        .font(.caption.weight(.semibold))
                    Text(selectedArtifact.satellite)
                        .font(.caption)
                    Text((selectedArtifact.imagePath as NSString).lastPathComponent)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(selectedArtifact.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(
                        String(
                            format: "Swath %.0f km • sync %.2f • jitter %.1f",
                            selectedMapArtifact.estimatedSwathWidthKilometers,
                            selectedArtifact.syncQuality,
                            selectedArtifact.lineJitter
                        )
                    )
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Button("Open") {
                            appState.selectDecodedNOAAArtifact(id: selectedArtifact.imagePath)
                            appState.executePostPassAction(
                                PostPassActionItem(
                                    satellite: selectedArtifact.satellite,
                                    preset: .noaaAPT,
                                    recordingKind: .audio,
                                    filePath: selectedArtifact.imagePath,
                                    actionLabel: "Open decoded APT image",
                                    detailText: nil,
                                    sourceFilePath: selectedArtifact.sourcePath,
                                    createdAt: selectedArtifact.createdAt
                                )
                            )
                        }
                        .buttonStyle(.borderless)

                        Button("Recordings") {
                            appState.selectDecodedNOAAArtifact(id: selectedArtifact.imagePath)
                        }
                        .buttonStyle(.borderless)

                        Button("Zoom") {
                            appState.focusDecodedNOAAArtifact(id: selectedArtifact.imagePath)
                        }
                        .buttonStyle(.borderless)
                    }

                    HStack(spacing: 6) {
                        Button("Ch A") {
                            appState.openAPTChannelImage(selectedArtifact, channel: 1)
                        }
                        .buttonStyle(.borderless)

                        Button("Clear") {
                            mapState.selectedDecodedNOAAArtifactID = nil
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .frame(maxWidth: 180, alignment: .leading)
            }
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
        .cornerRadius(12)
        .shadow(radius: 4)
    }

    private var weatherSummary: String {
        let blockLabel = weatherRadarManager.weatherBlockCount == 1 ? "1 block" : "\(weatherRadarManager.weatherBlockCount) blocks"
        guard let lastUpdate = weatherRadarManager.lastWeatherUpdate else {
            return "\(blockLabel) loaded"
        }

        let age = max(Int(Date().timeIntervalSince(lastUpdate)), 0)
        if age < 60 {
            return "\(blockLabel) • updated \(age)s ago"
        }
        return "\(blockLabel) • updated \(age / 60)m ago"
    }

    private var selectedDecodedNOAAArtifact: APTDecodedArtifact? {
        guard let selectedID = mapState.selectedDecodedNOAAArtifactID else { return nil }
        return filteredDecodedAPTArtifacts.first(where: { $0.imagePath == selectedID })
    }

    private var selectedDecodedNOAAMapArtifact: DecodedNOAAArtifact? {
        guard let selectedID = mapState.selectedDecodedNOAAArtifactID else { return nil }
        return filteredDecodedNOAAMapArtifacts.first(where: { $0.id == selectedID })
    }

    private var filteredDecodedAPTArtifacts: [APTDecodedArtifact] {
        appState.decodedAPTArtifacts.filter {
            appState.noaaArtifactQualityTier($0).rank >= mapState.minimumNOAAQualityTier.rank
        }
    }

    private var filteredDecodedNOAAMapArtifacts: [DecodedNOAAArtifact] {
        mapState.decodedNOAAArtifacts.filter {
            $0.qualityTier.rank >= mapState.minimumNOAAQualityTier.rank
        }
    }
}

public final class DecodedNOAAOverlay: NSObject, MKOverlay {
    public let coordinate: CLLocationCoordinate2D
    public let boundingMapRect: MKMapRect
    public let satellite: String
    public let imagePath: String
    public let createdAt: Date
    public let polyline: MKPolyline
    public let polygon: MKPolygon
    public let estimatedSwathWidthKilometers: Double
    public let qualityScore: Double
    public let qualityTier: NOAAArtifactQualityTier
    public let isSelected: Bool

    public init(
        satellite: String,
        imagePath: String,
        createdAt: Date,
        coordinates: [CLLocationCoordinate2D],
        estimatedSwathWidthKilometers: Double,
        qualityScore: Double,
        qualityTier: NOAAArtifactQualityTier,
        isSelected: Bool
    ) {
        self.satellite = satellite
        self.imagePath = imagePath
        self.createdAt = createdAt
        self.polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        self.estimatedSwathWidthKilometers = estimatedSwathWidthKilometers
        self.qualityScore = qualityScore
        self.qualityTier = qualityTier
        self.isSelected = isSelected
        let polygonCoordinates = Self.makeSwathPolygon(
            coordinates: coordinates,
            halfWidthKilometers: estimatedSwathWidthKilometers / 2.0
        )
        self.polygon = MKPolygon(coordinates: polygonCoordinates, count: polygonCoordinates.count)
        self.coordinate = coordinates[coordinates.count / 2]
        self.boundingMapRect = polygon.boundingMapRect
        super.init()
    }

    private static func makeSwathPolygon(
        coordinates: [CLLocationCoordinate2D],
        halfWidthKilometers: Double
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count >= 2 else { return coordinates }

        let halfWidthDegreesLat = halfWidthKilometers / 111.0
        var leftSide: [CLLocationCoordinate2D] = []
        var rightSide: [CLLocationCoordinate2D] = []
        leftSide.reserveCapacity(coordinates.count)
        rightSide.reserveCapacity(coordinates.count)

        for index in coordinates.indices {
            let current = coordinates[index]
            let previous = coordinates[max(index - 1, 0)]
            let next = coordinates[min(index + 1, coordinates.count - 1)]
            let dx = next.longitude - previous.longitude
            let dy = next.latitude - previous.latitude
            let length = max(sqrt(dx * dx + dy * dy), 0.000001)
            let nx = -dy / length
            let ny = dx / length
            let lonScale = max(cos(current.latitude * .pi / 180.0), 0.2)
            let halfWidthDegreesLon = halfWidthDegreesLat / lonScale

            leftSide.append(
                CLLocationCoordinate2D(
                    latitude: current.latitude + ny * halfWidthDegreesLat,
                    longitude: current.longitude + nx * halfWidthDegreesLon
                )
            )
            rightSide.append(
                CLLocationCoordinate2D(
                    latitude: current.latitude - ny * halfWidthDegreesLat,
                    longitude: current.longitude - nx * halfWidthDegreesLon
                )
            )
        }

        return leftSide + rightSide.reversed()
    }
}

public final class DecodedNOAAOverlayRenderer: MKOverlayPathRenderer {
    private let polylineRenderer: MKPolylineRenderer
    private let polygonRenderer: MKPolygonRenderer

    public override init(overlay: MKOverlay) {
        let decoded = overlay as! DecodedNOAAOverlay
        self.polylineRenderer = MKPolylineRenderer(polyline: decoded.polyline)
        self.polygonRenderer = MKPolygonRenderer(polygon: decoded.polygon)
        super.init(overlay: overlay)
        let baseColor: NSColor
        switch decoded.qualityTier {
        case .strong:
            baseColor = .systemGreen
        case .usable:
            baseColor = .systemOrange
        case .weak:
            baseColor = .systemRed
        }
        let tierAlphaScale: CGFloat
        switch decoded.qualityTier {
        case .strong:
            tierAlphaScale = 1.0
        case .usable:
            tierAlphaScale = 0.86
        case .weak:
            tierAlphaScale = 0.62
        }
        let strokeAlpha: CGFloat = (decoded.isSelected ? 0.95 : 0.82) * tierAlphaScale
        let fillAlpha: CGFloat = (decoded.isSelected ? 0.30 : 0.15) * tierAlphaScale
        self.polylineRenderer.strokeColor = baseColor.withAlphaComponent(strokeAlpha)
        self.polylineRenderer.lineWidth = decoded.isSelected ? 4.0 : (decoded.qualityTier == .weak ? 2.0 : 3.0)
        self.polylineRenderer.lineDashPattern = decoded.isSelected ? [8, 3] : (decoded.qualityTier == .strong ? [5, 3] : [6, 4])
        self.polygonRenderer.fillColor = baseColor.withAlphaComponent(fillAlpha)
        self.polygonRenderer.strokeColor = baseColor.withAlphaComponent((decoded.isSelected ? 0.78 : 0.42) * tierAlphaScale)
        self.polygonRenderer.lineWidth = decoded.isSelected ? 2.0 : (decoded.qualityTier == .weak ? 0.8 : 1.0)
    }

    public override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        polygonRenderer.draw(mapRect, zoomScale: zoomScale, in: context)
        polylineRenderer.draw(mapRect, zoomScale: zoomScale, in: context)
    }

    public func containsScreenPoint(_ point: CGPoint) -> Bool {
        let mapPoint = self.point(for: MKMapPoint(overlay.coordinate))
        let offset = CGPoint(x: point.x - mapPoint.x, y: point.y - mapPoint.y)
        guard let polygonPath = polygonRenderer.path else { return false }
        if polygonPath.contains(offset) {
            return true
        }
        guard let polylinePath = polylineRenderer.path else { return false }
        let stroked = polylinePath.copy(
            strokingWithWidth: max(polylineRenderer.lineWidth + 10.0, 14.0),
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 0
        )
        return stroked.contains(offset)
    }
}

private struct WeatherAgeLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Weather Age")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)

            ForEach(WeatherAgeStyle.buckets, id: \.label) { row in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.green.opacity(row.alphaMultiplier))
                        .frame(width: 14, height: 8)
                    Text(row.label)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.top, 2)
    }
}

private struct DecodedNOAADetailDrawer: View {
    @EnvironmentObject var mapState: MapState
    @EnvironmentObject var appState: AppState
    @State private var selectedPreviewChannel: PreviewChannel = .combined

    var body: some View {
        if let artifact = selectedDecodedNOAAArtifact,
           let mapArtifact = selectedDecodedNOAAMapArtifact {
            VStack(alignment: .leading, spacing: 10) {
                Text("NOAA Preview")
                    .font(.headline)

                Picker("Channel", selection: $selectedPreviewChannel) {
                    ForEach(PreviewChannel.allCases, id: \.self) { channel in
                        Text(channel.rawValue).tag(channel)
                    }
                }
                .pickerStyle(.segmented)

                if let previewImage = NSImage(contentsOfFile: previewImagePath(for: artifact)) {
                    Image(nsImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 260, height: 180)
                        .background(Color.black.opacity(0.18))
                        .cornerRadius(8)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.12))
                        .frame(width: 260, height: 180)
                        .overlay(
                            Text("Preview unavailable")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(artifact.satellite)
                        .font(.subheadline)
                    HStack(spacing: 6) {
                        NOAAArtifactQualityTag(
                            tier: appState.noaaArtifactQualityTier(artifact),
                            score: appState.noaaArtifactQualityScore(artifact)
                        )
                        if appState.noaaArtifactQualityTier(artifact) == .weak {
                            Text("Weak pass")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.red)
                        }
                    }
                    Text((artifact.imagePath as NSString).lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(artifact.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("View: \(selectedPreviewChannel.rawValue)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    NOAAQualityBadgeRow(
                        badges: [
                            qualityBadge(
                                label: "Sync",
                                valueText: String(format: "%.2f", artifact.syncQuality),
                                classification: artifact.syncQuality >= 0.75 ? .good : (artifact.syncQuality >= 0.45 ? .fair : .poor)
                            ),
                            qualityBadge(
                                label: "Telem",
                                valueText: String(format: "%.2f", artifact.telemetryContrast),
                                classification: artifact.telemetryContrast >= 0.18 ? .good : (artifact.telemetryContrast >= 0.08 ? .fair : .poor)
                            ),
                            qualityBadge(
                                label: "Cal",
                                valueText: String(format: "%.2f", artifact.calibrationSpread),
                                classification: artifact.calibrationSpread >= 0.22 ? .good : (artifact.calibrationSpread >= 0.10 ? .fair : .poor)
                            )
                        ]
                    )
                    NOAAQualityBadgeRow(
                        badges: [
                            qualityBadge(
                                label: "Sep",
                                valueText: String(format: "%.2f", artifact.channelSeparation),
                                classification: artifact.channelSeparation >= 0.12 ? .good : (artifact.channelSeparation >= 0.05 ? .fair : .poor)
                            ),
                            qualityBadge(
                                label: "Jitter",
                                valueText: String(format: "%.1f", artifact.lineJitter),
                                classification: artifact.lineJitter <= 12 ? .good : (artifact.lineJitter <= 30 ? .fair : .poor)
                            ),
                            qualityBadge(
                                label: "Bal",
                                valueText: String(format: "%+.2f", artifact.channelBalance),
                                classification: abs(artifact.channelBalance) <= 0.18 ? .good : (abs(artifact.channelBalance) <= 0.35 ? .fair : .poor)
                            )
                        ]
                    )
                    Text(
                        String(
                            format: "Swath %.0f km • sync %.2f • jitter %.1f • telem %.2f",
                            mapArtifact.estimatedSwathWidthKilometers,
                            artifact.syncQuality,
                            artifact.lineJitter,
                            artifact.telemetryContrast
                        )
                    )
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    if let coverage = artifact.coverageSummary {
                        Text(
                            "Obs \(coverage.observerLatitude, specifier: "%.2f"), \(coverage.observerLongitude, specifier: "%.2f")"
                        )
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        if let first = coverage.firstLine, let last = coverage.lastLine {
                            Text(
                                "Track \(first.latitude, specifier: "%.1f"), \(first.longitude, specifier: "%.1f") → \(last.latitude, specifier: "%.1f"), \(last.longitude, specifier: "%.1f")"
                            )
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button("Open") {
                        appState.executePostPassAction(
                            PostPassActionItem(
                                satellite: artifact.satellite,
                                preset: .noaaAPT,
                                recordingKind: .audio,
                                filePath: artifact.imagePath,
                                actionLabel: "Open decoded APT image",
                                detailText: nil,
                                sourceFilePath: artifact.sourcePath,
                                createdAt: artifact.createdAt
                            )
                        )
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Zoom") {
                        appState.focusDecodedNOAAArtifact(id: artifact.imagePath)
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 8) {
                    Button("Ch A") {
                        selectedPreviewChannel = .channelA
                        appState.openAPTChannelImage(artifact, channel: 1)
                    }
                    .buttonStyle(.bordered)

                    Button("Ch B") {
                        selectedPreviewChannel = .channelB
                        appState.openAPTChannelImage(artifact, channel: 2)
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 8) {
                    Button("Source") {
                        NSWorkspace.shared.open(artifact.sourceURL)
                    }
                    .buttonStyle(.bordered)

                    Button("Recordings") {
                        appState.selectDecodedNOAAArtifact(id: artifact.imagePath)
                    }
                    .buttonStyle(.bordered)
                }

                Button("Close") {
                    mapState.selectedDecodedNOAAArtifactID = nil
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding()
            .frame(width: 290, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
            .cornerRadius(14)
            .shadow(radius: 6)
            .onChange(of: artifact.imagePath) { _ in
                selectedPreviewChannel = .combined
            }
        }
    }

    private func previewImagePath(for artifact: APTDecodedArtifact) -> String {
        switch selectedPreviewChannel {
        case .combined:
            return artifact.imagePath
        case .channelA:
            return artifact.channelAImagePath
        case .channelB:
            return artifact.channelBImagePath
        }
    }

    private var selectedDecodedNOAAArtifact: APTDecodedArtifact? {
        guard let selectedID = mapState.selectedDecodedNOAAArtifactID else { return nil }
        return appState.decodedAPTArtifacts.first(where: { $0.imagePath == selectedID })
    }

    private var selectedDecodedNOAAMapArtifact: DecodedNOAAArtifact? {
        guard let selectedID = mapState.selectedDecodedNOAAArtifactID else { return nil }
        return mapState.decodedNOAAArtifacts.first(where: { $0.id == selectedID })
    }

    private func qualityBadge(label: String, valueText: String, classification: NOAAQualityClassification) -> NOAAQualityBadge {
        NOAAQualityBadge(label: label, valueText: valueText, classification: classification)
    }

    private enum PreviewChannel: String, CaseIterable {
        case combined = "Combined"
        case channelA = "Ch A"
        case channelB = "Ch B"
    }
}

private struct NOAAQualityBadgeRow: View {
    let badges: [NOAAQualityBadge]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(badges, id: \.label) { badge in
                VStack(alignment: .leading, spacing: 1) {
                    Text(badge.label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(badge.valueText)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(badge.classification.fillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(badge.classification.strokeColor, lineWidth: 1)
                )
                .cornerRadius(7)
            }
        }
    }
}

private struct NOAAArtifactQualityTag: View {
    let tier: NOAAArtifactQualityTier
    let score: Double

    var body: some View {
        Text("\(tier.rawValue) \(Int((score * 100).rounded()))")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(fillColor)
            .foregroundColor(strokeColor)
            .overlay(
                Capsule()
                    .stroke(strokeColor.opacity(0.35), lineWidth: 1)
            )
            .clipShape(Capsule())
    }

    private var fillColor: Color {
        switch tier {
        case .strong:
            return Color.green.opacity(0.16)
        case .usable:
            return Color.orange.opacity(0.16)
        case .weak:
            return Color.red.opacity(0.16)
        }
    }

    private var strokeColor: Color {
        switch tier {
        case .strong:
            return .green
        case .usable:
            return .orange
        case .weak:
            return .red
        }
    }
}

private struct NOAAQualityBadge {
    let label: String
    let valueText: String
    let classification: NOAAQualityClassification
}

private enum NOAAQualityClassification {
    case good
    case fair
    case poor

    var fillColor: Color {
        switch self {
        case .good:
            return Color.green.opacity(0.14)
        case .fair:
            return Color.orange.opacity(0.14)
        case .poor:
            return Color.red.opacity(0.14)
        }
    }

    var strokeColor: Color {
        switch self {
        case .good:
            return Color.green.opacity(0.45)
        case .fair:
            return Color.orange.opacity(0.45)
        case .poor:
            return Color.red.opacity(0.45)
        }
    }
}

public struct SatellitePassList: View {
    @EnvironmentObject var mapState: MapState
    
    public var body: some View {
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
if diff < 0 { return "Passing" }
        let mins = diff / 60
        let secs = diff % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
