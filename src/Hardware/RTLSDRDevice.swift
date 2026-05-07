//
// RTLSDRDevice.swift
// NeuralSDR2
//
// Swift wrapper for librtlsdr C library
// Provides device enumeration, configuration, and sample streaming
// Phase 7: Device state, reconnect, error reporting, tuner enumeration
//

import Foundation
import CLibRTLSDR
import Accelerate
import os.log

private let logger = Logger(subsystem: "com.neuralsdr2.app", category: "RTLSDRDevice")

/// Information about an RTL-SDR device discovered on the system.
///
/// Use ``RTLSDRDevice/enumerateDevices()`` to get a list of available devices.
public struct RTLSDRDeviceInfo: Sendable {
    public let index: UInt32
    public let name: String
    public let serial: String
    public let tunerName: String

    public init(index: UInt32, name: String, serial: String, tunerName: String) {
        self.index = index
        self.name = name
        self.serial = serial
        self.tunerName = tunerName
    }
}

/// Configuration parameters for an RTL-SDR device.
///
/// Set sample rate, center frequency, gain mode, and other hardware parameters,
/// then pass to ``RTLSDRDevice/configure(_:)`` to apply.
///
/// ```swift
/// var config = RTLSDRConfig()
/// config.sampleRate = 2_048_000
/// config.centerFrequency = 1090_000_000
/// try device.configure(config)
/// ```
public struct RTLSDRConfig: Sendable {
    public var sampleRate: Double = 2_048_000
    public var centerFrequency: Double = 1090_000_000
    public var gainMode: Bool = false
    public var tunerGain: Double = 0
    public var frequencyCorrection: Double = 0
    public var biasTeeEnabled: Bool = false
    public var directSamplingMode: UInt32 = 0
    public init() {}

    // Common sample rates
    public static let sampleRates: [Double] = [
        1_024_000,
        1_920_000,
        2_048_000,
        2_400_000,
        2_560_000,
        3_200_000
    ]

    // Common frequency bands
    public static let frequencyBands: [(name: String, start: Double, end: Double)] = [
        ("HF", 0, 30_000_000),
        ("VHF", 30_000_000, 300_000_000),
        ("UHF", 300_000_000, 3_000_000_000),
        ("FM Broadcast", 88_000_000, 108_000_000),
        ("Air Band", 108_000_000, 137_000_000),
        ("2m Ham", 144_000_000, 148_000_000),
        ("70cm Ham", 420_000_000, 450_000_000),
        ("ADS-B", 1_090_000_000, 1_090_000_000)
    ]
}

/// A Swift wrapper for RTL-SDR hardware devices.
///
/// Provides device enumeration, configuration, and IQ sample streaming.
/// Uses the `CLibRTLSDR` C library for hardware access.
///
/// ```swift
/// let device = RTLSDRDevice()
/// try device.open(index: 0)
/// var config = RTLSDRConfig()
/// config.centerFrequency = 1090_000_000
/// try device.configure(config)
/// try device.startStreaming { iqSamples in
///     pipeline.process(samples: iqSamples)
/// }
/// ```
public class RTLSDRDevice: NSObject {

    // MARK: - Device State

    public enum DeviceState: String, Sendable {
        case disconnected
        case connected
        case configuring
        case streaming
        case error
        case reconnecting
    }

    // MARK: - Properties

private var device: OpaquePointer?
private var _isStreaming = false
private var config = RTLSDRConfig()
private var sampleCallback: (([ComplexFloat]) -> Void)?
private var streamingQueue: DispatchQueue?
private var streamingSemaphore: DispatchSemaphore?

// Pre-allocated buffers for batch IQ conversion (grow-only)
private var iBuffer: [Float] = []
private var qBuffer: [Float] = []
private var complexSamples: [ComplexFloat] = []

    public private(set) var deviceState: DeviceState = .disconnected
    public var onStateChanged: ((DeviceState) -> Void)?
    public var onError: ((String) -> Void)?

