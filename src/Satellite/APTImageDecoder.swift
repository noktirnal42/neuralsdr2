import Foundation
import AppKit
import CoreGraphics
import CoreLocation

public struct APTDecodeContext {
    public let satellite: String
    public let observerLatitude: Double
    public let observerLongitude: Double
    public let passStart: Date?
    public let passEnd: Date?
    public let lineCoverage: [APTLineCoverage]

    public init(
        satellite: String,
        observerLatitude: Double,
        observerLongitude: Double,
        passStart: Date? = nil,
        passEnd: Date? = nil,
        lineCoverage: [APTLineCoverage] = []
    ) {
        self.satellite = satellite
        self.observerLatitude = observerLatitude
        self.observerLongitude = observerLongitude
        self.passStart = passStart
        self.passEnd = passEnd
        self.lineCoverage = lineCoverage
    }
}

public struct APTLineCoverage: Codable, Hashable {
    public let timestamp: Date
    public let latitude: Double
    public let longitude: Double

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

public struct APTDecodeResult {
    public let imageURL: URL
    public let channelAImageURL: URL
    public let channelBImageURL: URL
    public let lineCount: Int
    public let width: Int
    public let syncQuality: Float
    public let lineJitter: Float
    public let channelBalance: Float
    public let telemetryContrast: Float
    public let channelSeparation: Float
    public let calibrationSpread: Float
    public let coverageSummary: APTCoverageSummary?
    public let sourceURL: URL
    public let createdAt: Date
}

public struct APTCoverageSummary: Codable, Hashable {
    public let observerLatitude: Double
    public let observerLongitude: Double
    public let passStart: Date?
    public let passEnd: Date?
    public let firstLine: APTLineCoverage?
    public let lastLine: APTLineCoverage?
    public let lineCount: Int
    public let samplePoints: [APTLineCoverage]
}

public struct APTDecodedArtifact: Identifiable, Codable, Hashable {
    public var id: String { imagePath }
    public let satellite: String
    public let imagePath: String
    public let channelAImagePath: String
    public let channelBImagePath: String
    public let sourcePath: String
    public let createdAt: Date
    public let lineCount: Int
    public let width: Int
    public let syncQuality: Float
    public let lineJitter: Float
    public let channelBalance: Float
    public let telemetryContrast: Float
    public let channelSeparation: Float
    public let calibrationSpread: Float
    public let coverageSummary: APTCoverageSummary?

    public var imageURL: URL { URL(fileURLWithPath: imagePath) }
    public var channelAImageURL: URL { URL(fileURLWithPath: channelAImagePath) }
    public var channelBImageURL: URL { URL(fileURLWithPath: channelBImagePath) }
    public var sourceURL: URL { URL(fileURLWithPath: sourcePath) }
}

public enum APTImageDecoder {
    public static func decodeRecording(at url: URL, satellite: String, context: APTDecodeContext? = nil) throws -> APTDecodeResult {
        let wav = try WAVFloatReader.read(url: url)
        let lineSamples = max(Int(wav.sampleRate * 0.5), 1)
        let width = 2080
        let envelope = smoothedEnvelope(from: wav.samples)
        let lineStarts = estimateLineStarts(envelope: envelope, estimatedLineSamples: lineSamples)
        let lineCount = lineStarts.count

        guard lineCount > 0 else {
            throw NSError(domain: "APTImageDecoder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Recording too short for APT decode"])
        }

        var grayscale = [Float](repeating: 0, count: width * lineCount)
        var channelAGrayscale = [Float](repeating: 0, count: width * lineCount)
        var channelBGrayscale = [Float](repeating: 0, count: width * lineCount)
        var syncAccum: Float = 0
        var channelBalanceAccum: Float = 0
        var telemetryContrastAccum: Float = 0
        var channelSeparationAccum: Float = 0
        var calibrationSpreadAccum: Float = 0

        for (y, base) in lineStarts.enumerated() {
            let lineValues = extractLineValues(
                envelope: envelope,
                lineStart: base,
                lineSamples: lineSamples,
                width: width
            )
            let normalized = normalizeLine(lineValues)
            let analysis = analyzeLine(normalizedValues: normalized)
            syncAccum += analysis.syncScore
            channelBalanceAccum += analysis.channelBalance
            telemetryContrastAccum += analysis.telemetryContrast
            channelSeparationAccum += analysis.channelSeparation
            calibrationSpreadAccum += analysis.calibrationSpread
            for x in 0..<width {
                grayscale[y * width + x] = normalized[x]
                channelAGrayscale[y * width + x] = analysis.channelALine[x]
                channelBGrayscale[y * width + x] = analysis.channelBLine[x]
            }
        }

