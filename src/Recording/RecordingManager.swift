//
// RecordingManager.swift
// NeuralSDR2
//
// Manages IQ and audio recording with metadata
//

import Foundation
import AVFoundation

/// Recording types
public enum RecordingType: String, Sendable {
    case iq = "IQ Recording"
    case audio = "Audio Recording"
    case spectrum = "Spectrum Data"
}

/// Recording format options
public enum RecordingFormat: String, Sendable {
    case wav = "WAV"
    case flac = "FLAC"
    case rawIQ = "Raw IQ"
    case sigmf = "SigMF"
}

/// Recording metadata
public struct RecordingMetadata: Hashable {
    public var timestamp: Date
    public var frequency: Double
    public var sampleRate: Double
    public var mode: String
    public var duration: TimeInterval
    public var filePath: String
    public var fileSize: UInt64
    public var notes: String
    public var tags: [String]

    public init(
        timestamp: Date = Date(),
        frequency: Double = 0,
        sampleRate: Double = 2048000,
        mode: String = "NFM",
        duration: TimeInterval = 0,
        filePath: String = "",
        fileSize: UInt64 = 0,
        notes: String = "",
        tags: [String] = []
    ) {
        self.timestamp = timestamp
        self.frequency = frequency
        self.sampleRate = sampleRate
        self.mode = mode
        self.duration = duration
        self.filePath = filePath
        self.fileSize = fileSize
        self.notes = notes
        self.tags = tags
    }
}

/// Recording session state
public enum RecordingState {
    case idle
    case recording
    case paused
    case stopping
}

/// Manages all recording operations
public class RecordingManager {
    private(set) public var currentState: RecordingState = .idle
    private var currentRecording: RecordingSession?
    private var recordingsDirectory: URL
    private var metadataDatabase: RecordingDatabase

    public var onRecordingStart: ((RecordingMetadata) -> Void)?
    public var onRecordingUpdate: ((RecordingMetadata) -> Void)?
    public var onRecordingStop: ((RecordingMetadata) -> Void)?

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("NeuralSDR2", isDirectory: true)
        recordingsDirectory = appFolder.appendingPathComponent("Recordings", isDirectory: true)

