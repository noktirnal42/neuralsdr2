import Foundation

public struct PacketDecodeResult {
    public let reportURL: URL
    public let sourceURL: URL
    public let createdAt: Date
    public let sampleRate: Double
    public let estimatedBaud: Double
    public let markFrequency: Double
    public let spaceFrequency: Double
    public let confidence: Double
    public let hdlcFlagCount: Int
    public let decodedFrames: [String]
}

public struct PacketDecodedArtifact: Identifiable, Codable, Hashable {
    public var id: String { reportPath }
    public let satellite: String
    public let reportPath: String
    public let sourcePath: String
    public let createdAt: Date
    public let sampleRate: Double
    public let estimatedBaud: Double
    public let markFrequency: Double
    public let spaceFrequency: Double
    public let confidence: Double
    public let hdlcFlagCount: Int
    public let decodedFrames: [String]

    public var reportURL: URL { URL(fileURLWithPath: reportPath) }
    public var sourceURL: URL { URL(fileURLWithPath: sourcePath) }
}

public enum PacketAudioDecoder {
    public static func decodeRecording(at url: URL, satellite: String) throws -> PacketDecodeResult {
        let wav = try PacketWAVFloatReader.read(url: url)
        guard !wav.samples.isEmpty else {
            throw NSError(domain: "PacketAudioDecoder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Recording too short for packet analysis"])
        }

        let estimatedBaud = 1200.0
        let symbolSamples = max(Int((wav.sampleRate / estimatedBaud).rounded()), 1)
        let symbolCount = wav.samples.count / symbolSamples
        guard symbolCount >= 32 else {
            throw NSError(domain: "PacketAudioDecoder", code: 2, userInfo: [NSLocalizedDescriptionKey: "Recording too short for packet analysis"])
        }

        var toneBits: [Bool] = []
        toneBits.reserveCapacity(symbolCount)
        var contrastAccum = 0.0
        var markWins = 0
        var spaceWins = 0

        for symbolIndex in 0..<symbolCount {
            let start = symbolIndex * symbolSamples
            let end = min(start + symbolSamples, wav.samples.count)
            let slice = Array(wav.samples[start..<end])
            let markPower = goertzelPower(samples: slice, frequency: 1200, sampleRate: wav.sampleRate)
            let spacePower = goertzelPower(samples: slice, frequency: 2200, sampleRate: wav.sampleRate)
            let markBit = markPower >= spacePower
            toneBits.append(markBit)
            if markBit {
                markWins += 1
            } else {
                spaceWins += 1
            }
            let total = markPower + spacePower
            if total > 0 {
                contrastAccum += abs(markPower - spacePower) / total
            }
        }

        let bitBalance = Double(min(markWins, spaceWins)) / Double(max(markWins + spaceWins, 1))
        let averageContrast = contrastAccum / Double(max(toneBits.count, 1))
        let nrziBits = decodeNRZI(bits: toneBits)
        let flagRanges = findHDLCFlags(in: nrziBits)
        let frames = decodeFrames(bits: nrziBits, flagRanges: flagRanges)
        let printableFrames = frames.compactMap(parsedFrameSummary(from:))
        let confidence = min(max((bitBalance * 0.45) + (averageContrast * 0.35) + (min(Double(flagRanges.count), 8.0) / 8.0 * 0.20), 0), 1)

        let createdAt = Date()
        let reportDirectory = try decodedOutputDirectory(for: satellite)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let baseFilename = formatter.string(from: createdAt)
        let reportURL = reportDirectory.appendingPathComponent("\(baseFilename)_PacketReport.txt")

        let artifact = PacketDecodedArtifact(
            satellite: satellite,
            reportPath: reportURL.path,
            sourcePath: url.path,
            createdAt: createdAt,
            sampleRate: wav.sampleRate,
            estimatedBaud: estimatedBaud,
            markFrequency: 1200,
            spaceFrequency: 2200,
            confidence: confidence,
            hdlcFlagCount: flagRanges.count,
            decodedFrames: printableFrames
        )

        try writeReport(for: artifact)
        try writeArtifactMetadata(artifact, forReportURL: reportURL)