        let pixels = grayscale.map { UInt8(max(0, min(255, Int($0 * 255)))) }
        let channelAPixels = channelAGrayscale.map { UInt8(max(0, min(255, Int($0 * 255)))) }
        let channelBPixels = channelBGrayscale.map { UInt8(max(0, min(255, Int($0 * 255)))) }

        let decodedDirectory = try decodedOutputDirectory(for: satellite)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let baseFilename = formatter.string(from: Date())
        let filename = "\(baseFilename)_APT.png"
        let channelAFilename = "\(baseFilename)_APT_ChannelA.png"
        let channelBFilename = "\(baseFilename)_APT_ChannelB.png"
        let outputURL = decodedDirectory.appendingPathComponent(filename)
        let channelAOutputURL = decodedDirectory.appendingPathComponent(channelAFilename)
        let channelBOutputURL = decodedDirectory.appendingPathComponent(channelBFilename)
        try writePNGGrayscale(pixels: pixels, width: width, height: lineCount, to: outputURL)
        try writePNGGrayscale(pixels: channelAPixels, width: width, height: lineCount, to: channelAOutputURL)
        try writePNGGrayscale(pixels: channelBPixels, width: width, height: lineCount, to: channelBOutputURL)
        let createdAt = Date()
        let coverageSummary = context.flatMap { buildCoverageSummary(context: $0, decodedLineCount: lineCount) }

        try writeArtifactMetadata(
            APTDecodedArtifact(
                satellite: satellite,
                imagePath: outputURL.path,
                channelAImagePath: channelAOutputURL.path,
                channelBImagePath: channelBOutputURL.path,
                sourcePath: url.path,
                createdAt: createdAt,
                lineCount: lineCount,
                width: width,
                syncQuality: syncAccum / Float(max(lineCount, 1)),
                lineJitter: averageLineJitter(lineStarts: lineStarts, expectedSpacing: lineSamples),
                channelBalance: channelBalanceAccum / Float(max(lineCount, 1)),
                telemetryContrast: telemetryContrastAccum / Float(max(lineCount, 1)),
                channelSeparation: channelSeparationAccum / Float(max(lineCount, 1)),
                calibrationSpread: calibrationSpreadAccum / Float(max(lineCount, 1)),
                coverageSummary: coverageSummary
            ),
            forImageURL: outputURL
        )

        return APTDecodeResult(
            imageURL: outputURL,
            channelAImageURL: channelAOutputURL,
            channelBImageURL: channelBOutputURL,
            lineCount: lineCount,
            width: width,
            syncQuality: syncAccum / Float(max(lineCount, 1)),
            lineJitter: averageLineJitter(lineStarts: lineStarts, expectedSpacing: lineSamples),
            channelBalance: channelBalanceAccum / Float(max(lineCount, 1)),
            telemetryContrast: telemetryContrastAccum / Float(max(lineCount, 1)),
            channelSeparation: channelSeparationAccum / Float(max(lineCount, 1)),
            calibrationSpread: calibrationSpreadAccum / Float(max(lineCount, 1)),
            coverageSummary: coverageSummary,
            sourceURL: url,
            createdAt: createdAt
        )
    }

