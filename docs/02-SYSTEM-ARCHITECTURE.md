# NeuralSDR2 - System Architecture

## 1. Overview

NeuralSDR2 is a native macOS SDR application built with Swift/SwiftUI and optimized C++ DSP code. The architecture follows a modular, layered approach with clear separation between hardware abstraction, signal processing, decoders, and user interface.

### 1.1 Architecture Principles

- **Modular**: Each component is independently testable and replaceable
- **Real-time capable**: DSP pipeline optimized for low-latency processing
- **Thread-safe**: Proper synchronization for multi-threaded operations
- **Extensible**: Plugin architecture for future decoders and features
- **Native macOS**: Leverages CoreAudio, Metal, MapKit, and other Apple frameworks

### 1.2 Technology Stack

| Layer | Technology |
|-------|------------|
| **UI** | SwiftUI, AppKit, Metal |
| **Application** | Swift 5.9+ |
| **DSP Core** | C++17, Accelerate/vDSP |
| **Audio** | CoreAudio, AudioUnits |
| **3D Graphics** | SceneKit, Metal |
| **Database** | SQLite3 |
| **Hardware** | librtlsdr, SoapySDR |

---

## 2. High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      UI Layer (Swift/SwiftUI)                    │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌───────────┐  │
│  │ Main Window │ │   Library   │ │  Settings   │ │   3D Map  │  │
│  └─────────────┘ └─────────────┘ └─────────────┘ └───────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                   Application Layer (Swift)                      │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌───────────┐  │
│  │ State Mgr   │ │  Recorder   │ │  Scheduler  │ │  Library  │  │
│  └─────────────┘ └─────────────┘ └─────────────┘ └───────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                    DSP Core Layer (C++/Swift)                    │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌───────────┐  │
│  │ Flowgraph   │ │  Filters    │ │ Demodulators│ │  Decoders │  │
│  └─────────────┘ └─────────────┘ └─────────────┘ └───────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                   Hardware Abstraction (C++)                     │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌───────────┐  │
│  │ RTL-SDR     │ │ SoapySDR    │ │ File Source │ │  Network  │  │
│  └─────────────┘ └─────────────┘ └─────────────┘ └───────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Component Architecture

### 3.1 Hardware Abstraction Layer (HAL)

**Purpose**: Abstract hardware-specific operations for RTL-SDR and other devices

#### 3.1.1 RTLSDRSource
```cpp
class RTLSDRSource {
public:
    // Device management
    static std::vector<Device> enumerateDevices();
    bool open(int deviceIndex);
    void close();
    
    // Configuration
    bool setSampleRate(double rate);
    bool setCenterFrequency(double freq);
    bool setGain(double gain);
    bool setAgcMode(bool enabled);
    
    // Streaming
    bool startStreaming(std::function<void(std::vector<std::complex<float>>)> callback);
    void stopStreaming();
    
    // Status
    bool isStreaming() const;
    double getSampleRate() const;
    double getCenterFrequency() const;
};
```

#### 3.1.2 SoapySDRSource
```cpp
class SoapySDRSource {
    // Wrapper around SoapySDR for multi-device support
    // Supports Airspy, HackRF, SDRplay, etc.
};
```

#### 3.1.3 FileSource
```cpp
class FileSource {
    // Read IQ samples from file (WAV, IQ, SigMF)
    // Support for playback of recorded files
};
```

### 3.2 DSP Pipeline Architecture

Inspired by GNU Radio flowgraph, optimized for macOS.

#### 3.2.1 Flowgraph Core

```cpp
// Base class for all DSP blocks
class DSPBlock {
public:
    virtual void process(const std::complex<float>* input, 
                        std::complex<float>* output,
                        size_t count) = 0;
    virtual void setParams(const std::any& params) = 0;
    virtual size_t getOutputSize() const = 0;
};

// Flowgraph manages block connections and scheduling
class Flowgraph {
private:
    std::vector<std::shared_ptr<DSPBlock>> blocks;
    std::vector<Connection> connections;
    dispatch_queue_t processingQueue;
    
public:
    void addBlock(std::shared_ptr<DSPBlock> block);
    void connect(size_t outputBlock, size_t outputPort,
                size_t inputBlock, size_t inputPort);
    void start();
    void stop();
};
```