    public var autoReconnect: Bool = true
    private var reconnectAttempts: Int = 0
    private let maxReconnectAttempts: Int = 5
    private var lastConfig: RTLSDRConfig?
    private var lastStreamingCallback: (([ComplexFloat]) -> Void)?
    private var reconnectQueue = DispatchQueue(label: "com.neuralsdr2.rtlsdr.reconnect", qos: .utility)

    // Device info
    public private(set) var deviceInfo: RTLSDRDeviceInfo?
    public private(set) var isOpen = false

    // Statistics
    public private(set) var samplesReceived: UInt64 = 0
    public private(set) var bytesPerSample: Int32 = 0
    public private(set) var sampleLoss: Double = 0.0

    /// Thread-safe streaming state access
    public var isStreaming: Bool {
        return _isStreaming
    }

    // MARK: - State Transitions

    private func updateState(_ newState: DeviceState) {
        deviceState = newState
        onStateChanged?(newState)
    }

    private func reportError(_ message: String) {
        logger.error("RTLSDRDevice error: \(message)")
        updateState(.error)
        onError?(message)
    }

    // MARK: - Error Types

    public enum DeviceError: Error, LocalizedError {
        case noDevicesFound
        case deviceOpenFailed
        case deviceNotOpen
        case configurationFailed(String)
        case streamingError
        case reconnectFailed

        public var errorDescription: String? {
            switch self {
            case .noDevicesFound:
                return "No RTL-SDR devices found"
            case .deviceOpenFailed:
                return "Failed to open device"
            case .deviceNotOpen:
                return "Device is not open"
            case .configurationFailed(let message):
                return "Configuration failed: \(message)"
            case .streamingError:
                return "Streaming error occurred"
            case .reconnectFailed:
                return "Reconnect failed after maximum attempts"
            }
        }
    }

    // MARK: - Device Enumeration

    /// Enumerate available RTL-SDR devices with tuner type detection
    public static func enumerateDevices() -> [RTLSDRDeviceInfo] {
        let deviceCount = rtlsdr_get_device_count()
        var devices: [RTLSDRDeviceInfo] = []

        for index in 0..<deviceCount {
            let name = String(cString: rtlsdr_get_device_name(index))
            var manufact = [CChar](repeating: 0, count: 256)
            var product = [CChar](repeating: 0, count: 256)
            var serialBuf = [CChar](repeating: 0, count: 256)
            rtlsdr_get_device_usb_strings(index, &manufact, &product, &serialBuf)
            let serial = String(cString: serialBuf)

            let tunerName = getTunerNameForDevice(at: index)

            devices.append(RTLSDRDeviceInfo(
                index: index,
                name: name,
                serial: serial,
                tunerName: tunerName
            ))
        }

        return devices
    }

    /// Briefly open a device to read its tuner type, then close it
    private static func getTunerNameForDevice(at index: UInt32) -> String {
        var dev: OpaquePointer?
        let openResult = rtlsdr_open(&dev, index)
        guard openResult == 0, dev != nil else {
            return "Unknown"
        }
        let tunerType = rtlsdr_get_tuner_type(dev)
        rtlsdr_close(dev)
        return tunerNameForType(Int32(tunerType.rawValue))
    }

    /// Check if any devices are available
    public static func hasDevices() -> Bool {
        return rtlsdr_get_device_count() > 0
    }

    // MARK: - Initialization

    /// Open device by index
    public func open(index: UInt32 = 0) throws {
        guard RTLSDRDevice.hasDevices() else {
            throw DeviceError.noDevicesFound
        }

        let openResult = rtlsdr_open(&device, index)
        guard openResult == 0, device != nil else {
            reportError("Failed to open device at index \(index)")
            throw DeviceError.deviceOpenFailed
        }

        isOpen = true
        updateState(.connected)

        // Get device info
        let namePtr = rtlsdr_get_device_name(index)
        let tunerType = rtlsdr_get_tuner_type(device)
        let tunerName = RTLSDRDevice.tunerNameForType(Int32(tunerType.rawValue))

        var serialBuf = [CChar](repeating: 0, count: 256)
        rtlsdr_get_usb_strings(device, nil, nil, &serialBuf)
        let serial = String(cString: serialBuf)

        deviceInfo = RTLSDRDeviceInfo(
            index: index,
            name: namePtr != nil ? String(cString: namePtr!) : "Unknown",
            serial: serial,
            tunerName: tunerName
        )

        // Reset statistics
        samplesReceived = 0
        sampleLoss = 0.0
        reconnectAttempts = 0

        logger.info("Device opened: \(self.deviceInfo?.name ?? "Unknown"), tuner: \(tunerName)")
    }

