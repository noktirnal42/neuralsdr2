//
// AppState.swift
// NeuralSDR2 - Application State
//
// Central observable state managing SDR device, DSP pipeline, and UI bindings
// Phase 7: USB hot-plug monitoring, device state tracking, auto-reconnect
//

import SwiftUI
import AppKit
import CoreLocation

private struct AppSessionPreferences: Codable {
    var workspace: String
    var frequency: Double
    var sampleRate: Double
    var currentMode: String
    var bandwidth: Double
    var agcEnabled: Bool
    var tunerGain: Double
    var squelchEnabled: Bool
    var squelchThreshold: Float
    var dump978Enabled: Bool
    var dump978Host: String
    var dump978Port: UInt16
    var mapStyle: String
    var weatherOverlayEnabled: Bool
    var showGroundTracks: Bool
    var showOrbits: Bool
    var showDecodedNOAA: Bool
    var observerLatitude: Double
    var observerLongitude: Double
    var useCurrentLocation: Bool
    var liveDopplerRetuneEnabled: Bool
    var minimumNOAAQualityTier: String
    var satelliteProfiles: [String: SatelliteProfile]

    init(
        workspace: String = AppState.Workspace.radio.rawValue,
        frequency: Double = 1_090_000_000,
        sampleRate: Double = 2_048_000,
        currentMode: String = DemodulatorType.NFM.rawValue,
        bandwidth: Double = 15_000,
        agcEnabled: Bool = true,
        tunerGain: Double = 35.0,
        squelchEnabled: Bool = false,
        squelchThreshold: Float = -90.0,
        dump978Enabled: Bool = false,
        dump978Host: String = "127.0.0.1",
        dump978Port: UInt16 = 30978,
        mapStyle: String = MapState.MapStyle.hybrid.rawValue,
        weatherOverlayEnabled: Bool = false,
        showGroundTracks: Bool = true,
        showOrbits: Bool = true,
        showDecodedNOAA: Bool = true,
        observerLatitude: Double = 37.7749,
        observerLongitude: Double = -122.4194,
        useCurrentLocation: Bool = true,
        liveDopplerRetuneEnabled: Bool = false,
        minimumNOAAQualityTier: String = NOAAArtifactQualityTier.weak.rawValue,
        satelliteProfiles: [String: SatelliteProfile] = [:]
    ) {
        self.workspace = workspace
        self.frequency = frequency
        self.sampleRate = sampleRate
        self.currentMode = currentMode
        self.bandwidth = bandwidth
        self.agcEnabled = agcEnabled
        self.tunerGain = tunerGain
        self.squelchEnabled = squelchEnabled
        self.squelchThreshold = squelchThreshold
        self.dump978Enabled = dump978Enabled
        self.dump978Host = dump978Host
        self.dump978Port = dump978Port
        self.mapStyle = mapStyle
        self.weatherOverlayEnabled = weatherOverlayEnabled
        self.showGroundTracks = showGroundTracks
        self.showOrbits = showOrbits
        self.showDecodedNOAA = showDecodedNOAA
        self.observerLatitude = observerLatitude
        self.observerLongitude = observerLongitude
        self.useCurrentLocation = useCurrentLocation
        self.liveDopplerRetuneEnabled = liveDopplerRetuneEnabled
        self.minimumNOAAQualityTier = minimumNOAAQualityTier
        self.satelliteProfiles = satelliteProfiles
    }

    private enum CodingKeys: String, CodingKey {
        case workspace
        case frequency
        case sampleRate
        case currentMode
        case bandwidth
        case agcEnabled
        case tunerGain
        case squelchEnabled
        case squelchThreshold
        case dump978Enabled
        case dump978Host
        case dump978Port
        case mapStyle
        case weatherOverlayEnabled
        case showGroundTracks
        case showOrbits
        case showDecodedNOAA
        case observerLatitude
        case observerLongitude
        case useCurrentLocation
        case liveDopplerRetuneEnabled
        case minimumNOAAQualityTier
        case satelliteProfiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            workspace: try container.decodeIfPresent(String.self, forKey: .workspace) ?? AppState.Workspace.radio.rawValue,
            frequency: try container.decodeIfPresent(Double.self, forKey: .frequency) ?? 1_090_000_000,
            sampleRate: try container.decodeIfPresent(Double.self, forKey: .sampleRate) ?? 2_048_000,
            currentMode: try container.decodeIfPresent(String.self, forKey: .currentMode) ?? DemodulatorType.NFM.rawValue,
            bandwidth: try container.decodeIfPresent(Double.self, forKey: .bandwidth) ?? 15_000,
            agcEnabled: try container.decodeIfPresent(Bool.self, forKey: .agcEnabled) ?? true,
            tunerGain: try container.decodeIfPresent(Double.self, forKey: .tunerGain) ?? 35.0,
            squelchEnabled: try container.decodeIfPresent(Bool.self, forKey: .squelchEnabled) ?? false,
            squelchThreshold: try container.decodeIfPresent(Float.self, forKey: .squelchThreshold) ?? -90.0,
            dump978Enabled: try container.decodeIfPresent(Bool.self, forKey: .dump978Enabled) ?? false,
            dump978Host: try container.decodeIfPresent(String.self, forKey: .dump978Host) ?? "127.0.0.1",
            dump978Port: try container.decodeIfPresent(UInt16.self, forKey: .dump978Port) ?? 30978,
            mapStyle: try container.decodeIfPresent(String.self, forKey: .mapStyle) ?? MapState.MapStyle.hybrid.rawValue,
            weatherOverlayEnabled: try container.decodeIfPresent(Bool.self, forKey: .weatherOverlayEnabled) ?? false,
            showGroundTracks: try container.decodeIfPresent(Bool.self, forKey: .showGroundTracks) ?? true,
            showOrbits: try container.decodeIfPresent(Bool.self, forKey: .showOrbits) ?? true,
            showDecodedNOAA: try container.decodeIfPresent(Bool.self, forKey: .showDecodedNOAA) ?? true,
            observerLatitude: try container.decodeIfPresent(Double.self, forKey: .observerLatitude) ?? 37.7749,
            observerLongitude: try container.decodeIfPresent(Double.self, forKey: .observerLongitude) ?? -122.4194,
            useCurrentLocation: try container.decodeIfPresent(Bool.self, forKey: .useCurrentLocation) ?? true,
            liveDopplerRetuneEnabled: try container.decodeIfPresent(Bool.self, forKey: .liveDopplerRetuneEnabled) ?? false,
            minimumNOAAQualityTier: try container.decodeIfPresent(String.self, forKey: .minimumNOAAQualityTier) ?? NOAAArtifactQualityTier.weak.rawValue,
            satelliteProfiles: try container.decodeIfPresent([String: SatelliteProfile].self, forKey: .satelliteProfiles) ?? [:]
        )
    }
}

private struct SatellitePreset {
    let frequency: Double
    let mode: DemodulatorType
    let bandwidth: Double
    let receivePreset: SatelliteReceivePreset
}

private struct SatelliteProfile: Codable {
    var frequency: Double
    var mode: DemodulatorType
    var bandwidth: Double
    var receivePreset: SatelliteReceivePreset
}

public enum NOAAArtifactQualityTier: String {
    case strong = "Strong"
    case usable = "Usable"
    case weak = "Weak"

    var rank: Int {
        switch self {
        case .strong: return 2
        case .usable: return 1
        case .weak: return 0
        }
    }
}

public enum SatelliteReceivePreset: String, CaseIterable, Codable {
    case noaaAPT = "NOAA APT"
    case fmVoice = "FM Voice"
    case packet = "Packet"
    case digitalVoice = "Digital Voice"

    var preferredRecordingKind: SatelliteRecordingKind {
        switch self {
        case .noaaAPT, .fmVoice, .packet:
            return .audio
        case .digitalVoice:
            return .iq
        }
    }
}

public enum SatelliteRecordingKind: String, CaseIterable, Codable {
    case iq = "IQ"
    case audio = "Audio"
}

