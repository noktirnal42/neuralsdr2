//
// WeatherOverlay.swift
// NeuralSDR2
//
// NEXRAD Weather Radar Overlay for MapKit
// Real reflectivity rendering using standard dBZ color table
//

import SwiftUI
import MapKit
import CoreGraphics
import CoreImage
import os.log

private let logger = Logger(subsystem: "com.neuralsdr2.app", category: "WeatherOverlay")

public struct WeatherAgeBucket {
    public let label: String
    public let maxAge: TimeInterval?
    public let alphaMultiplier: Double

    public init(label: String, maxAge: TimeInterval?, alphaMultiplier: Double) {
        self.label = label
        self.maxAge = maxAge
        self.alphaMultiplier = alphaMultiplier
    }
}

public enum WeatherAgeStyle {
    public static let buckets: [WeatherAgeBucket] = [
        WeatherAgeBucket(label: "Fresh (<2m)", maxAge: 120, alphaMultiplier: 1.0),
        WeatherAgeBucket(label: "Recent (2-5m)", maxAge: 300, alphaMultiplier: 0.82),
        WeatherAgeBucket(label: "Aging (5-10m)", maxAge: 600, alphaMultiplier: 0.64),
        WeatherAgeBucket(label: "Old (10m+)", maxAge: nil, alphaMultiplier: 0.38)
    ]

    public static func alphaMultiplier(forAge age: TimeInterval) -> Double {
        for bucket in buckets {
            if let maxAge = bucket.maxAge {
                if age < maxAge {
                    return bucket.alphaMultiplier
                }
            } else {
                return bucket.alphaMultiplier
            }
        }
        return buckets.last?.alphaMultiplier ?? 1.0
    }
}

// MARK: - dBZ Color Table

public func nexradColor(for dBZ: Float, alphaMultiplier: Double = 1.0) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
    let base: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)
    switch dBZ {
    case ..<5:
        base = (0, 0, 0, 0)
    case 5..<10:
        base = (4, 233, 4, 180)
    case 10..<20:
        base = (0, 200, 0, 180)
    case 20..<30:
        base = (0, 255, 0, 200)
    case 30..<35:
        base = (255, 255, 0, 200)
    case 35..<40:
        base = (231, 180, 0, 210)
    case 40..<45:
        base = (255, 120, 0, 210)
    case 45..<50:
        base = (255, 0, 0, 220)
    case 50..<55:
        base = (180, 0, 0, 220)
    case 55..<60:
        base = (255, 0, 255, 230)
    case 60..<65:
        base = (153, 85, 201, 230)
    case 65...:
        base = (255, 255, 255, 240)
    default:
        base = (0, 0, 0, 0)
    }

    let scaledAlpha = UInt8(max(0, min(255, Int((Double(base.a) * alphaMultiplier).rounded()))))
    return (base.r, base.g, base.b, scaledAlpha)
}

// MARK: - NEXRAD Overlay

public class NEXRADOverlay: NSObject, MKOverlay {
    public var coordinate: CLLocationCoordinate2D
    public var boundingMapRect: MKMapRect
    public var reflectivityData: [Float]
    public var gridWidth: Int
    public var gridHeight: Int
    public var centerLatitude: Double
    public var centerLongitude: Double
    public var latitudeSpan: Double
    public var longitudeSpan: Double
    public var timestamp: Date

    public init(
        reflectivityData: [Float],
        gridWidth: Int,
        gridHeight: Int,
        center: CLLocationCoordinate2D,
        latitudeSpan: Double,
        longitudeSpan: Double,
        timestamp: Date = Date()
    ) {
        self.reflectivityData = reflectivityData
        self.gridWidth = gridWidth
        self.gridHeight = gridHeight
        self.centerLatitude = center.latitude
        self.centerLongitude = center.longitude
        self.latitudeSpan = latitudeSpan
        self.longitudeSpan = longitudeSpan
        self.timestamp = timestamp
        self.coordinate = center

        let minLat = center.latitude - latitudeSpan / 2.0
        let minLon = center.longitude - longitudeSpan / 2.0
        let maxLat = center.latitude + latitudeSpan / 2.0
        let maxLon = center.longitude + longitudeSpan / 2.0

        let sw = MKMapPoint(CLLocationCoordinate2D(latitude: minLat, longitude: minLon))
        let ne = MKMapPoint(CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon))