        try? FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)

        let dbURL = appFolder.appendingPathComponent("recordings.json", isDirectory: false)
        metadataDatabase = RecordingDatabase(databaseURL: dbURL)
    }

    public func startIQRecording(
        frequency: Double,
        sampleRate: Double,
        mode: String,
        format: RecordingFormat = .rawIQ,
        notes: String = "",
        tags: [String] = []
    ) throws -> URL {
        guard currentState == .idle else {
            throw RecordingError.alreadyRecording
        }

        let session = RecordingSession(
            type: .iq,
            format: format,
            sampleRate: sampleRate,
            recordingsDirectory: recordingsDirectory
        )

        try session.startRecording(
            frequency: frequency,
            mode: mode,
            notes: notes,
            tags: tags
        )

        currentRecording = session
        currentState = .recording

        if let metadata = session.metadata {
            onRecordingStart?(metadata)
        }

        return session.fileURL
    }

    public func startAudioRecording(
        frequency: Double,
        sampleRate: Double = 48000,
        mode: String,
        format: RecordingFormat = .wav,
        notes: String = "",
        tags: [String] = []
    ) throws -> URL {
        guard currentState == .idle else {
            throw RecordingError.alreadyRecording
        }

        let session = RecordingSession(
            type: .audio,
            format: format,
            sampleRate: sampleRate,
            recordingsDirectory: recordingsDirectory
        )

        try session.startRecording(
            frequency: frequency,
            mode: mode,
            notes: notes,
            tags: tags
        )

        currentRecording = session
        currentState = .recording

        if let metadata = session.metadata {
            onRecordingStart?(metadata)
        }

        return session.fileURL
    }

    public func writeSamples(_ samples: [ComplexFloat]) throws {
        guard currentState == .recording, let session = currentRecording else {
            return
        }

        try session.writeSamples(samples)

        if let metadata = session.metadata {
            onRecordingUpdate?(metadata)
        }
    }

    public func writeAudioSamples(_ samples: [Float]) throws {
        guard currentState == .recording, let session = currentRecording else {
            return
        }

        try session.writeAudioSamples(samples)

        if let metadata = session.metadata {
            onRecordingUpdate?(metadata)
        }
    }

    public func stopRecording() throws -> RecordingMetadata? {
        guard currentState == .recording || currentState == .paused,
              let session = currentRecording else {
            throw RecordingError.notRecording
        }

        currentState = .stopping

        let metadata = try session.stopRecording()

        try? metadataDatabase.addRecording(metadata)

        currentRecording = nil
        currentState = .idle

        onRecordingStop?(metadata)

        return metadata
    }

    public func pauseRecording() throws {
        guard currentState == .recording, let session = currentRecording else {
            throw RecordingError.notRecording
        }

        session.pause()
        currentState = .paused
    }

    public func resumeRecording() throws {
        guard currentState == .paused, let session = currentRecording else {
            throw RecordingError.notRecording
        }

        session.resume()
        currentState = .recording
    }

    public func getRecordings(filter: String? = nil) -> [RecordingMetadata] {
        return metadataDatabase.getRecordings(filter: filter)
    }

    public func deleteRecording(at path: String) throws {
        try metadataDatabase.deleteRecording(at: path)
        try FileManager.default.removeItem(atPath: path)

        let sigmfMetaPath = (path as NSString).deletingPathExtension + ".sigmf-meta"
        if FileManager.default.fileExists(atPath: sigmfMetaPath) {
            try? FileManager.default.removeItem(atPath: sigmfMetaPath)
        }
    }

    public func getRecordingsDirectory() -> URL {
        return recordingsDirectory
    }

    public var currentRecordingType: RecordingType? {
        currentRecording?.type
    }
}

// MARK: - WAV Header Constants

private enum WAVConstants {
    static let headerSize: UInt32 = 44
    static let fmtChunkSize: UInt32 = 16
    static let pcmFormat: UInt16 = 1
    static let ieeeFloatFormat: UInt16 = 3
}

// MARK: - Little-Endian Byte Helpers

