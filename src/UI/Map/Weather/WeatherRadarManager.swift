//
//  WeatherRadarManager.swift
//  NeuralSDR2
//
//  Bridge between UAT hardware decoder and MapKit overlay
//

import Foundation
import MapKit

/// Manages the flow of weather data from UAT hardware to the map
public class WeatherRadarManager: ObservableObject {
    @Published var isEnabled: Bool = false
    @Published var currentReflectivity: [Float] = []
    
    private var uatDecoder: UATDecoder?
    private var assembler: FISBAssembler
    private var mapState: MapState
    
    public init(mapState: MapState) {
        self.mapState = mapState
        self.assembler = FISBAssembler()
    }
    
    /// Connect a UAT decoder to the manager
    public func setDecoder(_ decoder: UATDecoder) {
        self.uatDecoder = decoder
        decoder.onWeatherUpdate = { [weak self] frame in
            self?.handleFISBFrame(frame)
        }
    }
    
    private func handleFISBFrame(_ frame: FISBFrame) {
        // Pass the lap to the assembler
        if let fullImage = assembler.addFrame(frame) {
            DispatchQueue.main.async {
                self.currentReflectivity = fullImage
                self.mapState.weatherRadarData = WeatherRadarData(
                    timestamp: Date(),
                    reflectivityData: fullImage,
                    bounds: self.calculateBounds()
                )
            }
        }
    }
    
    private func calculateBounds() -> MKMapRect {
        // Calculate map rect based on current center and zoom
        // For now, return a default US-centered rect
        return MKMapRect(x: 0, y: 0, width: 1000000, height: 1000000)
    }
}