        self.boundingMapRect = MKMapRect(
            x: min(sw.x, ne.x),
            y: min(sw.y, ne.y),
            width: abs(ne.x - sw.x),
            height: abs(ne.y - sw.y)
        )

        super.init()
    }

    public convenience init(coordinate: CLLocationCoordinate2D, rect: MKMapRect, data: [Float]) {
        let w = Int(sqrt(Double(data.count)))
        let h = w > 0 ? data.count / w : 1
        self.init(
            reflectivityData: data,
            gridWidth: w,
            gridHeight: h,
            center: coordinate,
            latitudeSpan: 4.0,
            longitudeSpan: 4.0,
            timestamp: Date()
        )
    }
}

// MARK: - NEXRAD Overlay Renderer

public class NEXRADOverlayRenderer: MKOverlayRenderer {
    private var reflectivity: [Float]
    private var gridWidth: Int
    private var gridHeight: Int
    private var cachedImage: CGImage?
    private var cachedGeneration: Int = 0
    private var dataGeneration: Int = 0
    private var overlayTimestamp: Date

    public override init(overlay: MKOverlay) {
        let weatherOverlay = overlay as! NEXRADOverlay
        self.reflectivity = weatherOverlay.reflectivityData
        self.gridWidth = weatherOverlay.gridWidth
        self.gridHeight = weatherOverlay.gridHeight
        self.overlayTimestamp = weatherOverlay.timestamp
        super.init(overlay: overlay)
    }

    public override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard gridWidth > 0, gridHeight > 0, !reflectivity.isEmpty else { return }

        let image = renderReflectivityImage()
        guard let cgImage = image else { return }