private func writeLE16(_ value: UInt16) -> [UInt8] {
    return [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
}

private func writeLE32(_ value: UInt32) -> [UInt8] {
    return [
        UInt8(value & 0xFF),
        UInt8((value >> 8) & 0xFF),
        UInt8((value >> 16) & 0xFF),
        UInt8((value >> 24) & 0xFF)
    ]
}

// MARK: - Recording Session

public class RecordingSession {
    public let type: RecordingType
    public let format: RecordingFormat
    public let sampleRate: Double

    private var _fileURL: URL
    private var fileHandle: FileHandle?
    private var startTime: Date?
    private var _metadata: RecordingMetadata?
    private var sampleCount: UInt64 = 0
    private var bytesWritten: UInt64 = 0
    private var recordingsDirectory: URL
    private var isPaused: Bool = false

    public var fileURL: URL { _fileURL }
    public var metadata: RecordingMetadata? { _metadata }

    public init(type: RecordingType, format: RecordingFormat, sampleRate: Double, recordingsDirectory: URL) {
        self.type = type
        self.format = format
        self.sampleRate = sampleRate
        self.recordingsDirectory = recordingsDirectory
        self._fileURL = URL(fileURLWithPath: "")
    }

    public func startRecording(frequency: Double, mode: String, notes: String, tags: [String]) throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())

        let filename: String
        switch format {
        case .sigmf:
            filename = "\(type.rawValue)_\(frequency / 1_000_000)MHz_\(timestamp)"
        default:
            filename = "\(type.rawValue)_\(frequency / 1_000_000)MHz_\(timestamp)"
        }
        let fileExtension = getFileExtension()

        _fileURL = recordingsDirectory.appendingPathComponent("\(filename).\(fileExtension)")

        let parentDir = _fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        switch format {
        case .wav:
            FileManager.default.createFile(atPath: _fileURL.path, contents: nil)
            fileHandle = try FileHandle(forWritingTo: _fileURL)
            try writeWAVHeader()

        case .flac:
            // FLAC encoding requires the FLAC C library (libFLAC) or an external tool such as
            // ffmpeg / flac. Without that dependency we cannot produce a valid FLAC bitstream.
            // Writing raw PCM to a .flac file would produce an invalid file, so we throw.
            throw RecordingError.invalidFormat

        case .rawIQ, .sigmf:
            FileManager.default.createFile(atPath: _fileURL.path, contents: nil)
            fileHandle = try FileHandle(forWritingTo: _fileURL)
        }

        startTime = Date()
        bytesWritten = 0
        sampleCount = 0

        if format == .wav {
            bytesWritten = UInt64(WAVConstants.headerSize)
        }

        _metadata = RecordingMetadata(
            timestamp: Date(),
            frequency: frequency,
            sampleRate: sampleRate,
            mode: mode,
            duration: 0,
            filePath: _fileURL.path,
            fileSize: 0,
            notes: notes,
            tags: tags
        )
    }

    public func writeSamples(_ samples: [ComplexFloat]) throws {
        guard let handle = fileHandle else { throw RecordingError.fileNotOpen }
        guard !isPaused else { return }

        switch format {
        case .rawIQ, .sigmf:
            var data = Data(capacity: samples.count * MemoryLayout<ComplexFloat>.size)
            for sample in samples {
                var r = sample.real
                var i = sample.imag
                data.append(Data(bytes: &r, count: MemoryLayout<Float>.size))
                data.append(Data(bytes: &i, count: MemoryLayout<Float>.size))
            }
            handle.write(data)
            bytesWritten += UInt64(data.count)

        case .wav:
            // IQ WAV: 2-channel Float32 (I=ch1, Q=ch2)
            var data = Data(capacity: samples.count * 2 * MemoryLayout<Float>.size)
            for sample in samples {
                var r = sample.real
                var i = sample.imag
                data.append(Data(bytes: &r, count: MemoryLayout<Float>.size))
                data.append(Data(bytes: &i, count: MemoryLayout<Float>.size))
            }
            handle.write(data)
            bytesWritten += UInt64(data.count)

        case .flac:
            throw RecordingError.invalidFormat
        }

        sampleCount += UInt64(samples.count)
        updateMetadata()
    }

    public func writeAudioSamples(_ samples: [Float]) throws {
        guard let handle = fileHandle else { throw RecordingError.fileNotOpen }
        guard !isPaused else { return }

        switch format {
        case .wav:
            var data = Data(capacity: samples.count * MemoryLayout<Float>.size)
            for sample in samples {
                var v = sample
                data.append(Data(bytes: &v, count: MemoryLayout<Float>.size))
            }
            handle.write(data)
            bytesWritten += UInt64(data.count)

        case .rawIQ, .sigmf:
            var data = Data(capacity: samples.count * MemoryLayout<Float>.size)
            for sample in samples {
                var v = sample
                data.append(Data(bytes: &v, count: MemoryLayout<Float>.size))
            }
            handle.write(data)
            bytesWritten += UInt64(data.count)

        case .flac:
            throw RecordingError.invalidFormat
        }

        sampleCount += UInt64(samples.count)
        updateMetadata()
    }

    public func stopRecording() throws -> RecordingMetadata {
        if format == .wav {
            try updateWAVHeader()
        }

        if format == .sigmf {
            try writeSigMFMetadata()
        }

        fileHandle?.closeFile()
        fileHandle = nil

        updateMetadata()
        return _metadata!
    }

    public func pause() {
        isPaused = true
    }

    public func resume() {
        isPaused = false
    }

    // MARK: - Private Helpers

    private func updateMetadata() {
        let duration = Date().timeIntervalSince(startTime ?? Date())

        _metadata?.duration = duration
        _metadata?.fileSize = bytesWritten
    }

    private func getFileExtension() -> String {
        switch format {
        case .wav: return "wav"
        case .flac: return "flac"
        case .rawIQ: return "iq"
        case .sigmf: return "sigmf-data"
        }
    }

    // MARK: - WAV Header

    private func wavAudioFormat() -> UInt16 {
        switch type {
        case .audio:
            return WAVConstants.ieeeFloatFormat
        case .iq:
            return WAVConstants.ieeeFloatFormat
        case .spectrum:
            return WAVConstants.ieeeFloatFormat
        }
    }

    private func wavNumChannels() -> UInt16 {
        switch type {
        case .iq: return 2
        case .audio: return 1
        case .spectrum: return 1
        }
    }

    private func wavBitsPerSample() -> UInt16 {
        return 32
    }

    private func wavBlockAlign() -> UInt16 {
        return wavNumChannels() * wavBitsPerSample() / 8
    }

    private func wavByteRate() -> UInt32 {
        return UInt32(sampleRate) * UInt32(wavBlockAlign())
    }

    private func writeWAVHeader() throws {
        guard let handle = fileHandle else { throw RecordingError.fileNotOpen }

        var header = Data()

        // RIFF header
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        header.append(contentsOf: writeLE32(0))                              // file size - 8 (placeholder)
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt chunk
        header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        header.append(contentsOf: writeLE32(WAVConstants.fmtChunkSize))      // chunk size = 16
        header.append(contentsOf: writeLE16(wavAudioFormat()))               // audio format
        header.append(contentsOf: writeLE16(wavNumChannels()))               // num channels
        header.append(contentsOf: writeLE32(UInt32(sampleRate)))             // sample rate
        header.append(contentsOf: writeLE32(wavByteRate()))                  // byte rate
        header.append(contentsOf: writeLE16(wavBlockAlign()))                // block align
        header.append(contentsOf: writeLE16(wavBitsPerSample()))             // bits per sample

        // data chunk
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        header.append(contentsOf: writeLE32(0))                              // data size (placeholder)

        handle.write(header)
    }

    private func updateWAVHeader() throws {
        guard let handle = fileHandle else { throw RecordingError.fileNotOpen }

        let dataSize = UInt32(bytesWritten - UInt64(WAVConstants.headerSize))
        let fileSize = dataSize + UInt32(WAVConstants.headerSize) - 8

        // Write RIFF chunk size at offset 4
        try handle.seek(toOffset: 4)
        handle.write(Data(writeLE32(fileSize)))

        // Write data chunk size at offset 40
        try handle.seek(toOffset: 40)
        handle.write(Data(writeLE32(dataSize)))
    }

    // MARK: - SigMF Metadata

    private func writeSigMFMetadata() throws {
        guard let meta = _metadata else { return }

        let dataFileSize = bytesWritten
        let totalSamples = dataFileSize / UInt64(MemoryLayout<ComplexFloat>.size)

        let metaURL = _fileURL.deletingPathExtension().appendingPathExtension("sigmf-meta")

        var json = [String: Any]()

        json["version"] = "1.0.0"
        json["type"] = "iq"

        var global = [String: Any]()
        global["core:datatype"] = "cf32_le"
        global["core:sample_rate"] = sampleRate
        global["core:version"] = "1.0.0"
        global["core:num_channels"] = 1
        global["core:recorder"] = "NeuralSDR2"
        if totalSamples > 0 {
            global["core:num_samples"] = NSNumber(value: totalSamples)
        }
        json["global"] = global

        var captures = [[String: Any]]()
        var capture = [String: Any]()
        capture["core:sample_start"] = NSNumber(value: 0)
        capture["core:frequency"] = meta.frequency
        captures.append(capture)
        json["captures"] = captures

        var annotations = [[String: Any]]()
        var annotation = [String: Any]()
        annotation["core:sample_start"] = NSNumber(value: 0)
        if totalSamples > 0 {
            annotation["core:sample_count"] = NSNumber(value: totalSamples)
        }
        annotation["core:mode"] = meta.mode
        if !meta.notes.isEmpty {
            annotation["core:comment"] = meta.notes
        }
        annotations.append(annotation)
        json["annotations"] = annotations

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try jsonData.write(to: metaURL)
    }
}