private struct ArmedSatelliteRecording {
    let satellite: String
    let aos: Date
    let los: Date
    let recordingKind: SatelliteRecordingKind
    let receivePreset: SatelliteReceivePreset
}

public struct PostPassActionItem: Identifiable {
    public let id = UUID()
    public let satellite: String
    public let preset: SatelliteReceivePreset
    public let recordingKind: SatelliteRecordingKind
    public let filePath: String
    public let actionLabel: String
    public let detailText: String?
    public let sourceFilePath: String?
    public let createdAt: Date
}

// MARK: - App State

public class AppState: ObservableObject {
    private static let preferencesKey = "com.neuralsdr2.session.preferences"
    public static let shared = AppState()
    public enum Workspace: String, CaseIterable {
        case radio = "Radio"
        case aircraft = "Aircraft"
        case satellites = "Satellites"
        case earth = "3D Earth"
        case recordings = "Recordings"
    }

    @Published public var isRunning = false
    @Published public var deviceInfo: RTLSDRDeviceInfo? = nil
    @Published public var devices: [RTLSDRDeviceInfo] = []
    @Published public var frequency: Double = 1090_000_000
    @Published public var sampleRate: Double = 2_048_000
    @Published public var displayMode: DisplayMode = .combined
    @Published public var currentMode: DemodulatorType = .NFM
    @Published public var signalLevel: Float = -120.0
    @Published public var spectrumData: [Float] = []
    @Published public var statusMessage = "Ready"
    @Published public var bandwidth: Double = 15000
    @Published public var volume: Float = 0.8
    @Published public var isMuted: Bool = false
    @Published public var agcEnabled: Bool = true
    @Published public var squelchEnabled: Bool = false
    @Published public var isRecording: Bool = false
    @Published public var rdsData = RDSState()
    @Published public var deviceState: RTLSDRDevice.DeviceState = .disconnected
    @Published public var workspace: Workspace = .radio
    @Published public var tunerGain: Double = 35.0
    @Published public var squelchThreshold: Float = -90.0
    @Published public var dump978Enabled: Bool = false
    @Published public var dump978Host: String = "127.0.0.1"
    @Published public var dump978Port: UInt16 = 30978
    @Published public var satelliteDopplerStatus: String = "Not tracking Doppler"
    @Published public var activeSatelliteTarget: String?
    @Published public var armedSatelliteRecording: String?
    @Published public var liveDopplerRetuneEnabled = false
    @Published public var satelliteRecordingStatus: String = "No satellite recording armed"
    @Published public var armedSatelliteQueue: [String] = []
    @Published public var latestAPTRecording: PostPassActionItem?
    @Published public var latestPacketRecording: PostPassActionItem?
    @Published public var decodedAPTArtifacts: [APTDecodedArtifact] = []
    @Published public var decodedPacketArtifacts: [PacketDecodedArtifact] = []
    @Published public var decoderHandoffQueue: [PostPassActionItem] = []
    @Published public var lastPostPassActionMessage: String = "No post-pass action run yet"
    @Published public var recordingLibraryRefreshToken: Int = 0

public var rtlDevice: RTLSDRDevice?
public var dspPipeline: DSPPipeline?
public var audioEngine: AudioOutputEngine?
public var spectrumAnalyzer: SpectrumAnalyzer?
public var performanceMonitor: PerformanceMonitor?
    public var bookmarkManager = BookmarkManager()
    public var layoutManager = LayoutManager()
    public var recordingManagerWrapper: RecordingManagerWrapper?
    public var usbMonitor: USBDeviceMonitor?
    public let mapState: MapState
    public let mapIntegrationManager: MapIntegrationManager
    private let startupQueue = DispatchQueue(label: "com.neuralsdr2.app.startup", qos: .userInitiated)
    private let hardwareQueue = DispatchQueue(label: "com.neuralsdr2.app.hardware", qos: .userInitiated)
    private var satelliteUpdateTimer: Timer?
    private var tleRefreshTask: Task<Void, Never>?
    private var armedSatelliteRecordingWindows: [ArmedSatelliteRecording] = []
    private var autoSatelliteRecordingActive = false
    private var satelliteProfiles: [String: SatelliteProfile] = [:]
    private var activeSatelliteBaseFrequency: Double?
    private var mapSubsystemsInitialized = false

    public enum DisplayMode {
        case spectrum
        case waterfall
        case combined
    }

public init() {
        let state = MapState()
        self.mapState = state
        self.mapIntegrationManager = MapIntegrationManager(mapState: state)
        self.mapState.onObserverLocationChanged = { [weak self] lat, lon in
            self?.mapIntegrationManager.updateObserverLocation(lat: lat, lon: lon)
        }
        loadPreferences()
        setupSpectrumAnalyzer()
        performanceMonitor = PerformanceMonitor()
        DispatchQueue.main.async { [weak self] in
            self?.completeDeferredStartup()
        }
}

    private func completeDeferredStartup() {
        refreshDecodedAPTArtifacts()
        refreshDecodedPacketArtifacts()

        startupQueue.async { [weak self] in
            guard let self else { return }
            self.setupAudio()
            self.setupUSBMonitor()
            let devices = RTLSDRDevice.enumerateDevices()

            DispatchQueue.main.async {
                self.devices = devices
                if let firstDevice = devices.first {
                    self.deviceInfo = firstDevice
                    self.statusMessage = "Found \(devices.count) RTL-SDR device(s)"
                } else if self.statusMessage == "Ready" || self.statusMessage.hasPrefix("Found ") {
                    self.deviceInfo = nil
                    self.statusMessage = "No RTL-SDR devices found"
                } else {
                    self.deviceInfo = nil
                }
            }
        }
    }

    private func setupAudio() {
        do {
            audioEngine = AudioOutputEngine()
            try audioEngine?.initialize(sampleRate: 64000, channels: 2, bufferSize: 512)
        } catch {
            statusMessage = "Audio init error: \(error.localizedDescription)"
        }
    }

    private func setupSpectrumAnalyzer() {
        spectrumAnalyzer = SpectrumAnalyzer(fftSize: 2048, sampleRate: sampleRate, centerFrequency: frequency, useGPU: false)
    }

    private func setupUSBMonitor() {
        usbMonitor = USBDeviceMonitor()
        usbMonitor?.onDeviceAdded = { [weak self] _ in
            DispatchQueue.main.async {
                self?.scanForDevices()
            }
        }
        usbMonitor?.onDeviceRemoved = { [weak self] _ in
            DispatchQueue.main.async {
                if self?.isRunning == true {
                    self?.stopSDR()
                    self?.statusMessage = "RTL-SDR device removed"
                }
                self?.scanForDevices()
            }
        }
        usbMonitor?.start()
    }

    public func scanForDevices() {
        hardwareQueue.async { [weak self] in
            guard let self else { return }
            let devices = RTLSDRDevice.enumerateDevices()
            DispatchQueue.main.async {
                self.devices = devices
                if devices.count > 0 {
                    self.deviceInfo = devices.first
                    self.statusMessage = "Found \(devices.count) RTL-SDR device(s)"
                } else {
                    self.deviceInfo = nil
                    self.statusMessage = "No RTL-SDR devices found"
                }
            }
        }
    }