#### 3.2.2 Filter Blocks

```cpp
// FIR Filter using vDSP
class FIRFilter : public DSPBlock {
private:
    std::vector<float> coefficients;
    std::vector<float> delayLine;
    size_t coefficientCount;
    
public:
    FIRFilter(const std::vector<float>& coeffs);
    void setCoefficients(const std::vector<float>& coeffs);
    void process(const std::complex<float>* input,
                std::complex<float>* output,
                size_t count) override;
};

// IIR Filter (Butterworth, Chebyshev)
class IIRFilter : public DSPBlock {
    // Implementation using vDSP_IIR struct
};

// Frequency Domain Filter (for wideband processing)
class FrequencyDomainFilter : public DSPBlock {
    // FFT-based filtering for efficiency
};
```

#### 3.2.3 Demodulator Blocks

```cpp
// Base demodulator interface
class Demodulator : public DSPBlock {
protected:
    float sampleRate;
    float bandwidth;
    
public:
    virtual void setBandwidth(float bw);
    virtual void setSampleRate(float rate);
};

// AM Demodulator
class AMDemodulator : public Demodulator {
private:
    bool synchronous;
    float carrierFrequency;
    
public:
    void process(const std::complex<float>* input,
                float* output,  // Real audio output
                size_t count) override;
};

// FM Demodulator
class FMDemodulator : public Demodulator {
private:
    float previousPhase;
    float deemphasis;
    
public:
    void process(const std::complex<float>* input,
                float* output,
                size_t count) override;
};

// SSB Demodulator (USB/LSB)
class SSBDemodulator : public Demodulator {
private:
    float bfoFrequency;
    std::unique_ptr<FIRFilter> filter;
    
public:
    void process(const std::complex<float>* input,
                float* output,
                size_t count) override;
};
```

#### 3.2.4 Resampler

```cpp
class Resampler {
    // Sample rate conversion
    // Polyphase filter bank implementation
    // Supports rational and arbitrary resampling
};
```

### 3.3 Audio Pipeline

#### 3.3.1 CoreAudio Integration

```swift
import CoreAudio
import AudioToolbox

class AudioPipeline {
    private var audioUnit: AudioUnit?
    private var outputBuffer: AudioBufferList?
    
    func setup(sampleRate: Double, channels: Int) -> OSStatus {
        // Create AudioUnit for output
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_DefaultOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        // Configure format
        var format = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 32,
            mReserved: 0
        )
        
        // Set render callback
        var callbackStruct = AURenderCallbackStruct(
            inputProc: audioRenderCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        
        return AudioUnitSetProperty(
            audioUnit!,
            kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Input,
            0,
            &callbackStruct,
            UInt32(MemoryLayout.size(ofValue: callbackStruct))
        )
    }
}
```

#### 3.3.2 Audio Processing

```swift
class AudioProcessor {
    private var agc: AGCProcessor?
    private var deemphasis: DeemphasisFilter?
    private var stereoDecoder: StereoDecoder?
    
    func process(samples: [Float]) -> [Float] {
        var audio = samples
        
        // Apply deemphasis (for FM)
        if let deemphasis = deemphasis {
            audio = deemphasis.apply(audio)
        }
        
        // Apply AGC
        if let agc = agc {
            audio = agc.process(audio)
        }
        
        return audio
    }
}
```

### 3.4 Display Engine

#### 3.4.1 Spectrum Display (Metal)

```swift
import Metal
import MetalKit

class SpectrumDisplay: MTKView {
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var spectrumBuffer: MTLBuffer!
    
    func draw(_ rect: CGRect) {
        // Update spectrum data
        // Render using Metal shaders
    }
}

// Metal shader for spectrum visualization
/*
vertex SpectrumVertex vertex_spectrum(uint index [[vertex_id]],
                                     constant float2* spectrum [[buffer(0)]]) {
    SpectrumVertex out;
    out.position = spectrum[index];
    return out;
}
*/
```

#### 3.4.2 Waterfall Display (Metal)