// MARK: - Recording Database

public class RecordingDatabase {
    private var databaseURL: URL
    private var recordings: [RecordingMetadata] = []
    private var fileCoordinator: NSFileCoordinator?

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL

        let parentDir = databaseURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        loadFromDisk()
    }

    public func addRecording(_ metadata: RecordingMetadata) throws {
        recordings.append(metadata)
        try saveToDisk()
    }

    public func getRecordings(filter: String? = nil) -> [RecordingMetadata] {
        guard let filter = filter?.lowercased(), !filter.isEmpty else {
            return recordings.sorted { $0.timestamp > $1.timestamp }
        }

        return recordings.filter { rec in
            rec.filePath.lowercased().contains(filter) ||
            rec.mode.lowercased().contains(filter) ||
            rec.notes.lowercased().contains(filter) ||
            rec.tags.contains { $0.lowercased().contains(filter) } ||
            String(format: "%.1f", rec.frequency / 1_000_000).contains(filter)
        }.sorted { $0.timestamp > $1.timestamp }
    }

    public func deleteRecording(at path: String) throws {
        recordings.removeAll { $0.filePath == path }
        try saveToDisk()
    }

    public func updateRecording(at path: String, notes: String? = nil, tags: [String]? = nil) throws {
        guard let index = recordings.firstIndex(where: { $0.filePath == path }) else { return }
        if let notes = notes { recordings[index].notes = notes }
        if let tags = tags { recordings[index].tags = tags }
        try saveToDisk()
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return }
        guard let data = FileManager.default.contents(atPath: databaseURL.path) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            recordings = try decoder.decode([RecordingMetadata].self, from: data)
        } catch {
            recordings = []
        }
    }

    private func saveToDisk() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(recordings)
        try data.write(to: databaseURL, options: .atomic)
    }
}