    public static func listDecodedArtifacts(limit: Int? = nil) -> [APTDecodedArtifact] {
        let baseDirectory = decodedArtifactsDirectory()
        guard let enumerator = FileManager.default.enumerator(at: baseDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        let artifacts = enumerator.compactMap { item -> APTDecodedArtifact? in
            guard let url = item as? URL, url.pathExtension.lowercased() == "json" else {
                return nil
            }
            return try? loadArtifactMetadata(from: url)
        }
        .sorted { $0.createdAt > $1.createdAt }

        if let limit {
            return Array(artifacts.prefix(limit))
        }
        return artifacts
    }

    private static func smoothedEnvelope(from samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let window = 5
        var output = [Float](repeating: 0, count: samples.count)
        var running: Float = 0

        for index in 0..<samples.count {
            running += abs(samples[index])
            if index >= window {
                running -= abs(samples[index - window])
            }
            let count = min(index + 1, window)
            output[index] = running / Float(count)
        }

        return output
    }

    private static func estimateLineStarts(envelope: [Float], estimatedLineSamples: Int) -> [Int] {
        guard envelope.count >= estimatedLineSamples else { return [] }

        var starts: [Int] = [findBestInitialStart(envelope: envelope, estimatedLineSamples: estimatedLineSamples)]
        let searchRadius = max(Int(Double(estimatedLineSamples) * 0.08), 32)

        while true {
            let expected = starts.last! + estimatedLineSamples
            let lower = max(expected - searchRadius, 0)
            let upper = min(expected + searchRadius, envelope.count - estimatedLineSamples)
            if upper <= lower { break }

            let previousProfile = lineSignature(
                envelope: envelope,
                lineStart: starts.last!,
                lineSamples: estimatedLineSamples
            )

            var bestStart = lower
            var bestScore = -Float.greatestFiniteMagnitude
            for candidate in lower...upper {
                let profile = lineSignature(
                    envelope: envelope,
                    lineStart: candidate,
                    lineSamples: estimatedLineSamples
                )
                let downsampled = downsampleLine(
                    envelope: envelope,
                    lineStart: candidate,
                    lineSamples: estimatedLineSamples,
                    width: 256
                )
                let sync = rawSyncCorrelation(
                    envelope: envelope,
                    start: candidate,
                    lineSamples: estimatedLineSamples
                )
                let score = similarity(lhs: previousProfile, rhs: profile) + lineSyncScore(downsampled) * 0.5 + sync * 1.6
                if score > bestScore {
                    bestScore = score
                    bestStart = candidate
                }
            }

            starts.append(bestStart)
            if bestStart + estimatedLineSamples >= envelope.count {
                break
            }
        }

        return starts.filter { $0 + estimatedLineSamples <= envelope.count }
    }

    private static func findBestInitialStart(envelope: [Float], estimatedLineSamples: Int) -> Int {
        let upper = min(estimatedLineSamples, max(envelope.count - estimatedLineSamples, 0))
        var bestStart = 0
        var bestScore = -Float.greatestFiniteMagnitude
        for candidate in 0...upper {
            let profile = downsampleLine(
                envelope: envelope,
                lineStart: candidate,
                lineSamples: estimatedLineSamples,
                width: 256
            )
            let rawCorrelation = rawSyncCorrelation(
                envelope: envelope,
                start: candidate,
                lineSamples: estimatedLineSamples
            )
            let score = lineSyncScore(profile) + rawCorrelation * 1.8
            if score > bestScore {
                bestScore = score
                bestStart = candidate
            }
        }
        return bestStart
    }

    private static func extractLineValues(envelope: [Float], lineStart: Int, lineSamples: Int, width: Int) -> [Float] {
        downsampleLine(envelope: envelope, lineStart: lineStart, lineSamples: lineSamples, width: width)
    }

    private static func downsampleLine(envelope: [Float], lineStart: Int, lineSamples: Int, width: Int) -> [Float] {
        var output = [Float](repeating: 0, count: width)
        for x in 0..<width {
            let start = lineStart + (x * lineSamples) / width
            let end = min(lineStart + ((x + 1) * lineSamples) / width, envelope.count)
            if end <= start {
                output[x] = 0
                continue
            }
            var sum: Float = 0
            for index in start..<end {
                sum += envelope[index]
            }
            output[x] = sum / Float(end - start)
        }
        return output
    }

    private static func normalizeLine(_ values: [Float]) -> [Float] {
        guard !values.isEmpty else { return values }
        let sorted = values.sorted()
        let low = sorted[Int(Float(sorted.count - 1) * 0.05)]
        let high = sorted[Int(Float(sorted.count - 1) * 0.95)]
        let scale = max(high - low, 0.0001)
        return values.map { value in
            let normalized = (value - low) / scale
            let gamma = sqrt(max(0, normalized))
            return min(1, max(0, gamma))
        }
    }

    private static func similarity(lhs: [Float], rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var score: Float = 0
        for index in lhs.indices {
            score -= abs(lhs[index] - rhs[index])
        }
        return score / Float(lhs.count)
    }

    private static func lineSyncScore(_ values: [Float]) -> Float {
        guard values.count >= 64 else { return 0 }

        let template = aptSyncTemplate(width: values.count)
        let signalMatch = similarity(lhs: values, rhs: template)

        let prefixWidth = max(values.count / 18, 6)
        let transitionWidth = max(values.count / 10, 8)
        let prefix = values.prefix(prefixWidth).reduce(0, +) / Float(prefixWidth)
        let following = values.dropFirst(prefixWidth).prefix(transitionWidth).reduce(0, +) / Float(transitionWidth)
        let leadingContrast = prefix - following

        let quarter = values.count / 4
        let mid = values.dropFirst(quarter).prefix(quarter).reduce(0, +) / Float(max(quarter, 1))
        let tail = values.suffix(quarter).reduce(0, +) / Float(max(quarter, 1))
        let bodyBalance = -abs(mid - tail)

        return signalMatch + leadingContrast * 1.4 + bodyBalance * 0.2
    }

    private static func lineSignature(envelope: [Float], lineStart: Int, lineSamples: Int) -> [Float] {
        let width = 96
        let values = downsampleLine(envelope: envelope, lineStart: lineStart, lineSamples: lineSamples, width: width)
        return normalizeLine(values)
    }

    private static func rawSyncCorrelation(envelope: [Float], start: Int, lineSamples: Int) -> Float {
        let syncSamples = max(Int(Float(lineSamples) * 0.05), 16)
        let darkSamples = max(Int(Float(lineSamples) * 0.07), 24)
        let total = syncSamples + darkSamples
        guard start + total < envelope.count else { return -1 }

        let syncRegion = mean(envelope, start: start, count: syncSamples)
        let darkRegion = mean(envelope, start: start + syncSamples, count: darkSamples)
        let bodyStart = start + total
        let bodySamples = max(Int(Float(lineSamples) * 0.12), 32)
        let bodyRegion = mean(envelope, start: bodyStart, count: min(bodySamples, max(envelope.count - bodyStart, 1)))

        return (syncRegion - darkRegion) + (bodyRegion - darkRegion) * 0.35
    }

    private static func analyzeLine(normalizedValues: [Float]) -> (
        syncScore: Float,
        channelBalance: Float,
        telemetryContrast: Float,
        channelSeparation: Float,
        calibrationSpread: Float,
        channelALine: [Float],
        channelBLine: [Float]
    ) {
        let syncScore = lineSyncScore(normalizedValues)
        guard normalizedValues.count >= 16 else {
            return (syncScore, 0, 0, 0, 0, normalizedValues, normalizedValues)
        }

        let telemetryStart = Int(Float(normalizedValues.count) * 0.12)
        let telemetryEnd = Int(Float(normalizedValues.count) * 0.23)
        let channelAStart = Int(Float(normalizedValues.count) * 0.23)
        let channelAEnd = Int(Float(normalizedValues.count) * 0.48)
        let spacerStart = Int(Float(normalizedValues.count) * 0.48)
        let spacerEnd = Int(Float(normalizedValues.count) * 0.56)
        let channelBStart = Int(Float(normalizedValues.count) * 0.56)
        let channelBEnd = Int(Float(normalizedValues.count) * 0.88)

        let telemetry = mean(normalizedValues, start: telemetryStart, count: max(telemetryEnd - telemetryStart, 1))
        let channelA = mean(normalizedValues, start: channelAStart, count: max(channelAEnd - channelAStart, 1))
        let spacer = mean(normalizedValues, start: spacerStart, count: max(spacerEnd - spacerStart, 1))
        let channelB = mean(normalizedValues, start: channelBStart, count: max(channelBEnd - channelBStart, 1))
        let telemetryValues = Array(normalizedValues[telemetryStart..<telemetryEnd])
        let calibration = telemetryCalibration(from: telemetryValues, fallbackLow: spacer, fallbackHigh: telemetry)

        let telemetryContrast = telemetry - spacer
        let channelSeparation = abs(channelA - channelB)
        let channelALine = calibratedChannelLine(
            normalizedValues,
            calibration: calibration,
            primaryStart: channelAStart,
            primaryEnd: channelAEnd,
            maskStart: channelBStart,
            maskEnd: channelBEnd
        )
        let channelBLine = calibratedChannelLine(
            normalizedValues,
            calibration: calibration,
            primaryStart: channelBStart,
            primaryEnd: channelBEnd,
            maskStart: channelAStart,
            maskEnd: channelAEnd
        )
        return (
            syncScore,
            channelA - channelB,
            telemetryContrast,
            channelSeparation,
            calibration.high - calibration.low,
            channelALine,
            channelBLine
        )
    }

    private static func telemetryCalibration(
        from telemetryValues: [Float],
        fallbackLow: Float,
        fallbackHigh: Float
    ) -> (low: Float, high: Float) {
        guard !telemetryValues.isEmpty else {
            return (min(fallbackLow, fallbackHigh), max(fallbackLow, fallbackHigh + 0.0001))
        }
        let sorted = telemetryValues.sorted()
        let lowIndex = max(Int(Float(sorted.count - 1) * 0.15), 0)
        let highIndex = max(Int(Float(sorted.count - 1) * 0.85), 0)
        let low = min(sorted[lowIndex], fallbackLow)
        let high = max(sorted[highIndex], fallbackHigh)
        return (low, max(high, low + 0.0001))
    }

    private static func calibratedChannelLine(
        _ values: [Float],
        calibration: (low: Float, high: Float),
        primaryStart: Int,
        primaryEnd: Int,
        maskStart: Int,
        maskEnd: Int
    ) -> [Float] {
        guard !values.isEmpty else { return values }
        let scale = max(calibration.high - calibration.low, 0.0001)
        return values.enumerated().map { index, value in
            let calibrated = min(1, max(0, (value - calibration.low) / scale))
            if index >= primaryStart && index < primaryEnd {
                return pow(calibrated, 0.85)
            }
            if index >= maskStart && index < maskEnd {
                return calibrated * 0.08
            }
            return calibrated * 0.18
        }
    }

    private static func buildCoverageSummary(context: APTDecodeContext, decodedLineCount: Int) -> APTCoverageSummary {
        let sampledCoverage = Array(context.lineCoverage.prefix(decodedLineCount))
        let reducedSamplePoints = sampledCoverage.isEmpty ? [] : strideSampledCoverage(sampledCoverage, maxPoints: 48)
        return APTCoverageSummary(
            observerLatitude: context.observerLatitude,
            observerLongitude: context.observerLongitude,
            passStart: context.passStart,
            passEnd: context.passEnd,
            firstLine: sampledCoverage.first,
            lastLine: sampledCoverage.last,
            lineCount: sampledCoverage.count,
            samplePoints: reducedSamplePoints
        )
    }

    private static func strideSampledCoverage(_ coverage: [APTLineCoverage], maxPoints: Int) -> [APTLineCoverage] {
        guard coverage.count > maxPoints, maxPoints > 1 else { return coverage }
        let strideSize = max(Double(coverage.count - 1) / Double(maxPoints - 1), 1)
        var reduced: [APTLineCoverage] = []
        reduced.reserveCapacity(maxPoints)
        var position = 0.0
        while Int(position) < coverage.count {
            reduced.append(coverage[Int(position)])
            position += strideSize
        }
        if reduced.last != coverage.last, let last = coverage.last {
            reduced.append(last)
        }
        return reduced
    }

    private static func averageLineJitter(lineStarts: [Int], expectedSpacing: Int) -> Float {
        guard lineStarts.count > 1 else { return 0 }
        var totalDeviation: Float = 0
        for pair in zip(lineStarts, lineStarts.dropFirst()) {
            totalDeviation += abs(Float((pair.1 - pair.0) - expectedSpacing))
        }
        return totalDeviation / Float(lineStarts.count - 1)
    }

    private static func mean(_ values: [Float], start: Int, count: Int) -> Float {
        guard !values.isEmpty, count > 0 else { return 0 }
        let lower = max(start, 0)
        let upper = min(lower + count, values.count)
        guard upper > lower else { return 0 }
        var sum: Float = 0
        for index in lower..<upper {
            sum += values[index]
        }
        return sum / Float(upper - lower)
    }

    private static func aptSyncTemplate(width: Int) -> [Float] {
        guard width > 0 else { return [] }
        var template = [Float](repeating: 0.35, count: width)
        let syncWidth = max(Int(Float(width) * 0.04), 6)
        let blackWidth = max(Int(Float(width) * 0.07), 10)
        let rampStart = syncWidth + blackWidth

        for index in 0..<min(syncWidth, width) {
            template[index] = 1.0
        }
        for index in syncWidth..<min(syncWidth + blackWidth, width) {
            template[index] = 0.05
        }
        if rampStart < width {
            for index in rampStart..<width {
                let progress = Float(index - rampStart) / Float(max(width - rampStart, 1))
                template[index] = 0.2 + progress * 0.5
            }
        }
        return template
    }

    private static func decodedOutputDirectory(for satellite: String) throws -> URL {
        let directory = decodedArtifactsDirectory()
            .appendingPathComponent("NOAA", isDirectory: true)
            .appendingPathComponent(sanitizedName(satellite), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func decodedBaseDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    private static func decodedArtifactsDirectory() -> URL {
        decodedBaseDirectory()
            .appendingPathComponent("NeuralSDR2", isDirectory: true)
            .appendingPathComponent("Decoded", isDirectory: true)
    }

    private static func metadataURL(forImageURL imageURL: URL) -> URL {
        imageURL.deletingPathExtension().appendingPathExtension("json")
    }

    private static func writeArtifactMetadata(_ artifact: APTDecodedArtifact, forImageURL imageURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(artifact)
        try data.write(to: metadataURL(forImageURL: imageURL))
    }

    private static func loadArtifactMetadata(from url: URL) throws -> APTDecodedArtifact {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(APTDecodedArtifact.self, from: data)
    }

    private static func sanitizedName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-")
    }

    private static func writePNGGrayscale(pixels: [UInt8], width: Int, height: Int, to url: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!

        let rep = NSBitmapImageRep(cgImage: image)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "APTImageDecoder", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
        }
        try pngData.write(to: url)
    }
}

private struct WAVFloatFile {
    let sampleRate: Double
    let samples: [Float]
}

private enum WAVFloatReader {
    static func read(url: URL) throws -> WAVFloatFile {
        let data = try Data(contentsOf: url)
        guard data.count > 44 else {
            throw NSError(domain: "APTImageDecoder", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid WAV file"])
        }

        var offset = 12
        var sampleRate: UInt32 = 48_000
        var channels: UInt16 = 1
        var bitsPerSample: UInt16 = 32
        var audioFormat: UInt16 = 3
        var sampleData = Data()

        while offset + 8 <= data.count {
            let chunkID = String(data: data[offset..<offset+4], encoding: .ascii) ?? ""
            let chunkSize = Int(readUInt32(from: data, offset: offset + 4))
            let chunkStart = offset + 8
            let chunkEnd = min(chunkStart + chunkSize, data.count)

            if chunkID == "fmt " && chunkStart + 16 <= data.count {
                audioFormat = readUInt16(from: data, offset: chunkStart)
                channels = readUInt16(from: data, offset: chunkStart + 2)
                sampleRate = readUInt32(from: data, offset: chunkStart + 4)
                bitsPerSample = readUInt16(from: data, offset: chunkStart + 14)
            } else if chunkID == "data" {
                sampleData = data[chunkStart..<chunkEnd]
                break
            }

            offset = chunkEnd + (chunkSize % 2)
        }

        guard audioFormat == 3, bitsPerSample == 32, !sampleData.isEmpty else {
            throw NSError(domain: "APTImageDecoder", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected Float32 WAV audio"])
        }

        let floatCount = sampleData.count / MemoryLayout<Float>.size
        var raw = [Float](repeating: 0, count: floatCount)
        _ = raw.withUnsafeMutableBytes { sampleData.copyBytes(to: $0) }

        if channels <= 1 {
            return WAVFloatFile(sampleRate: Double(sampleRate), samples: raw)
        }

        var mono: [Float] = []
        mono.reserveCapacity(raw.count / Int(channels))
        let channelStride = Int(channels)
        for index in Swift.stride(from: 0, to: raw.count - channelStride + 1, by: channelStride) {
            let slice = raw[index..<(index + channelStride)]
            let value = slice.reduce(0, +) / Float(channelStride)
            mono.append(value)
        }
        return WAVFloatFile(sampleRate: Double(sampleRate), samples: mono)
    }

    private static func readUInt16(from data: Data, offset: Int) -> UInt16 {
        let range = offset..<(offset + 2)
        return data[range].withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian
    }

    private static func readUInt32(from data: Data, offset: Int) -> UInt32 {
        let range = offset..<(offset + 4)
        return data[range].withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
    }
}