    /// Close the device
    public func close() {
        stopStreaming()

        if device != nil {
            rtlsdr_close(device)
            device = nil
            isOpen = false
            updateState(.disconnected)
        }
    }

    deinit {
        close()
    }

    // MARK: - Configuration

    /// Apply configuration to the device
    public func configure(_ config: RTLSDRConfig) throws {
        guard isOpen, device != nil else {
            throw DeviceError.deviceNotOpen
        }

        updateState(.configuring)

        // Set sample rate
        let sampleRateResult = rtlsdr_set_sample_rate(device, UInt32(config.sampleRate))
        guard sampleRateResult == 0 else {
            reportError("Failed to set sample rate")
            throw DeviceError.configurationFailed("Failed to set sample rate")
        }

        // Set center frequency
        let freqResult = rtlsdr_set_center_freq(device, UInt32(config.centerFrequency))
        guard freqResult == 0 else {
            reportError("Failed to set center frequency")
            throw DeviceError.configurationFailed("Failed to set center frequency")
        }

        // Set gain mode
        let gainModeResult = rtlsdr_set_tuner_gain_mode(device, config.gainMode ? 0 : 1)
        guard gainModeResult == 0 else {
            reportError("Failed to set gain mode")
            throw DeviceError.configurationFailed("Failed to set gain mode")
        }

        // Set tuner gain if not auto
        if !config.gainMode && config.tunerGain > 0 {
            let gainResult = rtlsdr_set_tuner_gain(device, Int32(config.tunerGain))
            guard gainResult == 0 else {
                reportError("Failed to set tuner gain")
                throw DeviceError.configurationFailed("Failed to set tuner gain")
            }
        }

        // Set frequency correction (PPM)
        if config.frequencyCorrection != 0 {
            let ppmResult = rtlsdr_set_freq_correction(device, Int32(config.frequencyCorrection))
            if ppmResult != 0 {
                logger.warning("Could not set frequency correction")
            }
        }

        // Set bias tee
        if config.biasTeeEnabled {
            let biasResult = rtlsdr_set_bias_tee(device, 1)
            if biasResult != 0 {
                logger.warning("Bias tee not supported or failed")
            }
        }

        // Set direct sampling
        if config.directSamplingMode > 0 {
            let directResult = rtlsdr_set_direct_sampling(device, Int32(config.directSamplingMode))
            if directResult != 0 {
                logger.warning("Direct sampling mode not supported")
            }
        }

        self.config = config
        lastConfig = config

        if _isStreaming {
            updateState(.streaming)
        } else {
            updateState(.connected)
        }
    }

    // MARK: - Streaming