```swift
class WaterfallDisplay: MTKView {
    private var texture: MTLTexture!
    private var scrollOffset: Int = 0
    
    func updateWaterfall(spectrumData: [Float]) {
        // Shift existing data down
        // Add new spectrum at top
        // Update texture
    }
}
```

#### 3.4.3 S-Meter

```swift
class SMeterView: NSView {
    var signalLevel: Float = -120.0  // dBm
    
    override func draw(_ dirtyRect: NSRect) {
        // Draw analog meter with needle
        // Or digital bargraph
    }
}
```

### 3.5 Decoder Architecture

#### 3.5.1 Base Decoder Interface

```swift
protocol Decoder {
    var name: String { get }
    var sampleRate: Double { get }
    var bandwidth: Double { get }
    
    func process(samples: [ComplexFloat]) -> DecoderOutput?
    func reset()
}

enum DecoderOutput {
    case audio(Float)
    case data(Data)
    case image(CGImage)
    case text(String)
}
```

#### 3.5.2 ADS-B Decoder

```swift
class ADSBDecoder: Decoder {
    func process(samples: [ComplexFloat]) -> DecoderOutput? {
        // Mode S demodulation
        // Preamble detection
        // Bit extraction
        // CRC check
        // Message decoding
        return .data(decodedMessage)
    }
}
```

#### 3.5.3 Satellite Decoder

```swift
class APTDecoder: Decoder {
    func process(samples: [ComplexFloat]) -> DecoderOutput? {
        // Sync pulse detection
        // Line synchronization
        // Image extraction
        // Contrast enhancement
        // Georeferencing
        return .image(processedImage)
    }
}
```

### 3.6 Satellite Tracking

#### 3.6.1 TLE Management

```swift
import CoreLocation

struct TLE {
    var line1: String
    var line2: String
    var epoch: Date
    var name: String
    
    func parse() -> SatelliteElements {
        // Parse TLE format
        // Extract orbital elements
    }
}

class TLEManager {
    func fetchFromCelesTrak() async throws -> [TLE] {
        // Download from celestrak.org
        // Parse TLE data
    }
    
    func updateTLEs() async throws {
        // Auto-update TLEs
    }
}
```

#### 3.6.2 SGP4 Propagation

```swift
import SwiftSGP4  // Wrapper around SGP4 library

class SatelliteTracker {
    private var tle: TLE
    private var propagator: SGP4Propagator
    
    func getCurrentPosition(date: Date) -> CLLocationCoordinate3D {
        // Calculate satellite position
        // Return latitude, longitude, altitude
    }
    
    func getNextPass(date: Date, location: CLLocationCoordinate2D) -> SatellitePass {
        // Find next AOS (Acquisition of Signal)
        // Calculate TCA (Time of Closest Approach)
        // Find LOS (Loss of Signal)
    }
    
    func getDopplerCorrection(date: Date) -> Double {
        // Calculate range rate
        // Convert to frequency shift
    }
}
```

### 3.7 Map Engine

#### 3.7.1 2D Map (MapKit)

```swift
import MapKit

class AircraftMapView: MKMapView {
    func updateAircraft(_ aircraft: [Aircraft]) {
        // Update annotations
        // Animate markers
    }
    
    func addWeatherOverlay(data: WeatherData) {
        // Add NEXRAD overlay
    }
}
```

#### 3.7.2 3D Earth (SceneKit)

```swift
import SceneKit

class EarthScene: SCNScene {
    func setupEarth() {
        // Create sphere geometry
        // Apply Earth texture
        // Add atmosphere glow
        // Setup lighting (sun direction)
    }
    
    func addSatellite(name: String, position: SCNVector3) {
        // Add satellite node
        // Add orbit path
    }
    
    func updateSatellitePositions() {
        // Update positions from TLE
    }
}
```

### 3.8 Library & Database

#### 3.8.1 Recording Manager

```swift
class RecordingManager {
    func startRecording(type: RecordingType, format: RecordingFormat) {
        // Create file
        // Start writing samples
    }
    
    func stopRecording() {
        // Finalize file
        // Update database
    }
    
    func getRecordings(filter: RecordingFilter) -> [Recording] {
        // Query database
        // Return metadata
    }
}
```

#### 3.8.2 Database Schema

