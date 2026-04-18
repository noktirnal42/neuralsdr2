//
//  RecordingManager.swift
//  NeuralSDR2
//
//  Manages IQ and audio recording with metadata
//

import Foundation
import AVFoundation

/// Recording types
public enum RecordingType: String {
    case iq = "IQ Recording"
    case audio = "Audio Recording"
    case spectrum = "Spectrum Data"
}

/// Recording format options
public enum RecordingFormat: String {
    case wav = "WAV"
    case flac = "FLAC"
    case rawIQ = "Raw IQ"
    case sigmf = "SigMF"
}

/// Recording metadata
public struct RecordingMetadata {
    var timestamp: Date
    var frequency: Double
    var sampleRate: Double
    var mode: String
    var duration: TimeInterval
    var filePath: String
    var fileSize: UInt64
    var notes: String
    var tags: [String]
    
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
    private(set) var currentState: RecordingState = .idle
    private var currentRecording: RecordingSession?
    private var recordingsDirectory: URL
    private var metadataDatabase: RecordingDatabase?
    
    // Callbacks
    public var onRecordingStart: ((RecordingMetadata) -> Void)?
    public var onRecordingUpdate: ((RecordingMetadata) -> Void)?
    public var onRecordingStop: ((RecordingMetadata) -> Void)?
    
    public init() {
        // Set up recordings directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("NeuralSDR2", isDirectory: true)
        recordingsDirectory = appFolder.appendingPathComponent("Recordings", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        
        // Initialize database
        metadataDatabase = RecordingDatabase()
    }
    
    /// Start IQ recording
    public func startIQRecording(
        frequency: Double,
        sampleRate: Double,
        mode: String,
        format: RecordingFormat = .rawIQ,
        notes: String = ""
    ) throws -> URL {
        guard currentState == .idle else {
            throw RecordingError.alreadyRecording
        }
        
        // Create recording session
        let session = RecordingSession(
            type: .iq,
            format: format,
            sampleRate: sampleRate
        )
        
        try session.startRecording(
            frequency: frequency,
            mode: mode,
            notes: notes
        )
        
        currentRecording = session
        currentState = .recording
        
        // Callback
        if let metadata = session.metadata {
            onRecordingStart?(metadata)
        }
        
        return session.fileURL
    }
    
    /// Start audio recording
    public func startAudioRecording(
        frequency: Double,
        sampleRate: Double = 48000,
        mode: String,
        format: RecordingFormat = .wav,
        notes: String = ""
    ) throws -> URL {
        guard currentState == .idle else {
            throw RecordingError.alreadyRecording
        }
        
        // Create recording session
        let session = RecordingSession(
            type: .audio,
            format: format,
            sampleRate: sampleRate
        )
        
        try session.startRecording(
            frequency: frequency,
            mode: mode,
            notes: notes
        )
        
        currentRecording = session
        currentState = .recording
        
        // Callback
        if let metadata = session.metadata {
            onRecordingStart?(metadata)
        }
        
        return session.fileURL
    }
    
    /// Write IQ samples to current recording
    public func writeSamples(_ samples: [ComplexFloat]) throws {
        guard currentState == .recording, let session = currentRecording else {
            return
        }
        
        try session.writeSamples(samples)
        
        // Update callback periodically
        if let metadata = session.metadata {
            onRecordingUpdate?(metadata)
        }
    }
    
    /// Write audio samples to current recording
    public func writeAudioSamples(_ samples: [Float]) throws {
        guard currentState == .recording, let session = currentRecording else {
            return
        }
        
        try session.writeAudioSamples(samples)
        
        // Update callback
        if let metadata = session.metadata {
            onRecordingUpdate?(metadata)
        }
    }
    
    /// Stop current recording
    public func stopRecording() throws -> RecordingMetadata? {
        guard currentState == .recording || currentState == .paused,
              let session = currentRecording else {
            throw RecordingError.notRecording
        }
        
        currentState = .stopping
        
        // Finalize recording
        let metadata = try session.stopRecording()
        
        // Save to database
        try? metadataDatabase?.addRecording(metadata)
        
        currentRecording = nil
        currentState = .idle
        
        // Callback
        onRecordingStop?(metadata)
        
        return metadata
    }
    
    /// Pause recording
    public func pauseRecording() throws {
        guard currentState == .recording, let session = currentRecording else {
            throw RecordingError.notRecording
        }
        
        session.pause()
        currentState = .paused
    }
    
    /// Resume recording
    public func resumeRecording() throws {
        guard currentState == .paused, let session = currentRecording else {
            throw RecordingError.notRecording
        }
        
        session.resume()
        currentState = .recording
    }
    
    /// Get list of all recordings
    public func getRecordings(filter: String? = nil) -> [RecordingMetadata] {
        return metadataDatabase?.getRecordings(filter: filter) ?? []
    }
    
    /// Delete a recording
    public func deleteRecording(at path: String) throws {
        try metadataDatabase?.deleteRecording(at: path)
        try FileManager.default.removeItem(atPath: path)
    }
    
    /// Get recordings directory URL
    public func getRecordingsDirectory() -> URL {
        return recordingsDirectory
    }
}

/// Individual recording session
public class RecordingSession {
    public let type: RecordingType
    public let format: RecordingFormat
    public let sampleRate: Double
    
