//
//  AudioEngine.swift
//  NeuralSDR2
//
//  CoreAudio-based audio output engine
//  Provides low-latency audio playback from DSP pipeline
//

import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation

/// Audio output engine using CoreAudio
public class AudioOutputEngine {
    private var audioComponent: AudioComponent?
    private var audioUnit: AudioUnit?
    private var isRunning = false
    private var sampleRate: Double = 48000
    private var channels: UInt32 = 2
    private var bufferFrames: UInt32 = 512
    
    // Audio buffer (circular)
    private var audioBuffer: [Float] = []
    private var bufferLock = NSLock()
    private var readIndex = 0
    private var writeIndex = 0
    
    // Volume control
    private var volume: Float = 0.8
    private var isMuted = false
    
    // Statistics
    private var bufferUnderruns = 0
    private var bufferOverruns = 0
    
    public init() {}
    
    deinit {
        stop()
    }
    
    /// Initialize audio unit
    public func initialize(sampleRate: Double = 48000, channels: UInt16 = 2, bufferSize: UInt32 = 512) throws {
        self.sampleRate = sampleRate
        self.channels = UInt32(channels)
        self.bufferFrames = bufferSize
        
        // Find output audio unit
        var desc = AudioComponentDescription()
        desc.componentType = kAudioUnitType_Output
        desc.componentSubType = kAudioUnitSubType_DefaultOutput
        desc.componentManufacturer = kAudioUnitManufacturer_Apple
        desc.componentFlags = 0
        desc.componentFlagsMask = 0
        
        guard let components = AudioComponentCopyComponents(&desc, &audioComponent),
              audioComponent != nil else {
            throw AudioError.componentNotFound
        }
        
        // Open audio unit
        var status = AudioComponentInstanceNew(audioComponent!, &audioUnit)
        guard status == noErr, audioUnit != nil else {
            throw AudioError.openFailed
        }
        
        // Set format
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
        
        // Set render callback
        var callbackStruct = AURenderCallbackStruct(
            inputProc: audioRenderCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
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
            throw AudioError.callbackError
        }
        
        // Initialize audio unit
        status = AudioUnitInitialize(audioUnit!)
        guard status == noErr else {
            throw AudioError.initializationError
        }
        
        // Set volume
        try? setVolume(volume)
    }
    
    /// Start audio playback
    public func start() throws {
        guard let audioUnit = audioUnit else {
            throw AudioError.notInitialized
        }
        
        var status = AudioUnitStart(audioUnit)
        guard status == noErr else {
            throw AudioError.startError
        }
        
        isRunning = true
    }
    
    /// Stop audio playback
    public func stop() {
        if let audioUnit = audioUnit, isRunning {
            AudioUnitStop(audioUnit)
            isRunning = false
        }
    }
    
    /// Queue audio samples for playback
    public func queueSamples(_ samples: [Float]) {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        
        for sample in samples {
            // Simple circular buffer logic
            if audioBuffer.count < 100000 {  // Max buffer size
                audioBuffer.append(sample * volume)
            } else {
                bufferOverruns += 1
            }
        }
    }
    
    /// Set volume (0.0 - 1.0)
    public func setVolume(_ newVolume: Float) throws {
        volume = max(0, min(1, newVolume))
        
        if let audioUnit = audioUnit {
            var vol = isMuted ? 0 : volume
            AudioUnitSetParameter(audioUnit, kAudioUnitParameterID_Volume, kAudioUnitScope_Global, 0, vol, 0)
        }
    }
    
    /// Toggle mute
    public func toggleMute() throws {
        isMuted.toggle()
        try setVolume(volume)
    }
    
    /// Clear audio buffer
    public func clearBuffer() {
        bufferLock.lock()
        audioBuffer.removeAll()
        readIndex = 0
        writeIndex = 0
        bufferLock.unlock()
    }
    
    /// Get statistics
    public func getStatistics() -> (underruns: Int, overruns: Int, bufferLevel: Int) {
        return (bufferUnderruns, bufferOverruns, audioBuffer.count)
    }
    
    // MARK: - Internal
    
    private static var instances: [ObjectIdentifier: AudioOutputEngine] = [:]
    
    private static let callbackQueue = DispatchQueue(label: "com.neuralsdr.audio.callback")
    
    private static func audioRenderCallback(
        _ inRefCon: UnsafeMutableRawPointer,
        _ ioAction: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        _ inTimeStamp: UnsafePointer<AudioTimeStamp>,
        _ inBusNumber: UInt32,
        _ inNumberFrames: UInt32,
        _ ioData: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        guard let selfPtr = Unmanaged<AudioOutputEngine>.fromOpaque(inRefCon).takeUnretainedValue() as AudioOutputEngine? else {
            return noErr
        }
        
        let bufferCount = Int(inNumberFrames)
        
        // Fill buffer with audio data
        for bufferIndex in 0..<Int(ioData.pointee.mNumberBuffers) {
            let buffer = ioData.pointee.mBuffers[bufferIndex]
            guard let audioData = buffer.mData else { continue }
            
            let floatBuffer = audioData.assumingMemoryBound(to: Float.self)
            
            for i in 0..<Int(inNumberFrames) {
                var sample: Float = 0
                
                selfPtr.bufferLock.lock()
                if !selfPtr.audioBuffer.isEmpty {
                    sample = selfPtr.audioBuffer.removeFirst()
                } else {
                    selfPtr.bufferUnderruns += 1
                }
                selfPtr.bufferLock.unlock()
                
                // Write to both channels if stereo
                if buffer.mNumberChannels == 2 {
                    floatBuffer[i * 2] = selfPtr.isMuted ? 0 : sample
                    floatBuffer[i * 2 + 1] = selfPtr.isMuted ? 0 : sample
                } else {
                    floatBuffer[i] = selfPtr.isMuted ? 0 : sample
                }
            }
        }
        
        return noErr
    }
}

// MARK: - Errors

extension AudioOutputEngine {
    enum AudioError: Error {
        case componentNotFound
        case openFailed
        case formatError
        case callbackError
        case initializationError
        case startError
        case notInitialized
        
        var localizedDescription: String {
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
            AudioUnitStop(audioUnit)
        }
    }
}