    public func startSDR() {
        guard deviceInfo != nil else {
            statusMessage = "No device selected"
            return
        }

        statusMessage = "Starting SDR..."
        hardwareQueue.async { [weak self] in
            guard let self else { return }
            do {
                let device = RTLSDRDevice()
                device.onStateChanged = { [weak self] state in
                    DispatchQueue.main.async {
                        self?.deviceState = state
                    }
                }
                device.onError = { [weak self] message in
                    DispatchQueue.main.async {
                        self?.statusMessage = "Error: \(message)"
                    }
                }
                try device.open(index: 0)

                var config = RTLSDRConfig()
                config.centerFrequency = self.frequency
                config.sampleRate = self.sampleRate
                config.gainMode = self.agcEnabled
                config.tunerGain = self.tunerGain
                try device.configure(config)

                let pipeline = DSPPipeline(sampleRate: self.sampleRate, centerFrequency: self.frequency)
                pipeline.setDemodulator(self.currentMode)

                let pipelineRate = pipeline.audioSampleRate
                self.audioEngine?.stop()
                try self.audioEngine?.initialize(sampleRate: pipelineRate, channels: 2, bufferSize: 512)

                pipeline.onSpectrumUpdate { [weak self] spectrum in
                    DispatchQueue.main.async {
                        self?.spectrumData = spectrum
                        self?.updateSignalLevel(spectrum: spectrum)
                    }
                }

                pipeline.onAudioOutput { [weak self] audio in
                    guard let self else { return }
                    if self.recordingManagerWrapper?.currentRecordingType == .audio {
                        try? self.recordingManagerWrapper?.writeAudioSamples(audio)
                    }
                    self.audioEngine?.queueSamples(audio)
                }

                try self.audioEngine?.start()

                DispatchQueue.main.async {
                    self.rtlDevice = device
                    self.dspPipeline = pipeline
                    self.isRunning = true
                    self.statusMessage = "Running: \(self.currentMode.rawValue) at \(self.formatFrequency(self.frequency))"
                    self.setupRDSCallbacks()
                }

                try device.startStreaming { [weak self, weak pipeline] samples in
                    guard let self else {
                        pipeline?.process(samples: samples)
                        return
                    }
                    if self.recordingManagerWrapper?.currentRecordingType == .iq {
                        try? self.recordingManagerWrapper?.writeIQSamples(samples)
                    }
                    pipeline?.process(samples: samples)
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusMessage = "Error: \(error.localizedDescription)"
                    self.isRunning = false
                    self.deviceState = .error
                }
            }
        }
    }

    public func stopSDR() {
        let device = rtlDevice
        rtlDevice = nil
        dspPipeline = nil
        isRunning = false
        deviceState = .disconnected
        statusMessage = "Stopping..."
        spectrumData = []

        hardwareQueue.async { [weak self] in
            device?.cancelReconnect()
            device?.stopStreaming()
            device?.close()

            self?.audioEngine?.stop()
            self?.audioEngine?.clearBuffer()

            DispatchQueue.main.async {
                self?.statusMessage = "Stopped"
            }
        }
    }

    public func setFrequency(_ newFrequency: Double) {
        frequency = newFrequency
        if isRunning {
            do {
                try reconfigureDevice { config in
                    config.centerFrequency = frequency
                }
                dspPipeline?.centerFrequency = frequency
                statusMessage = "Tuned to \(formatFrequency(frequency))"
            } catch {
                statusMessage = "Tune error: \(error.localizedDescription)"
            }
        }
        savePreferences()
    }

    public func setMode(_ mode: DemodulatorType) {
        currentMode = mode
        dspPipeline?.setDemodulator(mode)

        if isRunning, let pipelineRate = dspPipeline?.audioSampleRate {
            do {
                audioEngine?.stop()
                audioEngine?.clearBuffer()
                try audioEngine?.initialize(sampleRate: pipelineRate, channels: 2, bufferSize: 512)
                try audioEngine?.start()
            } catch {
                statusMessage = "Audio reconfigure error: \(error.localizedDescription)"
            }
        }

        statusMessage = "Mode: \(mode.rawValue)"
        savePreferences()
    }

    public func setBandwidth(_ bw: Double) {
        bandwidth = bw
        dspPipeline?.setBandwidth(bw)
        statusMessage = "Bandwidth: \(formatFrequency(bw))"
        savePreferences()
    }

    public func setMuted(_ muted: Bool) {
        isMuted = muted
        if audioEngine?.isMuted != muted {
            try? audioEngine?.toggleMute()
        }
        statusMessage = muted ? "Speaker monitoring muted" : "Speaker monitoring live"
    }

    public func toggleMuted() {
        setMuted(!isMuted)
    }

    public func setAGCEnabled(_ enabled: Bool) {
        agcEnabled = enabled
        do {
            try reconfigureDevice { config in
                config.gainMode = enabled
                config.tunerGain = tunerGain
            }
            statusMessage = enabled ? "AGC enabled" : "Manual gain enabled"
        } catch {
            statusMessage = "Gain config error: \(error.localizedDescription)"
        }
        savePreferences()
    }

    public func setTunerGain(_ gain: Double) {
        tunerGain = gain
        guard !agcEnabled else { return }
        do {
            try reconfigureDevice { config in
                config.gainMode = false
                config.tunerGain = gain
            }
            statusMessage = String(format: "RF gain %.1f dB", gain)
        } catch {
            statusMessage = "Gain config error: \(error.localizedDescription)"
        }
        savePreferences()
    }

    public func setSquelchEnabled(_ enabled: Bool) {
        squelchEnabled = enabled
        dspPipeline?.setSquelchEnabled(enabled)
        statusMessage = enabled ? "Squelch enabled" : "Squelch disabled"
        savePreferences()
    }

    public func setSquelchThreshold(_ threshold: Float) {
        squelchThreshold = threshold
        dspPipeline?.setSquelchThreshold(threshold)
        savePreferences()
    }

    public func setWorkspace(_ workspace: Workspace) {
        self.workspace = workspace
        ensureWorkspaceInfrastructure(for: workspace)
        savePreferences()
    }

    public func setWeatherOverlayEnabled(_ enabled: Bool) {
        ensureWorkspaceInfrastructure(for: .aircraft)
        mapState.weatherOverlayEnabled = enabled
        dump978Enabled = enabled
        mapIntegrationManager.weatherRadarManager.setEnabled(enabled)
        if enabled {
            mapIntegrationManager.weatherRadarManager.connectToDump978(host: dump978Host, port: dump978Port)
            statusMessage = "Weather overlay enabled"
        } else {
            statusMessage = "Weather overlay disabled"
        }
        savePreferences()
    }

    public func connectToDump978() {
        ensureWorkspaceInfrastructure(for: .aircraft)
        mapIntegrationManager.weatherRadarManager.connectToDump978(host: dump978Host, port: dump978Port)
        savePreferences()
    }