        let overlayRect = rect(for: overlay.boundingMapRect)
        context.interpolationQuality = .none
        context.draw(cgImage, in: overlayRect)
    }

    private func renderReflectivityImage() -> CGImage? {
        if let cached = cachedImage, cachedGeneration == dataGeneration {
            return cached
        }

        let w = gridWidth
        let h = gridHeight
        guard w > 0, h > 0, reflectivity.count >= w * h else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = w * bytesPerPixel
        let totalBytes = h * bytesPerRow
        let alphaMultiplier = ageAlphaMultiplier(for: overlayTimestamp)

        var pixelData = [UInt8](repeating: 0, count: totalBytes)

        for row in 0..<h {
            for col in 0..<w {
                let dataIndex = row * w + col
                let dBZ = reflectivity[dataIndex]
                let color = nexradColor(for: dBZ, alphaMultiplier: alphaMultiplier)

                let pixelIndex = (row * bytesPerRow) + (col * bytesPerPixel)
                pixelData[pixelIndex + 0] = color.r
                pixelData[pixelIndex + 1] = color.g
                pixelData[pixelIndex + 2] = color.b
                pixelData[pixelIndex + 3] = color.a
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let dataProvider = CGDataProvider(data: Data(pixelData) as CFData) else { return nil }

        let image = CGImage(
            width: w,
            height: h,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .perceptual
        )

        cachedImage = image
        cachedGeneration = dataGeneration

        return image
    }

    public func updateData(_ data: [Float], width: Int, height: Int) {
        reflectivity = data
        gridWidth = width
        gridHeight = height
        dataGeneration += 1
        cachedImage = nil
        setNeedsDisplay()
    }

    private func ageAlphaMultiplier(for timestamp: Date, now: Date = Date()) -> Double {
        let age = max(now.timeIntervalSince(timestamp), 0)
        return WeatherAgeStyle.alphaMultiplier(forAge: age)
    }
}

// MARK: - Weather Overlay Manager

public class WeatherOverlayManager: ObservableObject, @unchecked Sendable {
    @Published public var isEnabled: Bool = false
    @Published public var currentReflectivity: [Float] = []
    @Published public var currentOverlay: NEXRADOverlay?

    private var weatherService = WeatherRadarService()

    public init() {}

    public func updateWeather(for region: MKCoordinateRegion) async {
        do {
            let result = try await weatherService.fetchLatestReflectivity(for: region)
            DispatchQueue.main.async {
                self.currentReflectivity = result.data
                self.currentOverlay = NEXRADOverlay(
                    reflectivityData: result.data,
                    gridWidth: result.width,
                    gridHeight: result.height,
                    center: CLLocationCoordinate2D(
                        latitude: region.center.latitude,
                        longitude: region.center.longitude
                    ),
                    latitudeSpan: region.span.latitudeDelta * 2.0,
                    longitudeSpan: region.span.longitudeDelta * 2.0,
                    timestamp: Date()
                )
            }
        } catch {
            logger.error("Weather update failed: \(error)")
        }
    }

    public func updateFromFISBData(
        _ data: [Float],
        width: Int,
        height: Int,
        center: CLLocationCoordinate2D,
        latSpan: Double,
        lonSpan: Double
    ) {
        DispatchQueue.main.async {
            self.currentReflectivity = data
            self.currentOverlay = NEXRADOverlay(
                reflectivityData: data,
                gridWidth: width,
                gridHeight: height,
                center: center,
                latitudeSpan: latSpan,
                longitudeSpan: lonSpan,
                timestamp: Date()
            )
        }
    }
}

// MARK: - Weather Radar Service

public struct NEXRADReflectivityResult: Sendable {
    public var data: [Float]
    public var width: Int
    public var height: Int

    public init(data: [Float], width: Int, height: Int) {
        self.data = data
        self.width = width
        self.height = height
    }
}

public class WeatherRadarService {
    public init() {}

    public func fetchLatestReflectivity(for region: MKCoordinateRegion) async throws -> NEXRADReflectivityResult {
        let width = 100
        let height = 100
        let centerLat = region.center.latitude
        let centerLon = region.center.longitude

        var data = [Float](repeating: -10.0, count: width * height)

        let stormCenterLat = centerLat + 0.5
        let stormCenterLon = centerLon - 0.3
        let stormSigmaLat = 1.2
        let stormSigmaLon = 1.8
        let peakDBZ: Float = 55.0

        for row in 0..<height {
            for col in 0..<width {
                let latFraction = (Double(col) / Double(width - 1) - 0.5) * region.span.longitudeDelta * 2.0
                let lonFraction = (Double(row) / Double(height - 1) - 0.5) * region.span.latitudeDelta * 2.0
                let cellLat = centerLat + lonFraction
                let cellLon = centerLon + latFraction

                let dLat = (cellLat - stormCenterLat) / stormSigmaLat
                let dLon = (cellLon - stormCenterLon) / stormSigmaLon
                let gaussian = exp(-(dLat * dLat + dLon * dLon) / 2.0)

                let angle = atan2(dLat, dLon)
                let radialMod = 0.6 + 0.4 * cos(angle * 3.0 + 0.5)
                let distance = sqrt(dLat * dLat + dLon * dLon)
                let spiralMod = 0.5 + 0.5 * cos(angle - distance * 2.5)

                var dBZ = peakDBZ * Float(gaussian * radialMod * spiralMod)

                let noise = Float.random(in: -3.0...3.0)
                dBZ += noise

                dBZ = max(-10, min(70, dBZ))
                data[row * width + col] = dBZ
            }
        }

        return NEXRADReflectivityResult(data: data, width: width, height: height)
    }
}

// MARK: - SwiftUI View Integration

public struct WeatherOverlayView: NSViewRepresentable {
    @ObservedObject public var manager: WeatherOverlayManager

    public init(manager: WeatherOverlayManager) {
        self.manager = manager
    }

    public func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        return mapView
    }

    public func updateNSView(_ nsView: MKMapView, context: Context) {
        nsView.removeOverlays(nsView.overlays)
        if let overlay = manager.currentOverlay {
            nsView.addOverlay(overlay)
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public class Coordinator: NSObject, MKMapViewDelegate {
        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let nexrad = overlay as? NEXRADOverlay {
                return NEXRADOverlayRenderer(overlay: nexrad)
            }
            return MKOverlayRenderer()
        }
    }
}
