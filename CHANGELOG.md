# Changelog

All notable changes to NeuralSDR2 are documented in this file.

## [1.0.0] - 2026-04-18

### 🎉 Initial Release

#### Added - Core Features
- RTL-SDR hardware integration (validated with Nooelec Nano 3)
- Real-time DSP pipeline with < 1ms processing latency
- Complete demodulator suite:
  - AM (envelope & synchronous detection)
  - FM (NFM/WFM with 50μs/75μs deemphasis)
  - SSB (USB/LSB with BFO)
  - CW (Morse) with auto-speed detection
- Digital mode decoders:
  - FT8/FT4 (WSJT-X compatible)
  - PSK31/PSK63
  - RTTY (Baudot/ITA2)
  - RDS (FM broadcast data)

#### Added - Visual Experience
- Three photorealistic UI themes:
  - **Modern**: OLED-style high-contrast displays
  - **Vintage**: Amber incandescent glow with brushed aluminum
  - **Military**: CRT phosphor green with tactical styling
- Metal-accelerated spectrum display (60 fps)
- Metal-accelerated waterfall with 4 color palettes
- 3D Earth visualization using SceneKit
- Virtual Hardware material system (brushed aluminum, walnut, OD green)

#### Added - Mapping
- MapKit-based universal map
- ADS-B aircraft tracking with altitude color coding
- Historical flight tracks
- Satellite ground tracks with pass countdown
- User location with range rings
- 3D Earth orbit visualization

#### Added - Weather Radar
- Hardware-direct NEXRAD via 978 MHz UAT signal
- FIS-B packet decoder
- Multi-lap assembly for complete radar images
- SIGMET/AIRMET support

#### Added - Satellite Tracking
- SGP4/SDP4 orbital propagation
- TLE management with auto-update
- Pass prediction (AOS/LOS/TCA)
- Automatic Doppler correction
- Support for NOAA, Meteor-M, ISS, GOES satellites

#### Added - Recording
- IQ recording (Raw, SigMF, WAV formats)
- Audio recording (WAV, FLAC)
- Metadata management
- Library browser with search

#### Added - Audio
- CoreAudio integration with 18ms latency
- Volume control and mute
- Circular buffer management
- AGC (fast/slow/custom modes)
- Noise squelch

#### Added - UI Controls
- Smart frequency entry (supports MHz, GHz, kHz suffixes)
- Band presets (FM, Air, 2m, 70cm, ADS-B, UAT)
- Bandwidth control with mode-specific presets
- Spectrum markers (normal, delta, peak, bandwidth)
- Frequency bookmarks
- Keyboard shortcuts for all functions

### Performance
- CPU Usage: < 10% (M1)
- Memory: < 150 MB
- Audio Latency: 18 ms
- UI Frame Rate: 60 fps locked
- 24-hour stability test: PASSED

### Platform
- macOS 13.0 (Ventura) or later
- Apple Silicon native (M1/M2/M3)
- Intel with AVX2 support

---

## Development History

### Phase 1: Foundation (Weeks 1-4)
- Week 1: RTL-SDR wrapper, basic UI
- Week 2: DSP pipeline, demodulators
- Week 3: CoreAudio integration
- Week 4: Control panel & main window

### Phase 2: Advanced Features (Weeks 5-10)
- Week 5: Hardware validation
- Week 6: Recording, AGC, markers
- Week 7: UI polish, library browser
- Week 8: CW & RDS decoders
- Week 9: FT8, PSK31, RTTY
- Week 10: Satellite tracking, Doppler

### Phase 3: Advanced UI (Weeks 11-13)
- Week 11: Universal map, NEXRAD
- Week 12: Photorealistic themes
- Week 13: 3D Earth visualization

### Phase 4: Release (Weeks 14-18)
- Week 14: Performance optimization
- Week 15: Documentation
- Week 16: Final testing
- Week 17: Release preparation
- Week 18: v1.0.0 launch

---

## Next Release (v1.1.0 - Planned)

- Playback of recorded IQ files
- Airspy support
- HackRF support
- Network SDR (rtl_tcp)
- Additional decoders (APT, LRPT, HRIT)
- VOR/ILS navigation display

---

*Copyright © 2026 NeuralSDR. All rights reserved.*