    /// Start IQ sample streaming (runs rtlsdr_read_async on a background thread)
    public func startStreaming(callback: @escaping ([ComplexFloat]) -> Void) throws {
        guard isOpen, device != nil else {
            throw DeviceError.deviceNotOpen
        }

        guard !_isStreaming else {
            return
        }

        sampleCallback = callback
        lastStreamingCallback = callback
        _isStreaming = true
        updateState(.streaming)

        let resetResult = rtlsdr_reset_buffer(device)
        guard resetResult == 0 else {
            _isStreaming = false
            updateState(.connected)
            reportError("Failed to reset RTL-SDR sample buffer")
            throw DeviceError.streamingError
        }

        // Semaphore to signal when the async read thread has fully exited
        streamingSemaphore = DispatchSemaphore(value: 0)
        streamingQueue = DispatchQueue(label: "com.neuralsdr2.rtlsdr.streaming", qos: .userInteractive)

        // Capture a retained reference for the C callback context
        // This prevents use-after-free if the device is deallocated while streaming
        let selfContext = Unmanaged.passRetained(self).toOpaque()

        streamingQueue?.async { [weak self] in
            guard let self = self, let device = self.device else {
                // Device was released before streaming started
                Unmanaged<RTLSDRDevice>.fromOpaque(selfContext).release()
                self?.streamingSemaphore?.signal()
                return
            }

            let result = rtlsdr_read_async(device, { buffer, bytes, context in
                guard let context = context else { return }
                let strongSelf = Unmanaged<RTLSDRDevice>.fromOpaque(context).takeUnretainedValue()
                strongSelf.handleSamples(buffer: buffer, bytes: bytes)
            }, selfContext, 12, 16 * 32 * 512)

            if result != 0 && self._isStreaming {
                logger.error("rtlsdr_read_async returned error \(result)")
                self.handleStreamingError(result)
            }

            // Release the retained reference we created before dispatching
            Unmanaged<RTLSDRDevice>.fromOpaque(selfContext).release()

            self.streamingSemaphore?.signal()
        }
    }

/// Handle streaming error — trigger reconnect if enabled
    private func handleStreamingError(_ errorCode: Int32) {
        // librtlsdr error codes: -5 = no device, -7 = cancelled, -8 = busy
        let errorMessage: String
        if errorCode == -5 {
            errorMessage = "Device disconnected (USB)"
        } else if errorCode == -7 {
            errorMessage = "Streaming cancelled"
        } else if errorCode == -8 {
            errorMessage = "Device busy"
        } else {
            errorMessage = "Streaming error (code: \(errorCode))"
        }
        
        reportError(errorMessage)
        
        if autoReconnect && reconnectAttempts < maxReconnectAttempts {
            attemptReconnect()
        } else if autoReconnect {
            logger.error("Max reconnect attempts (\(self.maxReconnectAttempts)) reached")
            reportError("Reconnect failed after \(maxReconnectAttempts) attempts")
        }
    }