```sql
-- Recordings table
CREATE TABLE recordings (
    id INTEGER PRIMARY KEY,
    timestamp DATETIME,
    frequency REAL,
    sample_rate REAL,
    mode TEXT,
    duration REAL,
    file_path TEXT,
    file_size INTEGER,
    notes TEXT,
    tags TEXT
);

-- Satellite passes
CREATE TABLE satellite_passes (
    id INTEGER PRIMARY KEY,
    satellite_name TEXT,
    aos_time DATETIME,
    los_time DATETIME,
    max_elevation REAL,
    recording_id INTEGER,
    FOREIGN KEY (recording_id) REFERENCES recordings(id)
);

-- Aircraft sightings
CREATE TABLE aircraft_sightings (
    id INTEGER PRIMARY KEY,
    icao_hex TEXT,
    callsign TEXT,
    timestamp DATETIME,
    latitude REAL,
    longitude REAL,
    altitude INTEGER,
    speed REAL
);

-- Bookmarks
CREATE TABLE bookmarks (
    id INTEGER PRIMARY KEY,
    frequency REAL,
    name TEXT,
    mode TEXT,
    created DATETIME
);
```

---

## 4. Threading Model

### 4.1 Thread Architecture

```
Main Thread (UI)
├── User input handling
├── Display updates (60 fps)
├── Animation updates
└── Menu actions

DSP Thread (Real-time, high priority)
├── Sample acquisition from hardware
├── DSP pipeline processing
├── Demodulation
└── Audio output

Decoder Threads (as needed)
├── ADS-B decoding
├── Satellite decoding
├── Digital mode decoding
└── RDS decoding

Background Threads
├── TLE updates
├── Database writes
├── Network requests
└── File I/O
```

### 4.2 Synchronization

```swift
class ThreadSafeBuffer<T> {
    private var buffer: [T] = []
    private let queue = DispatchQueue(label: "com.neuralsdr.buffer")
    
    func append(_ item: T) {
        queue.async {
            self.buffer.append(item)
        }
    }
    
    func consume() -> [T] {
        var items: [T] = []
        queue.sync {
            items = buffer
            buffer.removeAll()
        }
        return items
    }
}
```

---

## 5. Memory Management

### 5.1 Buffer Pooling

```swift
class BufferPool {
    private var availableBuffers: [NSMutableData] = []
    private let poolSize: Int
    
    func acquireBuffer() -> NSMutableData {
        if let buffer = availableBuffers.popLast() {
            return buffer
        }
        return NSMutableData(capacity: bufferSize)
    }
    
    func releaseBuffer(_ buffer: NSMutableData) {
        if availableBuffers.count < poolSize {
            buffer.length = 0
            availableBuffers.append(buffer)
        }
    }
}
```

### 5.2 Memory-Mapped Files

For large IQ recordings, use memory-mapped files to avoid loading entire file into RAM.

---

## 6. Performance Considerations

### 6.1 DSP Optimization

- Use Accelerate framework (vDSP) for vectorized operations
- Metal compute shaders for GPU-accelerated DSP
- SIMD instructions for critical paths
- Pre-allocate buffers to avoid allocations during processing

### 6.2 Real-time Priority

```swift
// Set DSP thread to real-time priority
var threadPolicy = pthread_qos_class_t.QOS_CLASS_USER_INTERACTIVE
pthread_set_qos_class_self_np(threadPolicy, 0)
```

### 6.3 Latency Targets

| Operation | Target Latency |
|-----------|----------------|
| Audio output | < 50 ms |
| Spectrum update | < 33 ms (30 fps) |
| Waterfall update | < 33 ms (30 fps) |
| User input response | < 100 ms |
| Frequency change | < 100 ms |

---

## 7. Security Considerations

### 7.1 Sandboxing

- App Sandbox enabled
- Network access only for TLE updates, weather data
- File access limited to user's library folder

### 7.2 Data Privacy

- No personal data transmitted without consent
- Location data stored locally
- Optional anonymous usage statistics

---

*Document Version: 1.0*
*Last Updated: 2026-04-18*

</content>
<parameter=filePath>
/Users/jeremymcvay/dev/NeuralSDR2/docs/02-SYSTEM-ARCHITECTURE.md