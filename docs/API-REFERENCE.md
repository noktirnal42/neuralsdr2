# NeuralSDR2 API Reference

**Version**: 1.0.0
**Swift Version**: 5.9+

---

## Core Modules

### Hardware Layer

#### `RTLSDRDevice`
```swift
class RTLSDRDevice {
    static func enumerateDevices() -> [RTLSDRDeviceInfo]
    func open(index: UInt32) throws
    func close()
    func configure(_ config: RTLSDRConfig) throws
    func startStreaming(callback: @escaping ([ComplexFloat]) -> Void) throws
    func stopStreaming()
}
```

#### `RTLSDRConfig`
```swift
struct RTLSDRConfig {
    var sampleRate: Double = 2_048_000
    var centerFrequency: Double = 1_090_000_000
    var gainMode: Bool = false  // true = AGC
    var tunerGain: Double = 0
    var frequencyCorrection: Double = 0  // PPM
    var biasTeeEnabled: Bool = false
}
```

---

### DSP Pipeline

#### `DSPBlock` Protocol
```swift
protocol DSPBlock {
    var name: String { get }
    var sampleRate: Double { get set }
    func process(_ input: UnsafePointer<ComplexFloat>,
                _ output: UnsafeMutablePointer<ComplexFloat>,
                count: Int)
    func reset()
    func configure(params: [String: Any])
}
```

#### Demodulators
- `AMDemodulator`: AM signal demodulation
- `FMDemodulator`: FM with deemphasis (NFM/WFM)
- `SSBDemodulator`: USB/LSB with BFO

#### `SpectrumAnalyzer`
```swift
class SpectrumAnalyzer {
    init(fftSize: Int = 2048, sampleRate: Double, centerFrequency: Double)
    func process(_ samples: [ComplexFloat]) -> [Float]
    func getFrequencyAxis() -> [Double]
}
```

#### `AGCProcessor`
```swift
class AGCProcessor {
    init(type: AGCType, sampleRate: Double, threshold: Float)
    func process(_ samples: inout [Float])
    func processComplex(_ samples: inout [ComplexFloat])
    func reset()
}
```

---

### Decoders

#### `CWDecoder`
```swift
class CWDecoder: DSPBlock {
    var onCharacter: ((Character) -> Void)?
    var onWord: ((String) -> Void)?
    var currentWPM: Double
    func setSpeed(_ wpm: Double)
}
```

#### `RDSDecoder`
```swift
class RDSDecoder: DSPBlock {
    var onPS: ((String) -> Void)?
    var onRT: ((String) -> Void)?
    var programService: String
    var radioText: String
}
```

#### `FT8Decoder`, `PSK31Decoder`, `RTTYDecoder`
Standard decoder interfaces with mode-specific callbacks.

---

### Satellite Tracking

#### `TLE`
```swift
struct TLE {
    var name: String
    var line1: String
    var line2: String
    // Parsed orbital elements
    var meanMotion: Double
    var inclination: Double
    var eccentricity: Double
    // ... etc
}
```

#### `SGP4Propagator`
```swift
class SGP4Propagator {
    init(tle: TLE)
    func getPosition(at date: Date, observerLat: Double, observerLon: Double) -> SatellitePosition
}
```

#### `PassPredictor`
```swift
class PassPredictor {
    init(propagator: SGP4Propagator, latitude: Double, longitude: Double)
    func findNextPass(from date: Date) -> SatellitePass?
    func findPasses(days: Int) -> [SatellitePass]
}
```

---

### Recording

#### `RecordingManager`
```swift
class RecordingManager {
    func startIQRecording(frequency: Double, sampleRate: Double,
                         mode: String, format: RecordingFormat) throws -> URL
    func startAudioRecording(frequency: Double, sampleRate: Double,
                            mode: String, format: RecordingFormat) throws -> URL
    func writeSamples(_ samples: [ComplexFloat]) throws
    func writeAudioSamples(_ samples: [Float]) throws
    func stopRecording() throws -> RecordingMetadata?
    func getRecordings(filter: String?) -> [RecordingMetadata]
}
```

---

### Audio Engine

#### `AudioOutputEngine`
```swift
class AudioOutputEngine {
    func initialize(sampleRate: Double, channels: UInt16, bufferSize: UInt32) throws
    func start() throws
    func stop()
    func queueSamples(_ samples: [Float])
    func setVolume(_ newVolume: Float) throws
    func toggleMute() throws
}
```

---

### UI & Themes

#### `ThemeManager`
```swift
class ThemeManager: ObservableObject {
    @Published var currentTheme: HardwareTheme = .modern
    var properties: ThemeProperties
}

enum HardwareTheme: String, CaseIterable {
    case vintage, modern, military
}
```

---

## Extension Points

### Custom Demodulators
Implement `DSPBlock` protocol and register with `DSPPipeline`.

### Custom Decoders
Extend the decoder hierarchy with your own signal processing logic.

### Custom UI Themes
Create new theme properties and register with `ThemeManager`.

---

*For detailed implementation examples, see the source code and inline documentation.*
