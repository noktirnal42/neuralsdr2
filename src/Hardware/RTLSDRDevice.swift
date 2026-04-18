//
//  RTLSDRDevice.swift
//  NeuralSDR2
//
//  Swift wrapper for librtlsdr C library
//  Provides device enumeration, configuration, and sample streaming
//

import Foundation
import librtlsdr

/// RTL-SDR device information
struct RTLSDRDeviceInfo {
    let index: UInt32
    let name: String
    let serial: String
    let tunerName: String
    
    init(index: UInt32, name: String, serial: String, tunerName: String) {
        self.index = index
        self.name = name
        self.serial = serial
        self.tunerName = tunerName
    }
}

/// RTL-SDR device configuration
struct RTLSDRConfig {
    var sampleRate: Double = 2_048_000  // 2.048 MSps
    var centerFrequency: Double = 1090_000_000  // 1090 MHz (ADS-B)
    var gainMode: Bool = false  // false = manual, true = AGC
    var tunerGain: Double = 0  // Auto-gain when 0
    var frequencyCorrection: Double = 0  // PPM correction
    var biasTeeEnabled: Bool = false
    var directSamplingMode: UInt32 = 0  // 0 = disabled
    
    // Common sample rates
    static let sampleRates: [Double] = [
        1_024_000,
        1_920_000,
        2_048_000,
        2_400_000,
        2_560_000,
        3_200_000
    ]
    