    /// Attempt to reconnect to the device with exponential backoff
    private func attemptReconnect() {
        reconnectAttempts += 1
        let delaySeconds = pow(2.0, Double(reconnectAttempts - 1))
        updateState(.reconnecting)
        logger.info("Reconnect attempt \(self.reconnectAttempts)/\(self.maxReconnectAttempts) in \(delaySeconds)s")

        reconnectQueue.async { [weak self] in
            Thread.sleep(forTimeInterval: delaySeconds)

            guard let self = self else { return }

            // Clean up old device state
            if self.device != nil {
                rtlsdr_close(self.device)
                self.device = nil
                self.isOpen = false
            }
            self._isStreaming = false

            // Re-enumerate devices
            guard RTLSDRDevice.hasDevices() else {
                logger.warning("No devices found during reconnect attempt \(self.reconnectAttempts)")
                if self.reconnectAttempts < self.maxReconnectAttempts {
                    self.attemptReconnect()
                } else {
                    DispatchQueue.main.async {
                        self.reportError("Reconnect failed: no devices found")
                    }
                }
                return
            }

            // Try to re-open the device
            do {
                try self.open(index: 0)

                // Re-apply last configuration
                if let lastConfig = self.lastConfig {
                    try self.configure(lastConfig)
                }

                // Re-start streaming with last callback
                if let lastCallback = self.lastStreamingCallback {
                    try self.startStreaming(callback: lastCallback)
                }

                logger.info("Reconnect successful on attempt \(self.reconnectAttempts)")
            } catch {
                logger.warning("Reconnect attempt \(self.reconnectAttempts) failed: \(error.localizedDescription)")
                if self.reconnectAttempts < self.maxReconnectAttempts {
                    self.attemptReconnect()
                } else {
                    DispatchQueue.main.async {
                        self.reportError("Reconnect failed after \(self.maxReconnectAttempts) attempts: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Cancel any in-progress reconnect
    public func cancelReconnect() {
        reconnectAttempts = maxReconnectAttempts
    }

    /// Stop streaming and wait for the background thread to finish
    public func stopStreaming() {
        guard device != nil && _isStreaming else { return }

        _isStreaming = false
        reconnectAttempts = maxReconnectAttempts

        // Cancel the async read — this causes rtlsdr_read_async to return on the background thread
        rtlsdr_cancel_async(device)

        // Wait for the background thread to finish (with timeout to avoid hanging)
        _ = streamingSemaphore?.wait(timeout: .now() + 2.0)
        streamingSemaphore = nil
        streamingQueue = nil

        if isOpen {
            updateState(.connected)
        }
    }

/// Handle incoming samples from C callback
private func handleSamples(buffer: UnsafePointer<UInt8>?, bytes: UInt32) {
guard let buffer = buffer, bytes > 0 else { return }

samplesReceived += UInt64(bytes)

let sampleCount = Int(bytes) / 2

// Grow-only pre-allocation
if iBuffer.count < sampleCount { iBuffer = [Float](repeating: 0, count: sampleCount) }
if qBuffer.count < sampleCount { qBuffer = [Float](repeating: 0, count: sampleCount) }
if complexSamples.count < sampleCount { complexSamples = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: sampleCount) }

// Batch conversion: uint8 → float (tight loop, vectorizer-friendly)
for i in 0..<sampleCount {
    iBuffer[i] = Float(buffer[i * 2])
    qBuffer[i] = Float(buffer[i * 2 + 1])
}

// vDSP: subtract 127.5, then divide by 127.5
// x_out = (x - 127.5) / 127.5 = x / 127.5 - 1.0
// vDSP_vsmsa computes a * x + b, so: a = 1/127.5, b = -1.0
var a: Float = 1.0 / 127.5
var b: Float = -1.0
vDSP_vsmsa(iBuffer, 1, &a, &b, &iBuffer, 1, vDSP_Length(sampleCount))
vDSP_vsmsa(qBuffer, 1, &a, &b, &qBuffer, 1, vDSP_Length(sampleCount))

// Interleave into ComplexFloat
for i in 0..<sampleCount {
    complexSamples[i].real = iBuffer[i]
    complexSamples[i].imag = qBuffer[i]
}

sampleCallback?(complexSamples)
}

// MARK: - Utility Methods

    /// Get current gain values
    public func getGainValues() -> [Int32] {
        guard isOpen, device != nil else { return [] }

        let count = rtlsdr_get_tuner_gains(device, nil)
        guard count > 0 else { return [] }

        var gains = [Int32](repeating: 0, count: Int(count))
        rtlsdr_get_tuner_gains(device, &gains)

        return gains
    }

    /// Get device serial number
    public func getSerialNumber() -> String? {
        guard isOpen, device != nil else { return nil }

        var serial: [CChar] = [CChar](repeating: 0, count: 256)
        let result = rtlsdr_get_usb_strings(device, nil, nil, &serial)

        return result == 0 ? String(cString: serial) : nil
    }

    /// Reset device statistics
    public func resetStatistics() {
        samplesReceived = 0
        sampleLoss = 0.0
    }

    /// Get current sample rate
    public func getSampleRate() -> UInt32 {
        guard isOpen, device != nil else { return 0 }
        return rtlsdr_get_sample_rate(device)
    }

    /// Get current center frequency
    public func getCenterFrequency() -> UInt32 {
        guard isOpen, device != nil else { return 0 }
        return rtlsdr_get_center_freq(device)
    }
}

// MARK: - Helper Extensions

extension RTLSDRDevice {
    /// Convenience method to get device count
    public static var deviceCount: UInt32 {
        return rtlsdr_get_device_count()
    }

    /// Check if a specific tuner type is supported
    public static func isTunerSupported(_ tunerType: Int32) -> Bool {
        return tunerType >= 0
    }

    /// Map RTL-SDR tuner type enum to human-readable name
    /// The C API only exposes rtlsdr_get_tuner_type() which returns an enum integer
    public static func tunerNameForType(_ type: Int32) -> String {
        switch type {
        case 0: return "Unknown"
        case 1: return "E4000"
        case 2: return "FC0012"
        case 3: return "FC0013"
        case 4: return "FC2580"
        case 5: return "R820T"
        case 6: return "R828D"
        default: return "Tuner Type \(type)"
        }
    }
}