    private var fileHandle: FileHandle?
    private var fileURL: URL
    private var startTime: Date?
    private var metadata: RecordingMetadata?
    private var sampleCount: UInt64 = 0
    
    public var fileURL: URL { fileURL }
    public var metadata: RecordingMetadata? { metadata }
    
    public init(type: RecordingType, format: RecordingFormat, sampleRate: Double) {
        self.type = type
        self.format = format
        self.sampleRate = sampleRate
        self.fileURL = URL(fileURLWithPath: "")
    }
    
    public func startRecording(frequency: Double, mode: String, notes: String) throws {
        // Generate filename with timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        
        let filename = "\(type.rawValue)_\(frequency / 1_000_000)MHz_\(timestamp)"
        let extension = getFileExtension()
        
        // Create file URL
        let recordingsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("NeuralSDR2/Recordings", isDirectory: true)
        fileURL = recordingsDir.appendingPathComponent("\(filename).\(extension)")
        
        // Create file
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: fileURL)
        
        // Write WAV header if needed
        if format == .wav && type == .audio {
            try writeWAVHeader()
        }
        
        startTime = Date()
        
        // Create metadata
        metadata = RecordingMetadata(
            timestamp: Date(),
            frequency: frequency,
            sampleRate: sampleRate,
            mode: mode,
            duration: 0,
            filePath: fileURL.path,
            fileSize: 0,
            notes: notes,
            tags: []
        )
    }
    
    public func writeSamples(_ samples: [ComplexFloat]) throws {
        guard let handle = fileHandle else { throw RecordingError.fileNotOpen }
        
        // Convert to data and write
        let data = Data(bytes: samples, count: samples.count * MemoryLayout<ComplexFloat>.size)
        handle.write(data)
        
        sampleCount += UInt64(samples.count)
        updateMetadata()
    }
    
    public func writeAudioSamples(_ samples: [Float]) throws {
        guard let handle = fileHandle else { throw RecordingError.fileNotOpen }
        
        // Convert to data and write
        let data = Data(bytes: samples, count: samples.count * MemoryLayout<Float>.size)
        handle.write(data)
        
        sampleCount += UInt64(samples.count)
        updateMetadata()
    }
    
    public func stopRecording() throws -> RecordingMetadata {
        // Finalize file
        if format == .wav && type == .audio {
            try updateWAVHeader()
        }
        
        fileHandle?.closeFile()
        fileHandle = nil
        
        updateMetadata()
        return metadata!
    }
    
    public func pause() {
        // Pause implementation
    }
    
    public func resume() {
        // Resume implementation
    }
    
    private func updateMetadata() {
        let duration = Date().timeIntervalSince(startTime ?? Date())
        let fileSize = try? fileHandle?.seekToEnd()
        
        metadata?.duration = duration
        metadata?.fileSize = fileSize ?? 0
    }
    
    private func getFileExtension() -> String {
        switch format {
        case .wav: return "wav"
        case .flac: return "flac"
        case .rawIQ: return "iq"
        case .sigmf: return "sigmf-meta"
        }
    }
    
    private func writeWAVHeader() throws {
        // WAV header writing implementation
    }
    
    private func updateWAVHeader() throws {
        // Update WAV header with final size
    }
}

// MARK: - Recording Database

/// SQLite database for recording metadata
public class RecordingDatabase {
    private var dbPath: String
    
    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("NeuralSDR2", isDirectory: true)
        dbPath = appFolder.appendingPathComponent("recordings.db").path
        
        initializeDatabase()
    }
    
    private func initializeDatabase() {
        // Create SQLite table if not exists
        // Implementation using SQLite3
    }
    
    public func addRecording(_ metadata: RecordingMetadata) throws {
        // Insert into database
    }
    
    public func getRecordings(filter: String? = nil) -> [RecordingMetadata] {
        // Query database
        return []
    }
    
    public func deleteRecording(at path: String) throws {
        // Delete from database
    }
}

// MARK: - Errors

public enum RecordingError: Error {
    case alreadyRecording
    case notRecording
    case fileNotOpen
    case invalidFormat
    case writeError
}