    // Common frequency bands
    static let frequencyBands: [(name: String, start: Double, end: Double)] = [
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

/// RTL-SDR device wrapper class
class RTLSDRDevice: NSObject {
    
    // MARK: - Properties
    
    private var device: OpaquePointer?
    private var isStreaming = false
    private var config = RTLSDRConfig()
    private var sampleCallback: (([ComplexFloat]) -> Void)?
    
    // Device info
    private(set) var deviceInfo: RTLSDRDeviceInfo?
    private(set) var isOpen = false
    
    // Statistics
    private(set) var samplesReceived: UInt64 = 0
    private(set) var bytesPerSample: Int32 = 0
    private(set) var sampleLoss: Double = 0.0
    
    // MARK: - Error Types
    
    enum DeviceError: Error, LocalizedError {
        case noDevicesFound
        case deviceOpenFailed
        case deviceNotOpen
        case configurationFailed(String)
        case streamingError
        
        var errorDescription: String? {
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
            }
        }
    }
    
    // MARK: - Device Enumeration
    
    /// Enumerate available RTL-SDR devices
    static func enumerateDevices() -> [RTLSDRDeviceInfo] {
        let deviceCount = rtl_sdrtlsdr_get_device_count()
        var devices: [RTLSDRDeviceInfo] = []
        
        for index in 0..<deviceCount {
            let name = String(cString: rtl_sdrtlsdr_get_device_name(index))
            let serial = String(cString: rtl_sdrtlsdr_get_device_usb_strings(index))
            
            // Get tuner name after opening device
            devices.append(RTLSDRDeviceInfo(
                index: index,
                name: name,
                serial: serial,
                tunerName: "Unknown"
            ))
        }
        
        return devices
    }
    
    /// Check if any devices are available
    static func hasDevices() -> Bool {
        return rtl_sdrtlsdr_get_device_count() > 0
    }
    
    // MARK: - Initialization
    
    /// Open device by index
    func open(index: UInt32 = 0) throws {
        guard RTLSDRDevice.hasDevices() else {
            throw DeviceError.noDevicesFound
        }
        
        let openResult = rtl_sdrtlsdr_open(&device, index)
        guard openResult == 0, device != nil else {
            throw DeviceError.deviceOpenFailed
        }
        
        isOpen = true
        
        // Get device info
        let namePtr = rtl_sdrtlsdr_get_device_name(index)
        let tunerType = rtl_sdrtlsdr_get_tuner_type(device)
        let tunerName = rtl_sdrtlsr_get_tuner_name(tunerType)
        
        deviceInfo = RTLSDRDeviceInfo(
            index: index,
            name: String(cString: namePtr),
            serial: "",
            tunerName: String(cString: tunerName!)
        )
        
        // Reset statistics
        samplesReceived = 0
        sampleLoss = 0.0
    }
    
    /// Close the device
    func close() {
        if device != nil {
            stopStreaming()
            rtl_sdrtlsdr_close(device)
            device = nil
            isOpen = false
        }
    }
    
    deinit {
        close()
    }
    
    // MARK: - Configuration
    
    /// Apply configuration to the device
    func configure(_ config: RTLSDRConfig) throws {
        guard isOpen, device != nil else {
            throw DeviceError.deviceNotOpen
        }
        
        // Set sample rate
        let sampleRateResult = rtl_sdrtlsdr_set_sample_rate(device, UInt32(config.sampleRate))
        guard sampleRateResult == 0 else {
            throw DeviceError.configurationFailed("Failed to set sample rate")
        }
        
        // Set center frequency
        let freqResult = rtl_sdrtlsdr_set_center_freq(device, UInt32(config.centerFrequency))
        guard freqResult == 0 else {
            throw DeviceError.configurationFailed("Failed to set center frequency")
        }
        
        // Set gain mode
        let gainModeResult = rtl_sdrtlsdr_set_tuner_gain_mode(device, config.gainMode ? 0 : 1)
        guard gainModeResult == 0 else {
            throw DeviceError.configurationFailed("Failed to set gain mode")
        }
        
        // Set tuner gain if not auto
        if !config.gainMode && config.tunerGain > 0 {
            let gainResult = rtl_sdrtlsdr_set_tuner_gain(device, Int32(config.tunerGain))
            guard gainResult == 0 else {
                throw DeviceError.configurationFailed("Failed to set tuner gain")
            }
        }
        
        // Set frequency correction (PPM)
        if config.frequencyCorrection != 0 {
            let ppmResult = rtl_sdrtlsdr_set_freq_correction(device, Int32(config.frequencyCorrection))
            if ppmResult != 0 {
                // Non-fatal, just log
                print("Warning: Could not set frequency correction")
            }
        }
        
        // Set bias tee
        if config.biasTeeEnabled {
            let biasResult = rtl_sdrtlsdr_set_bias_tee(device, 1)
            if biasResult != 0 {
                print("Warning: Bias tee not supported or failed")
            }
        }
        
        // Set direct sampling
        if config.directSamplingMode > 0 {
            let directResult = rtl_sdrtlsdr_set_direct_sampling(device, config.directSamplingMode)
            if directResult != 0 {
                print("Warning: Direct sampling mode not supported")
            }
        }
        
        self.config = config
    }
    
    // MARK: - Streaming
    
    /// Start IQ sample streaming
    func startStreaming(callback: @escaping ([ComplexFloat]) -> Void) throws {
        guard isOpen, device != nil else {
            throw DeviceError.deviceNotOpen
        }
        
        guard !isStreaming else {
            return  // Already streaming
        }
        
        sampleCallback = callback
        
        // Set up the read callback
        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = rtl_sdrtlsdr_read_async(device, {
            buffer, bytes, context in
            let strongSelf = Unmanaged<RTLSDRDevice>.fromOpaque(context!).takeUnretainedValue()
            strongSelf.handleSamples(buffer: buffer, bytes: bytes)
        }, context, 0, 0)
        
        if result != 0 {
            throw DeviceError.streamingError
        }
        
        isStreaming = true
    }
    
    /// Stop streaming
    func stopStreaming() {
        if device != nil && isStreaming {
            rtl_sdrtlsdr_stop_async(device)
            isStreaming = false
        }
    }
    
    /// Handle incoming samples from C callback
    private func handleSamples(buffer: UnsafePointer<UInt8>?, bytes: Int32) {
        guard let buffer = buffer, bytes > 0 else { return }
        
        samplesReceived += UInt64(bytes)
        
        // Convert uint8_t IQ samples to ComplexFloat
        let sampleCount = Int(bytes) / 2  // 2 bytes per complex sample (I and Q)
        var complexSamples: [ComplexFloat] = []
        complexSamples.reserveCapacity(sampleCount)
        
        for i in 0..<sampleCount {
            let iValue = Float(buffer[i * 2]) - 127.5  // Center around 0
            let qValue = Float(buffer[i * 2 + 1]) - 127.5
            complexSamples.append(ComplexFloat(real: iValue, imag: qValue))
        }
        
        // Call Swift callback
        sampleCallback?(complexSamples)
    }
    
    // MARK: - Utility Methods
    
    /// Get current gain values
    func getGainValues() -> [Int32] {
        guard isOpen, device != nil else { return [] }
        
        let count = rtl_sdrtlsdr_get_tuner_gains(device, nil)
        guard count > 0 else { return [] }
        
        var gains = [Int32](repeating: 0, count: Int(count))
        rtl_sdrtlsdr_get_tuner_gains(device, &gains)
        
        return gains
    }
    
    /// Get device serial number
    func getSerialNumber() -> String? {
        guard isOpen, device != nil else { return nil }
        
        var serial: [CChar] = [CChar](repeating: 0, count: 256)
        let result = rtl_sdrtlsdr_get_usb_strings(device, nil, nil, &serial, nil)
        
        return result == 0 ? String(cString: serial) : nil
    }
    
    /// Reset device statistics
    func resetStatistics() {
        samplesReceived = 0
        sampleLoss = 0.0
    }
    
    /// Get current sample rate
    func getSampleRate() -> UInt32 {
        guard isOpen, device != nil else { return 0 }
        return rtl_sdrtlsdr_get_sample_rate(device)
    }
    
    /// Get current center frequency
    func getCenterFrequency() -> UInt32 {
        guard isOpen, device != nil else { return 0 }
        return rtl_sdrtlsdr_get_center_freq(device)
    }
}

// MARK: - Complex Number Type

/// Complex float for IQ samples
struct ComplexFloat {
    var real: Float
    var imag: Float
    
    init(real: Float, imag: Float) {
        self.real = real
        self.imag = imag
    }
    
    /// Magnitude (amplitude)
    var magnitude: Float {
        return sqrt(real * real + imag * imag)
    }
    
    /// Magnitude squared (faster, no sqrt)
    var magnitudeSquared: Float {
        return real * real + imag * imag
    }
    
    /// Phase (angle)
    var phase: Float {
        return atan2(imag, real)
    }
}

// MARK: - Helper Extensions

extension RTLSDRDevice {
    /// Convenience method to get device count
    static var deviceCount: UInt32 {
        return rtl_sdrtlsdr_get_device_count()
    }
    
    /// Check if a specific tuner type is supported
    static func isTunerSupported(_ tunerType: Int32) -> Bool {
        return tunerType >= 0
    }
}
