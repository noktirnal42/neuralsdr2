//
//  RecordingPanel.swift
//  NeuralSDR2
//
//  Recording control panel with start/stop/playback
//

import SwiftUI
import Foundation

struct RecordingPanel: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var recordingManager = RecordingManagerWrapper()
    
    @State private var isRecording = false
    @State private var isPlaying = false
    @State private var recordingType: RecordingType = .iq
    @State private var recordingFormat: RecordingFormat = .rawIQ
    @State private var recordingDuration: TimeInterval = 0
    @State private var showRecordings = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Recording controls
            HStack(spacing: 16) {
                // Record button
                Button(action: toggleRecording) {
                    Image(systemName: isRecording ? "stop.fill" : "record.circle")
                        .font(.title2)
                    Text(isRecording ? "Stop" : "Record")
                }
                .buttonStyle(.borderedProminent)
                .foregroundColor(isRecording ? .red : .primary)
                .disabled(appState.deviceInfo == nil)
                
                // Play button
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                    Text(isPlaying ? "Pause" : "Play")
                }
                .buttonStyle(.bordered)
                .disabled(!isRecording && !isPlaying)
                
                // Recording type selector
                Picker("Type", selection: $recordingType) {
                    Text("IQ").tag(RecordingType.iq)
                    Text("Audio").tag(RecordingType.audio)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                
                Spacer()
                
                // Duration display
                if isRecording {
                    Text(String(format: "%02d:%02d:%02d",
                         Int(recordingDuration) / 3600,
                         (Int(recordingDuration) % 3600) / 60,
                         Int(recordingDuration) % 60))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                }
                
                // Library button
                Button(action: { showRecordings = true }) {
                    Image(systemName: "list.bullet")
                    Text("Library")
                }
                .buttonStyle(.bordered)
            }
            
            // Recording status
            if isRecording {
                HStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("Recording: \(recordingType.rawValue)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Format: \(recordingFormat.rawValue)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .sheet(isPresented: $showRecordings) {
            RecordingLibraryView()
        }
        .onAppear {
            startDurationTimer()
            setupRecordingCallbacks()
        }
    }
    
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        guard let deviceInfo = appState.deviceInfo else { return }
        
        do {
            let url: URL
            if recordingType == .iq {
                url = try recordingManager.startIQRecording(
                    frequency: appState.frequency,
                    sampleRate: appState.sampleRate,
                    mode: appState.currentMode.rawValue,
                    format: recordingFormat
                )
            } else {
                url = try recordingManager.startAudioRecording(
                    frequency: appState.frequency,
                    sampleRate: 48000,
                    mode: appState.currentMode.rawValue,
                    format: recordingFormat
                )
            }
            
            isRecording = true
            appState.statusMessage = "Recording: \(url.lastPathComponent)"
        } catch {
            appState.statusMessage = "Recording error: \(error.localizedDescription)"
        }
    }
    
    private func stopRecording() {
        do {
            let metadata = try recordingManager.stopRecording()
            isRecording = false
            recordingDuration = 0
            appState.statusMessage = "Recording saved: \(metadata?.notes ?? "")"
        } catch {
            appState.statusMessage = "Stop error: \(error.localizedDescription)"
        }
    }
    
    private func togglePlayback() {
        isPlaying.toggle()
        // TODO: Implement playback from last recording
    }
    
    private func startDurationTimer() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if isRecording {
                recordingDuration += 1
            }
        }
    }
    
    private func setupRecordingCallbacks() {
        recordingManager.onRecordingStart = { metadata in
            DispatchQueue.main.async {
                appState.statusMessage = "Recording started: \(metadata.frequency / 1_000_000) MHz"
            }
        }
        
        recordingManager.onRecordingUpdate = { metadata in
            DispatchQueue.main.async {
                // Update duration display
            }
        }
        
        recordingManager.onRecordingStop = { metadata in
            DispatchQueue.main.async {
                appState.statusMessage = "Recording complete: \(metadata.fileSize) bytes"
            }
        }
    }
}

// MARK: - Recording Library View

struct RecordingLibraryView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var recordings: [RecordingMetadata] = []
    @State private var selectedRecording: RecordingMetadata?
    @State private var searchText = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                TextField("Search recordings...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                
                // Recording list
                List(selection: $selectedRecording) {
                    ForEach(recordings, id: \.filePath) { recording in
                        RecordingListItem(recording: recording)
                    }
                }
            }
            .navigationTitle("Recording Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Delete", action: deleteSelected)
                        .disabled(selectedRecording == nil)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: { dismiss() })
                }
            }
        }
        .frame(width: 800, height: 600)
        .onAppear {
            loadRecordings()
        }
    }
    
    private func loadRecordings() {
        // TODO: Load from RecordingManager
        recordings = []
    }
    
    private func deleteSelected() {
        // TODO: Delete selected recording
    }
}

struct RecordingListItem: View {
    let recording: RecordingMetadata
    
    var body: some View {
        HStack {
            // Icon based on type
            Image(systemName: "waveform")
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.filePath.components(separatedBy: "/").last ?? "Unknown")
                    .font(.system(.body, design: .monospaced))
                
                HStack(spacing: 12) {
                    Text("\(recording.frequency / 1_000_000, specifier: "%.1f") MHz")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(recording.mode)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(formatDuration(recording.duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(formatSize(recording.fileSize))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if !recording.notes.isEmpty {
                    Text(recording.notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    private func formatSize(_ size: UInt64) -> String {
        let mb = Double(size) / (1024 * 1024)
        if mb >= 1 {
            return String(format: "%.1f MB", mb)
        } else {
            let kb = Double(size) / 1024
            return String(format: "%.1f KB", kb)
        }
    }
}

// MARK: - Recording Manager Wrapper

class RecordingManagerWrapper: ObservableObject {
    private var manager: RecordingManager?
    
    var onRecordingStart: ((RecordingMetadata) -> Void)?
    var onRecordingUpdate: ((RecordingMetadata) -> Void)?
    var onRecordingStop: ((RecordingMetadata) -> Void)?
    
    init() {
        manager = RecordingManager()
        setupCallbacks()
    }
    
    private func setupCallbacks() {
        manager?.onRecordingStart = { [weak self] metadata in
            self?.onRecordingStart?(metadata)
        }
        manager?.onRecordingUpdate = { [weak self] metadata in
            self?.onRecordingUpdate?(metadata)
        }
        manager?.onRecordingStop = { [weak self] metadata in
            self?.onRecordingStop?(metadata)
        }
    }
    
    func startIQRecording(frequency: Double, sampleRate: Double, mode: String, format: RecordingFormat) throws -> URL {
        try manager?.startIQRecording(frequency: frequency, sampleRate: sampleRate, mode: mode, format: format) ?? URL(fileURLWithPath: "")
    }
    
    func startAudioRecording(frequency: Double, sampleRate: Double, mode: String, format: RecordingFormat) throws -> URL {
        try manager?.startAudioRecording(frequency: frequency, sampleRate: sampleRate, mode: mode, format: format) ?? URL(fileURLWithPath: "")
    }
    
    func stopRecording() throws -> RecordingMetadata? {
        try manager?.stopRecording()
    }
}

#Preview {
    RecordingPanel()
        .environmentObject(AppState())
}
