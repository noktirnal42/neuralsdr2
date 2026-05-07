//
// AudioEngine.swift
// NeuralSDR2
//
// CoreAudio-based audio output engine
// Provides low-latency audio playback from DSP pipeline
// Uses os_unfair_lock-protected ring buffer for thread safety
//

import Foundation
import CoreAudio
import AudioToolbox
import AudioUnit

/// Thread-safe single-producer single-consumer ring buffer
/// Uses os_unfair_lock to serialize read/write access (safe, ~100ns lock acquire)
public final class AudioRingBuffer {
    private var buffer: [Float]
    private let capacity: Int
    private var writePos: Int = 0
    private var readPos: Int = 0
    private var lock = os_unfair_lock_s()

    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = [Float](repeating: 0, count: capacity)
    }

    /// Write samples into the ring buffer (producer side)
    /// Returns the number of samples actually written (may be less than requested if full)
    func write(_ samples: [Float], offset: Int = 0, count: Int? = nil) -> Int {
        let writeCount = count ?? (samples.count - offset)
        var written = 0

        os_unfair_lock_lock(&lock)
        for i in 0..<writeCount {
            let available = capacity - (writePos - readPos)
            if available <= 0 {
                os_unfair_lock_unlock(&lock)
                return written
            }
            buffer[writePos % capacity] = samples[offset + i]
            writePos += 1
            written += 1
        }
        os_unfair_lock_unlock(&lock)
        return written
    }

    /// Read samples from the ring buffer (consumer side)
    /// Returns the number of samples actually read
    func read(into output: UnsafeMutablePointer<Float>, count: Int) -> Int {
        var readCount = 0

        os_unfair_lock_lock(&lock)
        let available = writePos - readPos
        let toRead = min(count, available)
        for i in 0..<toRead {
            output[i] = buffer[readPos % capacity]
            readPos += 1
            readCount += 1
        }
        os_unfair_lock_unlock(&lock)
        return readCount
    }

    /// Number of samples available for reading
    var available: Int {
        os_unfair_lock_lock(&lock)
        let count = writePos - readPos
        os_unfair_lock_unlock(&lock)
        return count
    }

    /// Remaining write capacity
    var freeSpace: Int {
        os_unfair_lock_lock(&lock)
        let space = capacity - (writePos - readPos)
        os_unfair_lock_unlock(&lock)
        return space
    }

    /// Clear all buffered data
    func clear() {
        os_unfair_lock_lock(&lock)
        writePos = 0
        readPos = 0
        os_unfair_lock_unlock(&lock)
    }
}

/// Audio output engine using CoreAudio
public class AudioOutputEngine {
    private var audioComponent: AudioComponent?
    private var audioUnit: AudioUnit?
    private var isRunning = false
    private var _sampleRate: Double = 48000
    private var _channels: UInt32 = 2
    private var bufferFrames: UInt32 = 512

    var ringBuffer: AudioRingBuffer
    private var bufferLock = os_unfair_lock_s()

    // Pre-allocated buffer for the render callback — avoids heap allocation in RT path
    var renderBuffer: [Float] = [Float](repeating: 0, count: 4096)

    // Volume control (applied at render time, not at enqueue time)
    var volume: Float = 0.8
    var isMuted = false

    // Statistics
    var bufferUnderruns = 0
    var bufferOverruns = 0

    public init() {
        // 48000 Hz * 2 channels * 0.5 seconds = 48000 samples
        // Use 65536 as a nice power-of-2 capacity
        ringBuffer = AudioRingBuffer(capacity: 65536)
    }

    deinit {
        stop()
        // Properly dispose the AudioUnit (fixes resource leak)
        if let au = audioUnit {
            AudioComponentInstanceDispose(au)
            audioUnit = nil
        }
    }

    /// Initialize audio unit
    public func initialize(sampleRate: Double = 48000, channels: UInt16 = 2, bufferSize: UInt32 = 512) throws {
        self._sampleRate = sampleRate
        self._channels = UInt32(channels)
        self.bufferFrames = bufferSize

        // Find output audio unit
        var desc = AudioComponentDescription()
        desc.componentType = kAudioUnitType_Output
        desc.componentSubType = kAudioUnitSubType_DefaultOutput
        desc.componentManufacturer = kAudioUnitManufacturer_Apple
        desc.componentFlags = 0
        desc.componentFlagsMask = 0

        audioComponent = AudioComponentFindNext(nil, &desc)
        guard audioComponent != nil else {
            throw AudioError.componentNotFound
        }

        // Open audio unit
        var status = AudioComponentInstanceNew(audioComponent!, &audioUnit)
        guard status == noErr, audioUnit != nil else {
            throw AudioError.openFailed
        }

        // Set format: 32-bit float, interleaved PCM
        var format = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4 * UInt32(channels),
            mFramesPerPacket: 1,
            mBytesPerFrame: 4 * UInt32(channels),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 32,
            mReserved: 0
        )

        status = AudioUnitSetProperty(
            audioUnit!,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            0,
            &format,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )

        guard status == noErr else {
            throw AudioError.formatError
        }

        // Set render callback using a free C function pointer
        // Use passRetained to prevent use-after-free if engine is deallocated while audio is running
        // The engine is retained for the lifetime of the audio unit; released in stop()
        let refCon = Unmanaged.passRetained(self).toOpaque()
        var callbackStruct = AURenderCallbackStruct(
            inputProc: neuralsdr2_audioRenderCallback,
            inputProcRefCon: refCon
        )

