# NeuralSDR2

**Professional Software Defined Radio for macOS**

NeuralSDR2 is a comprehensive, native macOS SDR (Software Defined Radio) application designed for RTL-SDR USB dongles. It combines professional-grade DSP capabilities with a stunning, photorealistic interface available in three distinct themes: Vintage, Modern, and Military.

![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)
![Platform](https://img.shields.io/badge/platform-macOS%2013.0+-lightgrey.svg)
![Swift](https://img.shields.io/badge/swift-5.9+-orange.svg)
![License](https://img.shields.io/badge/license-GPL%20v3-green.svg)

## Features

### Core SDR
- **Wide frequency coverage**: 24 MHz - 1766 MHz (with RTL-SDR)
- **Multiple demodulation modes**: AM, NFM, WFM, USB, LSB, CW
- **Advanced DSP**: FIR/IIR filters, noise reduction, AGC
- **High-performance spectrum analyzer**: Real-time pandapter with RBW/VBW controls
- **Waterfall display**: Multiple color palettes, persistence controls

### Satellite Operations
- **Automatic satellite tracking**: Real-time position from TLE data
- **Auto-Doppler correction**: Continuous frequency adjustment during passes
- **APT/LRPT decoding**: NOAA, Meteor-M satellite image decoding
- **Pass scheduling**: Automatic recording of satellite passes
- **3D Earth visualization**: Real-time satellite positions and ground tracks

### Aircraft Tracking (ADS-B)
- **Real-time aircraft tracking**: 1090 MHz Mode S decoding
- **Interactive map**: Live aircraft positions with altitude color-coding
- **Weather overlay**: NEXRAD radar integration
- **Flight statistics**: Track counts, range, and coverage

### Digital Modes
- **Amateur radio**: FT8, FT4, PSK31, RTTY, CW
- **Public safety**: P25 Phase 1, DMR, NXDN decoding
- **Broadcast**: RDS for FM radio
- **Scanner features**: Trunking, close call detection, scan lists

### Professional UI
- **Three themes**: Vintage (Yaesu/Kenwood style), Modern (ICOM/FlexRadio), Military (Collins tactical)
- **Photorealistic controls**: Analog meters, tuning knobs, displays
- **Customizable layout**: Flexible workspace arrangement
- **Dark mode support**: Easy on the eyes for nighttime operation

### macOS Integration
- **Native Swift/SwiftUI**: Optimized for Apple Silicon and Intel Macs
- **CoreAudio output**: Low-latency audio with AudioUnits
- **Metal acceleration**: High-performance spectrum and waterfall displays
- **MapKit integration**: 2D aircraft map with 3D Earth visualization
- **Full sandbox support**: Secure, App Store ready

## Installation

### Requirements
- macOS 13.0 (Ventura) or later
- RTL-SDR USB dongle (v3 or v4 recommended)
- Xcode Command Line Tools (for development build)

### Build from Source

```bash
# Clone the repository
git clone https://github.com/yourusername/NeuralSDR2.git
cd NeuralSDR2

# Install dependencies via Homebrew
brew install librtlsdr soapyrtlsdr

# Open in Xcode
open NeuralSDR2.xcodeproj

# Build and run
# (Or use xcodebuild from command line)
```

### Download Release

Pre-built DMG installers available on the [Releases](https://github.com/yourusername/NeuralSDR2/releases) page.

## Documentation

- [Feature Specification](docs/01-FEATURE-SPECIFICATION.md)
- [System Architecture](docs/02-SYSTEM-ARCHITECTURE.md)
- [Implementation Roadmap](docs/03-IMPLEMENTATION-ROADMAP.md)
- [User Guide](docs/USER-GUIDE.md) (coming soon)
- [API Reference](docs/API-REFERENCE.md) (coming soon)

## Project Structure

```
NeuralSDR2/
├── docs/                    # Documentation
│   ├── 01-FEATURE-SPECIFICATION.md
│   ├── 02-SYSTEM-ARCHITECTURE.md
│   └── 03-IMPLEMENTATION-ROADMAP.md
├── src/                     # Source code
│   ├── App/                 # App lifecycle, state management
│   ├── DSP/                 # DSP core (C++/Swift)
│   ├── Hardware/            # RTL-SDR, SoapySDR wrappers
│   ├── Decoders/            # Signal decoders
│   ├── UI/                  # SwiftUI views
│   └── Resources/           # Assets, themes
├── resources/               # External resources
├── releases/                # Built releases
└── tests/                   # Unit and integration tests
```

## Development

### Git Workflow

We use a feature-branch workflow:

```bash
# Create feature branch
git checkout -b feature/your-feature-name

# Make commits with conventional commits format
git commit -m "feat(dsp): add FIR filter implementation"

# Push and create pull request
git push origin feature/your-feature-name
```

### Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

### Building

```bash
# Debug build
xcodebuild -scheme NeuralSDR2 -configuration Debug build

# Release build
xcodebuild -scheme NeuralSDR2 -configuration Release build

# Run tests
xcodebuild -scheme NeuralSDR2 test
```

## Roadmap

### Version 0.1 (Current)
- [x] Project initialization
- [x] Documentation
- [ ] RTL-SDR integration
- [ ] Basic demodulators (AM, FM, SSB)
- [ ] Spectrum display
- [ ] Waterfall display
- [ ] Audio output

### Version 0.2
- [ ] Satellite tracking
- [ ] ADS-B decoding
- [ ] Recording/playback
- [ ] UI themes

### Version 1.0
- [ ] All core features
- [ ] Three complete themes
- [ ] Performance optimization
- [ ] Full documentation

See [Implementation Roadmap](docs/03-IMPLEMENTATION-ROADMAP.md) for full details.

## Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) first.

### Areas We Need Help
- DSP algorithm implementation
- Decoder development (satellite, digital modes)
- UI/UX design
- Documentation
- Testing

## License

This project is licensed under the GPL v3 License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [RTL-SDR](https://www.rtl-sdr.com/) - RTL-SDR dongle drivers
- [GNU Radio](https://www.gnuradio.org/) - DSP inspiration
- [SatDump](https://github.com/SatDump/SatDump) - Satellite decoding reference
- [dump1090](https://github.com/FlightAware/dump1090) - ADS-B decoding reference
- [gpredict](http://gpredict.oz9aec.net/) - Satellite tracking reference

## Contact

- **Website**: https://neuralsdr.org
- **Twitter**: @NeuralSDR
- **Discord**: [Join our Discord server](link)
- **Email**: info@neuralsdr.org

---

*NeuralSDR2 - Professional SDR for macOS*