    public func setDump978Host(_ host: String) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        dump978Host = trimmedHost.isEmpty ? "127.0.0.1" : trimmedHost
        if mapState.weatherOverlayEnabled {
            mapIntegrationManager.weatherRadarManager.connectToDump978(host: dump978Host, port: dump978Port)
        }
        savePreferences()
    }

    public func setDump978Port(_ port: UInt16) {
        dump978Port = port
        if mapState.weatherOverlayEnabled {
            mapIntegrationManager.weatherRadarManager.connectToDump978(host: dump978Host, port: dump978Port)
        }
        savePreferences()
    }

    public func showAircraftWorkspace() {
        workspace = .aircraft
        ensureWorkspaceInfrastructure(for: .aircraft)
        frequency = 1_090_000_000
        currentMode = .NFM
        bandwidth = 1_000_000
        dspPipeline?.setBandwidth(bandwidth)
        statusMessage = "Aircraft workspace ready"
        savePreferences()
    }

    public func showSatelliteWorkspace() {
        workspace = .satellites
        ensureWorkspaceInfrastructure(for: .satellites)
        frequency = 137_100_000
        currentMode = .WFM
        bandwidth = 40_000
        dspPipeline?.setBandwidth(bandwidth)
        statusMessage = "Satellite workspace ready"
        savePreferences()
    }

    public func tuneToSatellite(_ satellite: SatelliteTrack) {
        let preset = satelliteProfile(for: satellite.name)
        workspace = .satellites
        ensureWorkspaceInfrastructure(for: .satellites)
        frequency = preset.frequency
        currentMode = preset.mode
        bandwidth = preset.bandwidth
        activeSatelliteTarget = satellite.name
        activeSatelliteBaseFrequency = preset.frequency
        dspPipeline?.setDemodulator(currentMode)
        dspPipeline?.setBandwidth(bandwidth)

        if isRunning {
            do {
                try reconfigureDevice { config in
                    config.centerFrequency = frequency
                }
                dspPipeline?.centerFrequency = frequency
            } catch {
                statusMessage = "Satellite tune error: \(error.localizedDescription)"
            }
        }

        updateSatelliteDopplerStatus()
        statusMessage = "Tracking \(satellite.name) at \(formatFrequency(frequency))"
        savePreferences()
    }

    public func satelliteProfile(for name: String) -> (frequency: Double, mode: DemodulatorType, bandwidth: Double, receivePreset: SatelliteReceivePreset) {
        let profile = satelliteProfiles[name] ?? defaultSatelliteProfile(for: name)
        return (profile.frequency, profile.mode, profile.bandwidth, profile.receivePreset)
    }

    public func updateSatelliteProfile(
        name: String,
        frequency: Double? = nil,
        mode: DemodulatorType? = nil,
        bandwidth: Double? = nil,
        receivePreset: SatelliteReceivePreset? = nil
    ) {
        var profile = satelliteProfiles[name] ?? defaultSatelliteProfile(for: name)
        if let frequency {
            profile.frequency = frequency
        }
        if let mode {
            profile.mode = mode
        }
        if let bandwidth {
            profile.bandwidth = bandwidth
        }
        if let receivePreset {
            profile.receivePreset = receivePreset
        }
        satelliteProfiles[name] = profile

        if activeSatelliteTarget == name {
            activeSatelliteBaseFrequency = profile.frequency
            currentMode = profile.mode
            self.bandwidth = profile.bandwidth
            if !liveDopplerRetuneEnabled {
                self.frequency = profile.frequency
            }
            dspPipeline?.setDemodulator(profile.mode)
            dspPipeline?.setBandwidth(profile.bandwidth)
            if isRunning {
                do {
                    try reconfigureDevice { config in
                        config.centerFrequency = self.frequency
                    }
                    dspPipeline?.centerFrequency = self.frequency
                } catch {
                    statusMessage = "Satellite profile update error: \(error.localizedDescription)"
                }
            }
            updateSatelliteDopplerStatus()
        }

        savePreferences()
    }

    public func setLiveDopplerRetuneEnabled(_ enabled: Bool) {
        liveDopplerRetuneEnabled = enabled
        if !enabled, let target = activeSatelliteTarget {
            let profile = satelliteProfile(for: target)
            frequency = profile.frequency
            activeSatelliteBaseFrequency = profile.frequency
            if isRunning {
                do {
                    try reconfigureDevice { config in
                        config.centerFrequency = frequency
                    }
                    dspPipeline?.centerFrequency = frequency
                } catch {
                    statusMessage = "Doppler retune disable error: \(error.localizedDescription)"
                }
            }
        }
        updateSatelliteDopplerStatus()
        savePreferences()
    }

    public func armRecordingForNextPass(_ satellite: SatelliteTrack) {
        guard let pass = satellite.nextPass else {
            statusMessage = "No upcoming pass available for \(satellite.name)"
            return
        }

        let profile = satelliteProfile(for: satellite.name)
        let queuedWindow = ArmedSatelliteRecording(
            satellite: satellite.name,
            aos: pass.aos,
            los: pass.los,
            recordingKind: profile.receivePreset.preferredRecordingKind,
            receivePreset: profile.receivePreset
        )

        armedSatelliteRecordingWindows.removeAll { $0.satellite == satellite.name }
        armedSatelliteRecordingWindows.append(queuedWindow)
        armedSatelliteRecordingWindows.sort { $0.aos < $1.aos }
        armedSatelliteQueue = armedSatelliteRecordingWindows.map { "\($0.satellite) (\($0.recordingKind.rawValue))" }
        armedSatelliteRecording = armedSatelliteRecordingWindows.first?.satellite
        satelliteRecordingStatus = "Queued \(profile.receivePreset.preferredRecordingKind.rawValue) recording for \(satellite.name)"
        statusMessage = "Armed recording for \(satellite.name) at \(pass.aos.formatted(date: .omitted, time: .shortened))"
    }

    public func cancelArmedSatelliteRecording() {
        armedSatelliteRecordingWindows.removeAll()
        armedSatelliteRecording = nil
        armedSatelliteQueue = []
        autoSatelliteRecordingActive = false
        satelliteRecordingStatus = "No satellite recording armed"
        statusMessage = "Satellite recording automation cleared"
    }

    public func showBroadcastWorkspace() {
        workspace = .radio
        frequency = 100_700_000
        currentMode = .WFM
        bandwidth = 200_000
        dspPipeline?.setBandwidth(bandwidth)
        statusMessage = "Broadcast workspace ready"
        savePreferences()
    }

    private func updateSignalLevel(spectrum: [Float]) {
        if !spectrum.isEmpty {
            let avgPower = spectrum.reduce(0, +) / Float(spectrum.count)
            signalLevel = avgPower
        }
    }

    private func updateSatelliteDopplerStatus() {
        guard let target = activeSatelliteTarget,
              let tle = mapIntegrationManager.tleManager.getTLE(name: target) else {
            satelliteDopplerStatus = "Not tracking Doppler"
            return
        }

        let propagator = SGP4Propagator(tle: tle)
        let profile = satelliteProfile(for: target)
        let baseFrequency = activeSatelliteBaseFrequency ?? profile.frequency
        let position = propagator.getPosition(
            at: Date(),
            observerLat: mapState.observerLatitude,
            observerLon: mapState.observerLongitude
        )
        let shift = DopplerCorrection().calculateSatelliteShift(satellite: position, frequency: baseFrequency)
        let correctedFrequency = baseFrequency + shift

        if liveDopplerRetuneEnabled {
            frequency = correctedFrequency
            if isRunning {
                do {
                    try reconfigureDevice { config in
                        config.centerFrequency = correctedFrequency
                    }
                    dspPipeline?.centerFrequency = correctedFrequency
                } catch {
                    statusMessage = "Live Doppler retune error: \(error.localizedDescription)"
                }
            }
        }

        satelliteDopplerStatus = String(
            format: "%@ %@ • shift %@ Hz • %@",
            target,
            position.elevation > 0 ? "visible" : "below horizon",
            formatSignedFrequency(shift),
            liveDopplerRetuneEnabled ? "tracking \(formatFrequency(correctedFrequency))" : "corrected \(formatFrequency(correctedFrequency))"
        )
    }

    private func checkArmedSatelliteRecording() {
        guard let window = armedSatelliteRecordingWindows.first else { return }
        let now = Date()

        if now >= window.los {
            if autoSatelliteRecordingActive && isRecording {
                do {
                    let metadata = try recordingManagerWrapper?.stopRecording()
                    isRecording = false
                    if let metadata {
                        refreshRecordingLibrary()
                        runPostPassActions(for: window, metadata: metadata)
                    }
                    satelliteRecordingStatus = completionStatus(for: window)
                    statusMessage = "Satellite pass recording saved for \(window.satellite)"
                } catch {
                    statusMessage = "Satellite recording stop error: \(error.localizedDescription)"
                }
            }
            armedSatelliteRecordingWindows.removeFirst()
            armedSatelliteQueue = armedSatelliteRecordingWindows.map { "\($0.satellite) (\($0.recordingKind.rawValue))" }
            armedSatelliteRecording = armedSatelliteRecordingWindows.first?.satellite
            autoSatelliteRecordingActive = false
            return
        }

        guard now >= window.aos, !autoSatelliteRecordingActive, !isRecording else { return }

        if recordingManagerWrapper == nil {
            recordingManagerWrapper = RecordingManagerWrapper()
        }

        do {
            let note = recordingNotes(for: window)
            let tags = recordingTags(for: window)

            switch window.recordingKind {
            case .iq:
                _ = try recordingManagerWrapper?.startIQRecording(
                    frequency: frequency,
                    sampleRate: sampleRate,
                    mode: currentMode.rawValue,
                    format: .rawIQ,
                    notes: note,
                    tags: tags
                )
            case .audio:
                _ = try recordingManagerWrapper?.startAudioRecording(
                    frequency: frequency,
                    sampleRate: dspPipeline?.audioSampleRate ?? 48_000,
                    mode: currentMode.rawValue,
                    format: .wav,
                    notes: note,
                    tags: tags
                )
            }
            isRecording = true
            autoSatelliteRecordingActive = true
            satelliteRecordingStatus = "Recording \(window.recordingKind.rawValue) during \(window.satellite) pass"
            statusMessage = "Satellite pass recording started for \(window.satellite)"
        } catch {
            statusMessage = "Satellite recording start error: \(error.localizedDescription)"
        }
    }

    private func recordingNotes(for window: ArmedSatelliteRecording) -> String {
        "\(window.receivePreset.rawValue) pass for \(window.satellite)"
    }

    private func recordingTags(for window: ArmedSatelliteRecording) -> [String] {
        ["satellite", window.satellite, window.receivePreset.rawValue, window.recordingKind.rawValue]
    }

    private func completionStatus(for window: ArmedSatelliteRecording) -> String {
        switch window.receivePreset {
        case .noaaAPT:
            return "Saved \(window.recordingKind.rawValue) recording for \(window.satellite) • ready for APT image workflow"
        case .packet, .digitalVoice:
            return "Saved \(window.recordingKind.rawValue) recording for \(window.satellite) • ready for internal decoder"
        case .fmVoice:
            return "Saved \(window.recordingKind.rawValue) recording for \(window.satellite)"
        }
    }

    private func runPostPassActions(for window: ArmedSatelliteRecording, metadata: RecordingMetadata) {
        switch window.receivePreset {
        case .noaaAPT:
            do {
                let decodeContext = noaaDecodeContext(for: window.satellite)
                let result = try APTImageDecoder.decodeRecording(
                    at: URL(fileURLWithPath: metadata.filePath),
                    satellite: window.satellite,
                    context: decodeContext
                )
                let item = PostPassActionItem(
                    satellite: window.satellite,
                    preset: window.receivePreset,
                    recordingKind: window.recordingKind,
                    filePath: result.imageURL.path,
                    actionLabel: "Open decoded APT image",
                    detailText: String(
                        format: "Decoded %d lines • sync %.2f • jitter %.1f • balance %+.2f • telem %.2f • sep %.2f • cal %.2f",
                        result.lineCount,
                        result.syncQuality,
                        result.lineJitter,
                        result.channelBalance,
                        result.telemetryContrast,
                        result.channelSeparation,
                        result.calibrationSpread
                    ),
                    sourceFilePath: metadata.filePath,
                    createdAt: result.createdAt
                )
                latestAPTRecording = item
                refreshRecordingLibrary(
                    selectWorkspace: true,
                    message: "Decoded NOAA APT pass for \(window.satellite) and surfaced it in Library"
                )
            } catch {
                lastPostPassActionMessage = "APT decode failed for \(window.satellite): \(error.localizedDescription)"
            }
        case .packet:
            do {
                let result = try PacketAudioDecoder.decodeRecording(
                    at: URL(fileURLWithPath: metadata.filePath),
                    satellite: window.satellite
                )
                let item = PostPassActionItem(
                    satellite: window.satellite,
                    preset: window.receivePreset,
                    recordingKind: window.recordingKind,
                    filePath: result.reportURL.path,
                    actionLabel: "Open packet report",
                    detailText: String(
                        format: "Packet %.0f%% • flags %d • frames %d • %.1f/%.1f kHz",
                        result.confidence * 100,
                        result.hdlcFlagCount,
                        result.decodedFrames.count,
                        result.markFrequency / 1000,
                        result.spaceFrequency / 1000
                    ),
                    sourceFilePath: metadata.filePath,
                    createdAt: result.createdAt
                )
                latestPacketRecording = item
                refreshRecordingLibrary(
                    selectWorkspace: true,
                    message: "Decoded packet pass for \(window.satellite) and surfaced it in Library"
                )
            } catch {
                lastPostPassActionMessage = "Packet decode failed for \(window.satellite): \(error.localizedDescription)"
            }
        case .digitalVoice:
            let item = PostPassActionItem(
                satellite: window.satellite,
                preset: window.receivePreset,
                recordingKind: window.recordingKind,
                filePath: metadata.filePath,
                actionLabel: "Awaiting internal decoder",
                detailText: pendingDecoderDetail(for: window.receivePreset),
                sourceFilePath: nil,
                createdAt: metadata.timestamp
            )
            decoderHandoffQueue.insert(item, at: 0)
            refreshRecordingLibrary(
                selectWorkspace: true,
                message: "Saved digital voice pass for \(window.satellite) to Library"
            )
        case .fmVoice:
            refreshRecordingLibrary(
                selectWorkspace: true,
                message: "Saved FM voice pass for \(window.satellite) to Library"
            )
            break
        }
    }

    private func postPassActionLabel(for preset: SatelliteReceivePreset) -> String {
        switch preset {
        case .noaaAPT:
            return "Open latest APT audio"
        case .packet:
            return "Open latest packet report"
        case .digitalVoice:
            return "Queue for digital voice decoder"
        case .fmVoice:
            return "Review saved audio"
        }
    }

    private func pendingDecoderDetail(for preset: SatelliteReceivePreset) -> String {
        switch preset {
        case .noaaAPT:
            return "Internal APT image decode complete"
        case .packet:
            return "Internal packet decode complete"
        case .digitalVoice:
            return "Internal digital voice decoder not implemented yet"
        case .fmVoice:
            return "Saved internal audio recording"
        }
    }

    public func executePostPassAction(_ item: PostPassActionItem) {
        let url = URL(fileURLWithPath: item.filePath)
        switch item.preset {
        case .noaaAPT:
            NSWorkspace.shared.open(url)
            lastPostPassActionMessage = "Opened decoded NOAA APT image"
        case .packet:
            NSWorkspace.shared.open(url)
            lastPostPassActionMessage = "Opened internal packet report"
        case .digitalVoice:
            lastPostPassActionMessage = pendingDecoderDetail(for: item.preset)
        case .fmVoice:
            NSWorkspace.shared.open(url)
            lastPostPassActionMessage = "Opened saved voice recording"
        }
    }

    public func refreshDecodedAPTArtifacts() {
        let artifacts = APTImageDecoder.listDecodedArtifacts(limit: 24)
            .sorted { lhs, rhs in
                let lhsScore = noaaArtifactQualityScore(lhs)
                let rhsScore = noaaArtifactQualityScore(rhs)
                if abs(lhsScore - rhsScore) > 0.0001 {
                    return lhsScore > rhsScore
                }
                return lhs.createdAt > rhs.createdAt
            }
        decodedAPTArtifacts = artifacts
        mapState.decodedNOAAArtifacts = artifacts.compactMap { artifact -> DecodedNOAAArtifact? in
            guard let coverage = artifact.coverageSummary, coverage.samplePoints.count >= 2 else {
                return nil
            }
            return DecodedNOAAArtifact(
                id: artifact.imagePath,
                satellite: artifact.satellite,
                imagePath: artifact.imagePath,
                createdAt: artifact.createdAt,
                samplePoints: coverage.samplePoints.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                },
                estimatedSwathWidthKilometers: estimatedNOAASwathWidthKilometers(for: artifact),
                centerCoordinate: coverage.samplePoints[coverage.samplePoints.count / 2].coordinate,
                qualityScore: noaaArtifactQualityScore(artifact),
                qualityTier: noaaArtifactQualityTier(artifact)
            )
        }
        if latestAPTRecording == nil, let artifact = artifacts.first {
            latestAPTRecording = PostPassActionItem(
                satellite: artifact.satellite,
                preset: .noaaAPT,
                recordingKind: .audio,
                filePath: artifact.imagePath,
                actionLabel: "Open decoded APT image",
                detailText: String(
                    format: "Decoded %d lines • sync %.2f • jitter %.1f • balance %+.2f • telem %.2f • sep %.2f • cal %.2f",
                    artifact.lineCount,
                    artifact.syncQuality,
                    artifact.lineJitter,
                    artifact.channelBalance,
                    artifact.telemetryContrast,
                    artifact.channelSeparation,
                    artifact.calibrationSpread
                ),
                sourceFilePath: artifact.sourcePath,
                createdAt: artifact.createdAt
            )
        }
    }

    public func refreshDecodedPacketArtifacts() {
        let artifacts = PacketAudioDecoder.listDecodedArtifacts(limit: 24)
        decodedPacketArtifacts = artifacts
        if latestPacketRecording == nil, let artifact = artifacts.first {
            latestPacketRecording = PostPassActionItem(
                satellite: artifact.satellite,
                preset: .packet,
                recordingKind: .audio,
                filePath: artifact.reportPath,
                actionLabel: "Open packet report",
                detailText: String(
                    format: "Packet %.0f%% • flags %d • frames %d • %.1f/%.1f kHz",
                    artifact.confidence * 100,
                    artifact.hdlcFlagCount,
                    artifact.decodedFrames.count,
                    artifact.markFrequency / 1000,
                    artifact.spaceFrequency / 1000
                ),
                sourceFilePath: artifact.sourcePath,
                createdAt: artifact.createdAt
            )
        }
    }

    public func refreshRecordingLibrary(selectWorkspace: Bool = false, message: String? = nil) {
        refreshDecodedAPTArtifacts()
        refreshDecodedPacketArtifacts()
        recordingLibraryRefreshToken &+= 1
        if selectWorkspace {
            workspace = .recordings
        }
        if let message {
            lastPostPassActionMessage = message
        }
    }

    public func inferredSatelliteName(for metadata: RecordingMetadata) -> String {
        if let satelliteIndex = metadata.tags.firstIndex(of: "satellite"),
           metadata.tags.indices.contains(satelliteIndex + 1) {
            return metadata.tags[satelliteIndex + 1]
        }

        if let match = trackedSatelliteNames.first(where: { metadata.notes.localizedCaseInsensitiveContains($0) }) {
            return match
        }

        let basename = (metadata.filePath as NSString).lastPathComponent
        if let match = trackedSatelliteNames.first(where: { basename.localizedCaseInsensitiveContains($0) }) {
            return match
        }

        return "Unknown Satellite"
    }

    public func inferredReceivePreset(for metadata: RecordingMetadata) -> SatelliteReceivePreset? {
        if metadata.tags.contains(SatelliteReceivePreset.noaaAPT.rawValue) { return .noaaAPT }
        if metadata.tags.contains(SatelliteReceivePreset.packet.rawValue) { return .packet }
        if metadata.tags.contains(SatelliteReceivePreset.digitalVoice.rawValue) { return .digitalVoice }
        if metadata.tags.contains(SatelliteReceivePreset.fmVoice.rawValue) { return .fmVoice }

        let notes = metadata.notes
        if notes.localizedCaseInsensitiveContains(SatelliteReceivePreset.noaaAPT.rawValue) { return .noaaAPT }
        if notes.localizedCaseInsensitiveContains(SatelliteReceivePreset.packet.rawValue) { return .packet }
        if notes.localizedCaseInsensitiveContains(SatelliteReceivePreset.digitalVoice.rawValue) { return .digitalVoice }
        if notes.localizedCaseInsensitiveContains(SatelliteReceivePreset.fmVoice.rawValue) { return .fmVoice }

        return nil
    }

    public func canDecodeAgain(_ metadata: RecordingMetadata) -> Bool {
        switch inferredReceivePreset(for: metadata) {
        case .noaaAPT?, .packet?:
            return URL(fileURLWithPath: metadata.filePath).pathExtension.lowercased() == "wav"
        default:
            return false
        }
    }

    public func decodeRecordingFromLibrary(_ metadata: RecordingMetadata) {
        let preset = inferredReceivePreset(for: metadata)
        let satellite = inferredSatelliteName(for: metadata)
        let sourceURL = URL(fileURLWithPath: metadata.filePath)

        switch preset {
        case .noaaAPT:
            do {
                let decodeContext = noaaDecodeContext(for: satellite)
                let result = try APTImageDecoder.decodeRecording(at: sourceURL, satellite: satellite, context: decodeContext)
                latestAPTRecording = PostPassActionItem(
                    satellite: satellite,
                    preset: .noaaAPT,
                    recordingKind: .audio,
                    filePath: result.imageURL.path,
                    actionLabel: "Open decoded APT image",
                    detailText: String(
                        format: "Decoded %d lines • sync %.2f • jitter %.1f • balance %+.2f • telem %.2f • sep %.2f • cal %.2f",
                        result.lineCount,
                        result.syncQuality,
                        result.lineJitter,
                        result.channelBalance,
                        result.telemetryContrast,
                        result.channelSeparation,
                        result.calibrationSpread
                    ),
                    sourceFilePath: metadata.filePath,
                    createdAt: result.createdAt
                )
                refreshRecordingLibrary(selectWorkspace: true, message: "Re-decoded NOAA APT recording from Library")
            } catch {
                lastPostPassActionMessage = "APT decode failed: \(error.localizedDescription)"
            }

        case .packet:
            do {
                let result = try PacketAudioDecoder.decodeRecording(at: sourceURL, satellite: satellite)
                latestPacketRecording = PostPassActionItem(
                    satellite: satellite,
                    preset: .packet,
                    recordingKind: .audio,
                    filePath: result.reportURL.path,
                    actionLabel: "Open packet report",
                    detailText: String(
                        format: "Packet %.0f%% • flags %d • frames %d • %.1f/%.1f kHz",
                        result.confidence * 100,
                        result.hdlcFlagCount,
                        result.decodedFrames.count,
                        result.markFrequency / 1000,
                        result.spaceFrequency / 1000
                    ),
                    sourceFilePath: metadata.filePath,
                    createdAt: result.createdAt
                )
                refreshRecordingLibrary(selectWorkspace: true, message: "Re-decoded packet recording from Library")
            } catch {
                lastPostPassActionMessage = "Packet decode failed: \(error.localizedDescription)"
            }

        case .digitalVoice:
            lastPostPassActionMessage = "Digital voice re-decode is not implemented yet"
        case .fmVoice:
            lastPostPassActionMessage = "FM voice recordings are for listening, not internal decode"
        case nil:
            lastPostPassActionMessage = "Could not infer decoder from recording metadata"
        }
    }

    public func openAPTChannelImage(_ artifact: APTDecodedArtifact, channel: Int) {
        switch channel {
        case 1:
            NSWorkspace.shared.open(artifact.channelAImageURL)
            lastPostPassActionMessage = "Opened NOAA APT channel A image"
        case 2:
            NSWorkspace.shared.open(artifact.channelBImageURL)
            lastPostPassActionMessage = "Opened NOAA APT channel B image"
        default:
            NSWorkspace.shared.open(artifact.imageURL)
            lastPostPassActionMessage = "Opened decoded NOAA APT image"
        }
    }

    public func selectDecodedNOAAArtifact(id: String) {
        mapState.selectedDecodedNOAAArtifactID = id
        if let artifact = decodedAPTArtifacts.first(where: { $0.imagePath == id }) {
            latestAPTRecording = PostPassActionItem(
                satellite: artifact.satellite,
                preset: .noaaAPT,
                recordingKind: .audio,
                filePath: artifact.imagePath,
                actionLabel: "Open decoded APT image",
                detailText: String(
                    format: "Decoded %d lines • sync %.2f • jitter %.1f • balance %+.2f • telem %.2f • sep %.2f • cal %.2f",
                    artifact.lineCount,
                    artifact.syncQuality,
                    artifact.lineJitter,
                    artifact.channelBalance,
                    artifact.telemetryContrast,
                    artifact.channelSeparation,
                    artifact.calibrationSpread
                ),
                sourceFilePath: artifact.sourcePath,
                createdAt: artifact.createdAt
            )
            workspace = .recordings
            lastPostPassActionMessage = "Selected decoded NOAA artifact from map"
        }
    }

    public func focusDecodedNOAAArtifact(id: String? = nil) {
        if let id {
            mapState.selectedDecodedNOAAArtifactID = id
        }
        mapState.decodedNOAAFocusRequestToken += 1
        lastPostPassActionMessage = "Focused decoded NOAA swath on map"
    }

    public func setMinimumNOAAQualityTier(_ tier: NOAAArtifactQualityTier) {
        mapState.minimumNOAAQualityTier = tier
        savePreferences()
    }

    public func setMapStyle(_ style: MapState.MapStyle) {
        mapState.mapStyle = style
        savePreferences()
    }

    public func setShowDecodedNOAA(_ enabled: Bool) {
        mapState.showDecodedNOAA = enabled
        savePreferences()
    }

    public func setShowGroundTracks(_ enabled: Bool) {
        mapState.showGroundTracks = enabled
        savePreferences()
    }

    public func setShowOrbits(_ enabled: Bool) {
        mapState.showOrbits = enabled
        savePreferences()
    }

    public func noaaArtifactQualityScore(_ artifact: APTDecodedArtifact) -> Double {
        let sync = clamp01(Double(artifact.syncQuality))
        let telemetry = clamp01(Double(artifact.telemetryContrast) / 0.25)
        let separation = clamp01(Double(artifact.channelSeparation) / 0.18)
        let calibration = clamp01(Double(artifact.calibrationSpread) / 0.30)
        let balance = clamp01(1.0 - min(abs(Double(artifact.channelBalance)) / 0.5, 1.0))
        let jitter = clamp01(1.0 - min(Double(artifact.lineJitter) / 40.0, 1.0))

        return (
            sync * 0.28 +
            telemetry * 0.18 +
            separation * 0.18 +
            calibration * 0.16 +
            balance * 0.10 +
            jitter * 0.10
        )
    }

    public func noaaArtifactQualityTier(_ artifact: APTDecodedArtifact) -> NOAAArtifactQualityTier {
        let score = noaaArtifactQualityScore(artifact)
        if score >= 0.72 { return .strong }
        if score >= 0.45 { return .usable }
        return .weak
    }

    private func noaaDecodeContext(for satelliteName: String) -> APTDecodeContext? {
        guard let tle = mapIntegrationManager.tleManager.getTLE(name: satelliteName) else {
            return nil
        }

        let propagator = SGP4Propagator(tle: tle)
        let predictor = PassPredictor(
            propagator: propagator,
            latitude: mapState.observerLatitude,
            longitude: mapState.observerLongitude
        )
        let pass = predictor.findNextPass(from: Date().addingTimeInterval(-20 * 60), maxDays: 1)
        let lineCoverage = sampledNOAACoverage(
            propagator: propagator,
            from: pass?.aos ?? Date().addingTimeInterval(-8 * 60),
            to: pass?.los ?? Date(),
            lineCountHint: 2400
        )

        return APTDecodeContext(
            satellite: satelliteName,
            observerLatitude: mapState.observerLatitude,
            observerLongitude: mapState.observerLongitude,
            passStart: pass?.aos,
            passEnd: pass?.los,
            lineCoverage: lineCoverage
        )
    }

    private var trackedSatelliteNames: [String] {
        mapState.trackedSatellites.map(\.name)
    }

    private func clamp01(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    private func sampledNOAACoverage(
        propagator: SGP4Propagator,
        from start: Date,
        to end: Date,
        lineCountHint: Int
    ) -> [APTLineCoverage] {
        let duration = max(end.timeIntervalSince(start), 1)
        let step = max(duration / Double(max(lineCountHint, 1)), 0.2)
        var coverage: [APTLineCoverage] = []
        var current = start

        while current <= end {
            let pos = propagator.getPosition(at: current)
            coverage.append(
                APTLineCoverage(
                    timestamp: current,
                    latitude: pos.latitude,
                    longitude: pos.longitude
                )
            )
            current = current.addingTimeInterval(step)
        }

        if coverage.isEmpty {
            let pos = propagator.getPosition(at: start)
            coverage.append(
                APTLineCoverage(
                    timestamp: start,
                    latitude: pos.latitude,
                    longitude: pos.longitude
                )
            )
        }

        return coverage
    }

    private func estimatedNOAASwathWidthKilometers(for artifact: APTDecodedArtifact) -> Double {
        let baseWidth = 2800.0
        let separationFactor = max(Double(artifact.channelSeparation), 0.2)
        let telemetryFactor = max(Double(artifact.telemetryContrast), 0.2)
        let qualityScale = min(max((separationFactor + telemetryFactor) * 0.5, 0.75), 1.15)
        return baseWidth * qualityScale
    }

    private func formatFrequency(_ freq: Double) -> String {
        if freq >= 1_000_000_000 {
            return String(format: "%.3f GHz", freq / 1_000_000_000)
        } else if freq >= 1_000_000 {
            return String(format: "%.3f MHz", freq / 1_000_000)
        } else if freq >= 1_000 {
            return String(format: "%.3f kHz", freq / 1_000)
        } else {
            return "\(Int(freq)) Hz"
        }
    }

    private func formatSignedFrequency(_ freq: Double) -> String {
        if abs(freq) >= 1_000 {
            return String(format: "%+.1f k", freq / 1_000)
        }
        return String(format: "%+.0f", freq)
    }

    private func satellitePreset(for name: String) -> SatellitePreset {
        let upper = name.uppercased()
        if upper.contains("NOAA 15") {
            return SatellitePreset(frequency: 137_620_000, mode: .WFM, bandwidth: 40_000, receivePreset: .noaaAPT)
        }
        if upper.contains("NOAA 19") {
            return SatellitePreset(frequency: 137_100_000, mode: .WFM, bandwidth: 40_000, receivePreset: .noaaAPT)
        }
        if upper.contains("ISS") {
            return SatellitePreset(frequency: 145_800_000, mode: .NFM, bandwidth: 20_000, receivePreset: .fmVoice)
        }
        if upper.contains("AO-91") {
            return SatellitePreset(frequency: 435_250_000, mode: .NFM, bandwidth: 20_000, receivePreset: .fmVoice)
        }
        if upper.contains("AO-92") {
            return SatellitePreset(frequency: 145_880_000, mode: .NFM, bandwidth: 20_000, receivePreset: .fmVoice)
        }
        if upper.contains("SO-50") {
            return SatellitePreset(frequency: 436_795_000, mode: .NFM, bandwidth: 20_000, receivePreset: .fmVoice)
        }
        return SatellitePreset(frequency: 137_100_000, mode: .WFM, bandwidth: 40_000, receivePreset: .packet)
    }

    private func defaultSatelliteProfile(for name: String) -> SatelliteProfile {
        let preset = satellitePreset(for: name)
        return SatelliteProfile(
            frequency: preset.frequency,
            mode: preset.mode,
            bandwidth: preset.bandwidth,
            receivePreset: preset.receivePreset
        )
    }

    public func toggleRecording() {
        if isRecording {
            do {
                _ = try recordingManagerWrapper?.stopRecording()
                isRecording = false
                autoSatelliteRecordingActive = false
                statusMessage = "Recording stopped"
                refreshRecordingLibrary()
            } catch {
                statusMessage = "Recording stop error: \(error.localizedDescription)"
            }
        } else {
            if recordingManagerWrapper == nil {
                recordingManagerWrapper = RecordingManagerWrapper()
            }
            do {
                _ = try recordingManagerWrapper?.startIQRecording(
                    frequency: frequency,
                    sampleRate: sampleRate,
                    mode: currentMode.rawValue,
                    format: .rawIQ
                )
                isRecording = true
                statusMessage = "Recording started"
            } catch {
                statusMessage = "Recording start error: \(error.localizedDescription)"
            }
        }
    }

    public func addCurrentBookmark() {
        let name = String(format: "%.3f MHz %@", frequency / 1_000_000, currentMode.rawValue)
        let bookmark = Bookmark(name: name, frequency: frequency, mode: currentMode, tags: ["Quick"])
        bookmarkManager.addBookmark(bookmark)
        statusMessage = "Bookmarked \(name)"
    }

    public func setupRDSCallbacks() {
        dspPipeline?.setRDSCallbacks { [weak self] in
            guard let self = self, let pipeline = self.dspPipeline else { return }
            let rds = pipeline.rdsDecoder
            DispatchQueue.main.async {
                if let ps = rds?.programService, ps != "Unknown" {
                    self.rdsData.stationName = ps
                }
                self.rdsData.radioText = rds?.radioText ?? ""
                self.rdsData.piCode = rds?.programIdentification ?? 0
                self.rdsData.programType = RDSState.decodePTY(rds?.programType ?? 0)
                self.rdsData.trafficProgram = rds?.trafficProgram ?? false
                self.rdsData.trafficAnnouncement = rds?.trafficAnnouncement ?? false
                self.rdsData.isMusic = rds?.isMusic ?? false
                self.rdsData.alternativeFrequencies = rds?.alternativeFrequencies ?? []
                self.rdsData.hasData = true
            }
        }
    }

    private func startSatelliteUpdates() {
        guard satelliteUpdateTimer == nil else { return }
        mapIntegrationManager.updateSatellitePositions()
        satelliteUpdateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.mapIntegrationManager.updateSatellitePositions()
            self?.updateSatelliteDopplerStatus()
            self?.checkArmedSatelliteRecording()
        }
    }

    private func refreshTrackedSatellites() {
        tleRefreshTask?.cancel()
        tleRefreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.mapIntegrationManager.refreshTrackedSatellitesFromCelesTrak()
                await MainActor.run {
                    self.statusMessage = "Satellite elements refreshed"
                    self.mapIntegrationManager.updateSatellitePositions()
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "TLE refresh failed: \(error.localizedDescription)"
                }
            }
        }
    }

    public func persistSessionPreferences() {
        savePreferences()
    }

    private func ensureWorkspaceInfrastructure(for workspace: Workspace) {
        guard workspace == .aircraft || workspace == .satellites || workspace == .earth else { return }
        guard !mapSubsystemsInitialized else { return }

        mapSubsystemsInitialized = true
        startupQueue.async { [weak self] in
            guard let self else { return }
            self.mapIntegrationManager.loadDefaultSatellites()
            self.refreshTrackedSatellites()

            DispatchQueue.main.async {
                self.startSatelliteUpdates()
                if self.mapState.weatherOverlayEnabled {
                    self.mapIntegrationManager.weatherRadarManager.connectToDump978(
                        host: self.dump978Host,
                        port: self.dump978Port
                    )
                    self.mapIntegrationManager.weatherRadarManager.setEnabled(true)
                }
            }
        }
    }

    private func loadPreferences() {
        guard let data = UserDefaults.standard.data(forKey: Self.preferencesKey),
              let preferences = try? JSONDecoder().decode(AppSessionPreferences.self, from: data) else {
            return
        }

        workspace = Workspace(rawValue: preferences.workspace) ?? .radio
        frequency = preferences.frequency
        sampleRate = preferences.sampleRate
        currentMode = DemodulatorType(rawValue: preferences.currentMode) ?? .NFM
        bandwidth = preferences.bandwidth
        agcEnabled = preferences.agcEnabled
        tunerGain = preferences.tunerGain
        squelchEnabled = preferences.squelchEnabled
        squelchThreshold = preferences.squelchThreshold
        dump978Enabled = preferences.dump978Enabled
        dump978Host = preferences.dump978Host
        dump978Port = preferences.dump978Port
        mapState.mapStyle = MapState.MapStyle(rawValue: preferences.mapStyle) ?? .hybrid
        mapState.weatherOverlayEnabled = preferences.weatherOverlayEnabled
        mapState.showGroundTracks = preferences.showGroundTracks
        mapState.showOrbits = preferences.showOrbits
        mapState.showDecodedNOAA = preferences.showDecodedNOAA
        mapState.restoreObserverPreference(
            lat: preferences.observerLatitude,
            lon: preferences.observerLongitude,
            useCurrentLocation: preferences.useCurrentLocation
        )
        liveDopplerRetuneEnabled = preferences.liveDopplerRetuneEnabled
        mapState.minimumNOAAQualityTier = NOAAArtifactQualityTier(rawValue: preferences.minimumNOAAQualityTier) ?? .weak
        satelliteProfiles = preferences.satelliteProfiles
        ensureWorkspaceInfrastructure(for: workspace)
        savePreferences()
    }

    private func savePreferences() {
        let preferences = AppSessionPreferences(
            workspace: workspace.rawValue,
            frequency: frequency,
            sampleRate: sampleRate,
            currentMode: currentMode.rawValue,
            bandwidth: bandwidth,
            agcEnabled: agcEnabled,
            tunerGain: tunerGain,
            squelchEnabled: squelchEnabled,
            squelchThreshold: squelchThreshold,
            dump978Enabled: dump978Enabled,
            dump978Host: dump978Host,
            dump978Port: dump978Port,
            mapStyle: mapState.mapStyle.rawValue,
            weatherOverlayEnabled: mapState.weatherOverlayEnabled,
            showGroundTracks: mapState.showGroundTracks,
            showOrbits: mapState.showOrbits,
            showDecodedNOAA: mapState.showDecodedNOAA,
            observerLatitude: mapState.observerLatitude,
            observerLongitude: mapState.observerLongitude,
            useCurrentLocation: mapState.isUsingCurrentLocation,
            liveDopplerRetuneEnabled: liveDopplerRetuneEnabled,
            minimumNOAAQualityTier: mapState.minimumNOAAQualityTier.rawValue,
            satelliteProfiles: satelliteProfiles
        )

        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: Self.preferencesKey)
        }
    }

    private func reconfigureDevice(_ update: (inout RTLSDRConfig) -> Void) throws {
        guard isRunning else { return }
        var config = RTLSDRConfig()
        config.sampleRate = sampleRate
        config.centerFrequency = frequency
        config.gainMode = agcEnabled
        config.tunerGain = tunerGain
        update(&config)
        try rtlDevice?.configure(config)
    }
}