        return PacketDecodeResult(
            reportURL: reportURL,
            sourceURL: url,
            createdAt: createdAt,
            sampleRate: wav.sampleRate,
            estimatedBaud: estimatedBaud,
            markFrequency: 1200,
            spaceFrequency: 2200,
            confidence: confidence,
            hdlcFlagCount: flagRanges.count,
            decodedFrames: printableFrames
        )
    }

    public static func listDecodedArtifacts(limit: Int? = nil) -> [PacketDecodedArtifact] {
        let baseDirectory = decodedArtifactsDirectory()
        guard let enumerator = FileManager.default.enumerator(at: baseDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        let artifacts = enumerator.compactMap { item -> PacketDecodedArtifact? in
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

    private static func decodeNRZI(bits: [Bool]) -> [Bool] {
        guard let first = bits.first else { return [] }
        var decoded: [Bool] = []
        decoded.reserveCapacity(bits.count)
        var previous = first
        for bit in bits {
            decoded.append(bit == previous)
            previous = bit
        }
        return decoded
    }

    private static func findHDLCFlags(in bits: [Bool]) -> [Range<Int>] {
        guard bits.count >= 8 else { return [] }
        let flag = [false, true, true, true, true, true, true, false]
        var ranges: [Range<Int>] = []
        for start in 0...(bits.count - 8) {
            let candidate = Array(bits[start..<(start + 8)])
            if candidate == flag {
                ranges.append(start..<(start + 8))
            }
        }
        return ranges
    }

    private static func decodeFrames(bits: [Bool], flagRanges: [Range<Int>]) -> [[UInt8]] {
        guard flagRanges.count >= 2 else { return [] }
        var frames: [[UInt8]] = []
        for pairIndex in 0..<(flagRanges.count - 1) {
            let start = flagRanges[pairIndex].upperBound
            let end = flagRanges[pairIndex + 1].lowerBound
            guard end > start + 8 else { continue }
            let stuffed = Array(bits[start..<end])
            let unstuffed = removeBitStuffing(from: stuffed)
            let bytes = bytesFromLSBFirstBits(unstuffed)
            if !bytes.isEmpty {
                frames.append(bytes)
            }
        }
        return frames
    }

    private static func removeBitStuffing(from bits: [Bool]) -> [Bool] {
        var output: [Bool] = []
        output.reserveCapacity(bits.count)
        var onesCount = 0
        var index = 0
        while index < bits.count {
            let bit = bits[index]
            output.append(bit)
            if bit {
                onesCount += 1
                if onesCount == 5 {
                    index += 1
                    onesCount = 0
                }
            } else {
                onesCount = 0
            }
            index += 1
        }
        return output
    }

    private static func bytesFromLSBFirstBits(_ bits: [Bool]) -> [UInt8] {
        guard bits.count >= 8 else { return [] }
        var bytes: [UInt8] = []
        var index = 0
        while index + 7 < bits.count {
            var byte: UInt8 = 0
            for bitIndex in 0..<8 where bits[index + bitIndex] {
                byte |= UInt8(1 << bitIndex)
            }
            bytes.append(byte)
            index += 8
        }
        return bytes
    }

    private static func parsedFrameSummary(from bytes: [UInt8]) -> String? {
        if let ax25 = parseAX25Frame(bytes) {
            return ax25.summary
        }

        return printableASCIIFrame(from: bytes)
    }

    private static func printableASCIIFrame(from bytes: [UInt8]) -> String? {
        let filtered = bytes.filter { ($0 >= 32 && $0 <= 126) || $0 == 10 || $0 == 13 }
        guard filtered.count >= 4 else { return nil }
        let string = String(bytes: filtered, encoding: .ascii)?
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let string, !string.isEmpty else { return nil }
        return string
    }

    private struct ParsedAX25Frame {
        let destination: String
        let source: String
        let repeaters: [String]
        let control: UInt8
        let pid: UInt8?
        let info: String

        var summary: String {
            var route = "\(source) > \(destination)"
            if !repeaters.isEmpty {
                route += " via " + repeaters.joined(separator: ",")
            }

            var tail = "ctl=\(String(format: "%02X", control))"
            if let pid {
                tail += " pid=\(String(format: "%02X", pid))"
            }
            if !info.isEmpty {
                tail += " \(info)"
            }
            return "\(route) \(tail)"
        }
    }

    private static func parseAX25Frame(_ bytes: [UInt8]) -> ParsedAX25Frame? {
        guard bytes.count >= 16 else { return nil }

        var addresses: [String] = []
        var offset = 0
        var lastAddress = false

        while offset + 7 <= bytes.count, !lastAddress {
            let field = Array(bytes[offset..<(offset + 7)])
            guard let address = decodeAX25Address(field) else { return nil }
            addresses.append(address)
            lastAddress = (field[6] & 0x01) == 0x01
            offset += 7
        }

        guard addresses.count >= 2, offset < bytes.count else { return nil }
        let destination = addresses[0]
        let source = addresses[1]
        let repeaters = Array(addresses.dropFirst(2))

        let control = bytes[offset]
        offset += 1

        var pid: UInt8?
        if offset < bytes.count, control == 0x03 || control == 0x13 {
            pid = bytes[offset]
            offset += 1
        }

        let infoBytes = offset < bytes.count ? Array(bytes[offset...]) : []
        let info = infoBytes
            .filter { ($0 >= 32 && $0 <= 126) || $0 == 9 || $0 == 32 }
            .map { Character(UnicodeScalar($0)) }
        let infoString = String(info).trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedAX25Frame(
            destination: destination,
            source: source,
            repeaters: repeaters,
            control: control,
            pid: pid,
            info: infoString
        )
    }

    private static func decodeAX25Address(_ field: [UInt8]) -> String? {
        guard field.count == 7 else { return nil }
        let characters = field[0..<6].map { byte -> Character in
            let shifted = byte >> 1
            if shifted == 0x20 {
                return " "
            }
            let scalar = UnicodeScalar(max(UInt8(32), shifted))
            return Character(scalar)
        }
        let base = String(characters).trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return nil }
        let ssid = Int((field[6] >> 1) & 0x0F)
        if ssid > 0 {
            return "\(base)-\(ssid)"
        }
        return base
    }

    private static func goertzelPower(samples: [Float], frequency: Double, sampleRate: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        let omega = 2.0 * Double.pi * frequency / sampleRate
        let coeff = 2.0 * cos(omega)
        var q0 = 0.0
        var q1 = 0.0
        var q2 = 0.0

        for sample in samples {
            q0 = coeff * q1 - q2 + Double(sample)
            q2 = q1
            q1 = q0
        }

        return q1 * q1 + q2 * q2 - coeff * q1 * q2
    }

    private static func writeReport(for artifact: PacketDecodedArtifact) throws {
        let confidence = Int((artifact.confidence * 100).rounded())
        let frameSection: String
        if artifact.decodedFrames.isEmpty {
            frameSection = "No printable AX.25 payloads recovered from current heuristic decode."
        } else {
            frameSection = artifact.decodedFrames.enumerated().map { index, frame in
                "Frame \(index + 1): \(frame)"
            }.joined(separator: "\n")
        }

        let report = """
        NeuralSDR2 Internal Packet Report
        Satellite: \(artifact.satellite)
        Created: \(artifact.createdAt.formatted(date: .abbreviated, time: .standard))
        Source: \((artifact.sourcePath as NSString).lastPathComponent)

        Sample Rate: \(Int(artifact.sampleRate)) Hz
        Estimated Baud: \(Int(artifact.estimatedBaud)) baud
        Tone Pair: \(Int(artifact.markFrequency))/\(Int(artifact.spaceFrequency)) Hz
        Confidence: \(confidence)%
        HDLC Flags Detected: \(artifact.hdlcFlagCount)

        \(frameSection)
        """

        try report.write(to: artifact.reportURL, atomically: true, encoding: .utf8)
    }

    private static func decodedArtifactsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("NeuralSDR2/DecodedPackets", isDirectory: true)
    }

    private static func decodedOutputDirectory(for satellite: String) throws -> URL {
        let sanitized = satellite.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        let directory = decodedArtifactsDirectory().appendingPathComponent(sanitized, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func writeArtifactMetadata(_ artifact: PacketDecodedArtifact, forReportURL reportURL: URL) throws {
        let metadataURL = reportURL.deletingPathExtension().appendingPathExtension("json")
        let data = try JSONEncoder().encode(artifact)
        try data.write(to: metadataURL, options: .atomic)
    }

    private static func loadArtifactMetadata(from url: URL) throws -> PacketDecodedArtifact {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PacketDecodedArtifact.self, from: data)
    }
}

private enum PacketWAVFloatReader {
    static func read(url: URL) throws -> (sampleRate: Double, samples: [Float]) {
        let data = try Data(contentsOf: url)
        guard data.count > 44 else {
            throw NSError(domain: "PacketAudioDecoder", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid WAV file"])
        }

        func u16(_ offset: Int) -> UInt16 {
            data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian
        }

        func u32(_ offset: Int) -> UInt32 {
            data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        }

        guard String(data: data[0..<4], encoding: .ascii) == "RIFF",
              String(data: data[8..<12], encoding: .ascii) == "WAVE" else {
            throw NSError(domain: "PacketAudioDecoder", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid WAV file"])
        }

        var offset = 12
        var sampleRate = 48_000.0
        var audioFormat: UInt16 = 0
        var channels: UInt16 = 1
        var dataOffset: Int?
        var dataSize: Int?

        while offset + 8 <= data.count {
            guard let chunkID = String(data: data[offset..<(offset + 4)], encoding: .ascii) else { break }
            let chunkSize = Int(u32(offset + 4))
            let chunkDataOffset = offset + 8

            if chunkID == "fmt " {
                audioFormat = u16(chunkDataOffset)
                channels = u16(chunkDataOffset + 2)
                sampleRate = Double(u32(chunkDataOffset + 4))
            } else if chunkID == "data" {
                dataOffset = chunkDataOffset
                dataSize = chunkSize
                break
            }

            offset = chunkDataOffset + chunkSize + (chunkSize % 2)
        }

        guard audioFormat == 3, channels >= 1, let dataOffset, let dataSize else {
            throw NSError(domain: "PacketAudioDecoder", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected Float32 WAV audio"])
        }

        let frameCount = dataSize / MemoryLayout<Float>.size / Int(channels)
        var samples: [Float] = []
        samples.reserveCapacity(frameCount)

        for frame in 0..<frameCount {
            let sampleOffset = dataOffset + frame * Int(channels) * MemoryLayout<Float>.size
            let value = data.subdata(in: sampleOffset..<(sampleOffset + 4)).withUnsafeBytes { $0.load(as: Float.self) }
            samples.append(value)
        }

        return (sampleRate, samples)
    }
}