// MARK: - RecordingMetadata Codable

extension RecordingMetadata: Codable {
    private enum CodingKeys: String, CodingKey {
        case timestamp, frequency, sampleRate, mode, duration, filePath, fileSize, notes, tags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        frequency = try container.decode(Double.self, forKey: .frequency)
        sampleRate = try container.decode(Double.self, forKey: .sampleRate)
        mode = try container.decode(String.self, forKey: .mode)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        filePath = try container.decode(String.self, forKey: .filePath)
        fileSize = try container.decode(UInt64.self, forKey: .fileSize)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(sampleRate, forKey: .sampleRate)
        try container.encode(mode, forKey: .mode)
        try container.encode(duration, forKey: .duration)
        try container.encode(filePath, forKey: .filePath)
        try container.encode(fileSize, forKey: .fileSize)
        try container.encode(notes, forKey: .notes)
        try container.encode(tags, forKey: .tags)
    }
}

// MARK: - Errors

public enum RecordingError: Error, LocalizedError {
    case alreadyRecording
    case notRecording
    case fileNotOpen
    case invalidFormat
    case writeError
    case flacNotSupported

    public var errorDescription: String? {
        switch self {
        case .alreadyRecording: return "A recording is already in progress"
        case .notRecording: return "No recording is in progress"
        case .fileNotOpen: return "Recording file is not open"
        case .invalidFormat: return "Invalid recording format for this operation"
        case .writeError: return "Failed to write to recording file"
        case .flacNotSupported: return "FLAC encoding requires libFLAC or an external encoder (ffmpeg / flac command-line tool)"
        }
    }
}