public struct RDSState {
    public var stationName: String = ""
    public var radioText: String = ""
    public var piCode: UInt16 = 0
    public var programType: String = ""
    public var trafficProgram: Bool = false
    public var trafficAnnouncement: Bool = false
    public var isMusic: Bool = false
    public var alternativeFrequencies: [Float] = []
    public var hasData: Bool = false

    public init() {}

    public static func decodePTY(_ code: UInt8) -> String {
        let ptyNames = [
            "None", "News", "Current Affairs", "Information", "Sport", "Education",
            "Drama", "Culture", "Science", "Varied", "Pop Music", "Rock Music",
            "Easy Listening", "Light Classical", "Serious Classical", "Other Music",
            "Weather", "Finance", "Children's", "Social Affairs", "Religion",
            "Phone In", "Travel", "Leisure", "Jazz Music", "Country Music",
            "National Music", "Oldies Music", "Folk Music", "Documentary", "Alarm Test",
            "Alarm"
        ]
        let idx = Int(code)
        return idx < ptyNames.count ? ptyNames[idx] : "Unknown"
    }
}

// MARK: - Demodulator Shortcuts

public extension DemodulatorType {
    var shortcut: KeyEquivalent {
        switch self {
        case .IQ: return KeyEquivalent("q")
        case .AM: return KeyEquivalent("a")
        case .NFM: return KeyEquivalent("f")
        case .WFM: return KeyEquivalent("w")
        case .USB: return KeyEquivalent("u")
        case .LSB: return KeyEquivalent("l")
        case .CW: return KeyEquivalent("c")
        case .DMR: return KeyEquivalent("d")
        case .P25: return KeyEquivalent("p")
        case .DSTAR: return KeyEquivalent("i")
        }
    }
}