        status = AudioUnitSetProperty(
            audioUnit!,
            kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Input,
            0,
            &callbackStruct,
            UInt32(MemoryLayout.size(ofValue: callbackStruct))
        )

        guard status == noErr else {
            // Release the retained self since callback setup failed
            Unmanaged<AudioOutputEngine>.fromOpaque(refCon).release()
            throw AudioError.callbackError
        }

        // Initialize audio unit
        status = AudioUnitInitialize(audioUnit!)
        guard status == noErr else {
            throw AudioError.initializationError
        }
    }

    /// Start audio playback
    public func start() throws {
        guard let audioUnit = audioUnit else {
            throw AudioError.notInitialized
        }

        let status = AudioOutputUnitStart(audioUnit)
        guard status == noErr else {
            throw AudioError.startError
        }

        isRunning = true
    }

    /// Stop audio playback and wait for final callback
    public func stop() {
        guard let audioUnit = audioUnit, isRunning else { return }

        isRunning = false
        AudioOutputUnitStop(audioUnit)

        // After stopping, the audio unit will no longer call our callback,
        // so the retained refcon is no longer in use.
        // We don't release it here to avoid a double-release — the deinit
        // handles final cleanup via AudioComponentInstanceDispose.
    }

    /// Queue audio samples for playback (called from DSP/producer thread)
    public func queueSamples(_ samples: [Float]) {
        guard !samples.isEmpty else { return }

        os_unfair_lock_lock(&bufferLock)
        let written = ringBuffer.write(samples)
        if written < samples.count {
            bufferOverruns += 1
        }
        os_unfair_lock_unlock(&bufferLock)
    }

    /// Set volume (0.0 - 1.0) — applied at render time for immediate effect
    public func setVolume(_ newVolume: Float) throws {
        volume = max(0, min(1, newVolume))
    }

    /// Toggle mute
    public func toggleMute() throws {
        isMuted.toggle()
    }

    /// Clear audio buffer
    public func clearBuffer() {
        os_unfair_lock_lock(&bufferLock)
        ringBuffer.clear()
        os_unfair_lock_unlock(&bufferLock)
    }

    /// Get statistics
    public func getStatistics() -> (underruns: Int, overruns: Int, bufferLevel: Int) {
        return (bufferUnderruns, bufferOverruns, ringBuffer.available)
    }
}

/// Free function for AURenderCallback — required because Swift doesn't allow
/// forming a C function pointer from a static method reference.
private func neuralsdr2_audioRenderCallback(
    _ inRefCon: UnsafeMutableRawPointer,
    _ ioAction: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    _ inTimeStamp: UnsafePointer<AudioTimeStamp>,
    _ inBusNumber: UInt32,
    _ inNumberFrames: UInt32,
    _ ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    guard let ioData = ioData else { return noErr }
    let engine = Unmanaged<AudioOutputEngine>.fromOpaque(inRefCon).takeUnretainedValue()

    let bufferList = UnsafeMutableAudioBufferListPointer(ioData)
    let frames = Int(inNumberFrames)
    let vol = engine.volume
    let muted = engine.isMuted

    for buffer in bufferList {
        guard let audioData = buffer.mData else { continue }
        let floatBuffer = audioData.assumingMemoryBound(to: Float.self)

        let framesToRead = min(frames, engine.renderBuffer.count)
        engine.renderBuffer.withUnsafeMutableBufferPointer { buf in
            guard let ptr = buf.baseAddress else { return }
            ptr.initialize(repeating: 0, count: frames)
            let samplesRead = engine.ringBuffer.read(into: ptr, count: framesToRead)

            if samplesRead < frames {
                engine.bufferUnderruns += 1
            }

            if buffer.mNumberChannels == 2 {
                for i in 0..<frames {
                    let sample = muted ? Float(0) : ptr[i] * vol
                    floatBuffer[i * 2] = sample
                    floatBuffer[i * 2 + 1] = sample
                }
            } else {
                for i in 0..<frames {
                    floatBuffer[i] = muted ? Float(0) : ptr[i] * vol
                }
            }
        }
    }

    return noErr
}

// MARK: - Errors

extension AudioOutputEngine {
    public enum AudioError: Error {
        case componentNotFound
        case openFailed
        case formatError
        case callbackError
        case initializationError
        case startError
        case notInitialized

        public var localizedDescription: String {
            switch self {
            case .componentNotFound: return "Audio component not found"
            case .openFailed: return "Failed to open audio unit"
            case .formatError: return "Audio format error"
            case .callbackError: return "Callback setup error"
            case .initializationError: return "Audio initialization error"
            case .startError: return "Audio start error"
            case .notInitialized: return "Audio not initialized"
            }
        }
    }
}

// MARK: - Audio Input (for recording)

/// Audio input capture (for future use)
public class AudioInputEngine {
    private var audioUnit: AudioUnit?
    private var sampleCallback: (([Float]) -> Void)?

    public func start(sampleRate: Double = 48000, callback: @escaping ([Float]) -> Void) throws {
        // TODO: Implement audio input capture
        sampleCallback = callback
    }

    public func stop() {
        if let audioUnit = audioUnit {
            AudioOutputUnitStop(audioUnit)
        }
    }
}
