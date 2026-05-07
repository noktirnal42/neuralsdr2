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
    @Published public var isEnabled: Bool = false
    @Published public var currentReflectivity: [Float] = []
    @Published public var dump978StateDescription: String = "Disconnected"
    @Published public var weatherBlockCount: Int = 0
    @Published public var lastWeatherUpdate: Date?
    
    private var uatDecoder: UATDecoder?
    private var assembler: FISBAssembler
    private var mapState: MapState
    private let dump978Client = Dump978RawClient()
    private var blockStore: [String: WeatherRadarData] = [:]
    private var cleanupTimer: Timer?

    public var dump978Host: String = "127.0.0.1"
    public var dump978RawPort: UInt16 = 30978
    
    public init(mapState: MapState) {
        self.mapState = mapState
        self.assembler = FISBAssembler()
        configureDump978Client()
    }
    
    /// Connect a UAT decoder to the manager
    public func setDecoder(_ decoder: UATDecoder) {
        self.uatDecoder = decoder
        decoder.onWeatherUpdate = { [weak self] frame in
            self?.handleFISBFrame(frame)
        }
        decoder.onNEXRADBlock = { [weak self] block in
            self?.handleNEXRADBlock(block)
        }
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            startCleanupTimer()
            connectToDump978()
        } else {
            stopCleanupTimer()
            dump978Client.disconnect()
            DispatchQueue.main.async {
                self.mapState.weatherRadarData = nil
                self.mapState.weatherRadarBlocks = []
                self.currentReflectivity = []
                self.weatherBlockCount = 0
                self.lastWeatherUpdate = nil
            }
            blockStore.removeAll()
        }
    }

    public func connectToDump978(host: String? = nil, port: UInt16? = nil) {
        if let host {
            dump978Host = host
        }
        if let port {
            dump978RawPort = port
        }
        dump978Client.connect(host: dump978Host, port: dump978RawPort)
    }
    
    private func handleFISBFrame(_ frame: FISBFrame) {
        if let fullImage = assembler.addFrame(frame) {
            DispatchQueue.main.async {
                self.currentReflectivity = fullImage
            }
        }
    }

    private func configureDump978Client() {
        dump978Client.onStateChanged = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .disconnected:
                    self?.dump978StateDescription = "Disconnected"
                case .connecting:
                    self?.dump978StateDescription = "Connecting to dump978"
                case .connected:
                    self?.dump978StateDescription = "Connected to dump978"
                case .failed(let message):
                    self?.dump978StateDescription = "dump978 error: \(message)"
                }
            }
        }

        dump978Client.onMessage = { [weak self] line in
            self?.handleDump978Line(line)
        }
    }

    private func handleDump978Line(_ line: String) {
        if uatDecoder == nil {
            let decoder = UATDecoder(sampleRate: 2_083_334)
            setDecoder(decoder)
        }
        uatDecoder?.ingestDump978RawLine(line)
    }

    private func handleNEXRADBlock(_ block: FISBNEXRADBlock) {
        let centerLat = block.latitudeNorth - block.latitudeSize / 2.0
        let centerLon = block.longitudeWest + block.longitudeSize / 2.0
        let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        let minLat = block.latitudeNorth - block.latitudeSize
        let minLon = block.longitudeWest
        let maxLat = block.latitudeNorth
        let maxLon = block.longitudeWest + block.longitudeSize
        let sw = MKMapPoint(CLLocationCoordinate2D(latitude: minLat, longitude: minLon))
        let ne = MKMapPoint(CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon))
        let bounds = MKMapRect(
            x: min(sw.x, ne.x),
            y: min(sw.y, ne.y),
            width: abs(ne.x - sw.x),
            height: abs(ne.y - sw.y)
        )
        let weatherBlock = WeatherRadarData(
            timestamp: block.timestamp,
            key: block.key,
            reflectivityData: block.bins,
            bounds: bounds,
            gridWidth: 32,
            gridHeight: 4,
            center: center,
            latitudeSpan: block.latitudeSize,
            longitudeSpan: block.longitudeSize,
            source: "dump978"
        )

        upsertWeatherBlock(weatherBlock, referenceTime: block.timestamp)
    }

    func upsertWeatherBlock(_ weatherBlock: WeatherRadarData, referenceTime: Date? = nil) {
        blockStore[weatherBlock.key] = weatherBlock
        refreshDisplayedWeather(referenceTime: referenceTime ?? weatherBlock.timestamp)
    }

    func refreshDisplayedWeather(referenceTime: Date = Date()) {
        purgeOldBlocks(reference: referenceTime)
        let sortedBlocks = compositedBlocks()
        let mostRecentTimestamp = sortedBlocks.map(\.timestamp).max()

        DispatchQueue.main.async {
            self.mapState.weatherRadarBlocks = sortedBlocks
            self.mapState.weatherRadarData = sortedBlocks.last
            self.weatherBlockCount = sortedBlocks.count
            self.lastWeatherUpdate = mostRecentTimestamp
        }
    }

    private func purgeOldBlocks(reference: Date) {
        let maxAge: TimeInterval = 20 * 60
        blockStore = blockStore.filter { _, block in
            reference.timeIntervalSince(block.timestamp) <= maxAge
        }
    }

    private func compositedBlocks() -> [WeatherRadarData] {
        let referenceTime = blockStore.values.map(\.timestamp).max() ?? Date()
        let sortedBlocks = blockStore.values.sorted { lhs, rhs in
            let leftPriority = renderPriority(for: lhs, referenceTime: referenceTime)
            let rightPriority = renderPriority(for: rhs, referenceTime: referenceTime)
            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.key < rhs.key
        }

        return applyOverlapMask(to: sortedBlocks)
    }

    private func selectionPriority(for block: WeatherRadarData, referenceTime: Date) -> Int {
        var priority = 0
        if block.source == "dump978" {
            priority += 100
        }
        if block.longitudeSpan <= 1.0 {
            priority += 20
        } else if block.longitudeSpan <= 2.0 {
            priority += 10
        }
        priority += freshnessPriority(for: block, referenceTime: referenceTime)
        return priority
    }

    private func freshnessPriority(for block: WeatherRadarData, referenceTime: Date) -> Int {
        let age = max(referenceTime.timeIntervalSince(block.timestamp), 0)
        switch age {
        case ..<120:
            return 15
        case ..<300:
            return 10
        case ..<600:
            return 5
        default:
            return 0
        }
    }

    private func renderPriority(for block: WeatherRadarData, referenceTime: Date) -> Int {
        selectionPriority(for: block, referenceTime: referenceTime)
    }

    private func applyOverlapMask(to blocks: [WeatherRadarData]) -> [WeatherRadarData] {
        guard blocks.count > 1 else { return blocks }
        let referenceTime = blocks.map(\.timestamp).max() ?? Date()

        let prioritized = blocks.enumerated().sorted { lhs, rhs in
            let left = lhs.element
            let right = rhs.element
            let leftPriority = renderPriority(for: left, referenceTime: referenceTime)
            let rightPriority = renderPriority(for: right, referenceTime: referenceTime)
            if leftPriority != rightPriority {
                return leftPriority > rightPriority
            }
            if left.timestamp != right.timestamp {
                return left.timestamp > right.timestamp
            }
            return left.key > right.key
        }

        var processed: [Int: WeatherRadarData] = [:]
        var higherPriorityBlocks: [WeatherRadarData] = []

        for (originalIndex, block) in prioritized {
            let masked = maskedBlock(block, against: higherPriorityBlocks)
            if hasVisibleWeather(masked) {
                processed[originalIndex] = masked
                higherPriorityBlocks.append(masked)
            }
        }

        return blocks.enumerated().compactMap { index, block in
            if let processedBlock = processed[index] {
                return processedBlock
            }
            return higherPriorityBlocks.contains(where: { $0.key == block.key }) ? block : nil
        }
    }

    private func maskedBlock(_ block: WeatherRadarData, against higherPriorityBlocks: [WeatherRadarData]) -> WeatherRadarData {
        guard !higherPriorityBlocks.isEmpty else { return block }

        var maskedData = block.reflectivityData
        let transparencyValue: Float = 0

        for row in 0..<block.gridHeight {
            for col in 0..<block.gridWidth {
                let index = row * block.gridWidth + col
                guard index < maskedData.count else { continue }
                guard maskedData[index] >= 5 else { continue }

                let coordinate = coordinateForCell(row: row, col: col, in: block)
                if higherPriorityBlocks.contains(where: { coversVisibleWeather(at: coordinate, in: $0) }) {
                    maskedData[index] = transparencyValue
                }
            }
        }

        return WeatherRadarData(
            timestamp: block.timestamp,
            key: block.key,
            reflectivityData: maskedData,
            bounds: block.bounds,
            gridWidth: block.gridWidth,
            gridHeight: block.gridHeight,
            center: block.center,
            latitudeSpan: block.latitudeSpan,
            longitudeSpan: block.longitudeSpan,
            source: block.source
        )
    }

    private func coversVisibleWeather(at coordinate: CLLocationCoordinate2D, in block: WeatherRadarData) -> Bool {
        guard contains(coordinate: coordinate, in: block) else { return false }

        let lonStep = block.longitudeSpan / Double(block.gridWidth)
        let latStep = block.latitudeSpan / Double(block.gridHeight)
        guard lonStep > 0, latStep > 0 else { return false }

        let west = block.center.longitude - block.longitudeSpan / 2.0
        let north = block.center.latitude + block.latitudeSpan / 2.0

        let col = Int(((coordinate.longitude - west) / lonStep).rounded(.down))
        let row = Int(((north - coordinate.latitude) / latStep).rounded(.down))

        guard row >= 0, row < block.gridHeight, col >= 0, col < block.gridWidth else { return false }

        let index = row * block.gridWidth + col
        guard index < block.reflectivityData.count else { return false }
        return block.reflectivityData[index] >= 5
    }

    private func contains(coordinate: CLLocationCoordinate2D, in block: WeatherRadarData) -> Bool {
        let minLat = block.center.latitude - block.latitudeSpan / 2.0
        let maxLat = block.center.latitude + block.latitudeSpan / 2.0
        let minLon = block.center.longitude - block.longitudeSpan / 2.0
        let maxLon = block.center.longitude + block.longitudeSpan / 2.0
        return coordinate.latitude >= minLat &&
            coordinate.latitude <= maxLat &&
            coordinate.longitude >= minLon &&
            coordinate.longitude <= maxLon
    }

    private func coordinateForCell(row: Int, col: Int, in block: WeatherRadarData) -> CLLocationCoordinate2D {
        let lonStep = block.longitudeSpan / Double(block.gridWidth)
        let latStep = block.latitudeSpan / Double(block.gridHeight)
        let west = block.center.longitude - block.longitudeSpan / 2.0
        let north = block.center.latitude + block.latitudeSpan / 2.0

        return CLLocationCoordinate2D(
            latitude: north - (Double(row) + 0.5) * latStep,
            longitude: west + (Double(col) + 0.5) * lonStep
        )
    }

    private func hasVisibleWeather(_ block: WeatherRadarData) -> Bool {
        block.reflectivityData.contains(where: { $0 >= 5 })
    }

    private func startCleanupTimer() {
        guard cleanupTimer == nil else { return }
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.refreshDisplayedWeather(referenceTime: Date())
        }
    }

    private func stopCleanupTimer() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }

    deinit {
        stopCleanupTimer()
    }
}
