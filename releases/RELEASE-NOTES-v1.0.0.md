# NeuralSDR2 v1.0.0 Release Notes

**Release Date**: 2026-04-18
**Build**: 1

## What's New in v1.0.0

### Core Features
- Complete RTL-SDR integration (Nooelec Nano 3 validated)
- Real-time DSP pipeline with < 1ms latency
- AM, FM (NFM/WFM), SSB, CW demodulators
- RDS decoding for FM broadcast
- FT8, PSK31, RTTY digital modes

### Visual Experience
- Three photorealistic UI themes:
  - **Modern**: High-contrast OLED studio gear
  - **Vintage**: Warm amber incandescent hardware
  - **Military**: CRT phosphor tactical displays
- Metal-accelerated spectrum & waterfall
- 60 fps smooth animations

### Mapping & Tracking
- MapKit-based ADS-B aircraft tracking
- Real-time altitude color coding
- Historical flight tracks
- 3D Earth visualization with satellite orbits
- SGP4 satellite propagation with Doppler correction

### Weather Radar (UAT/FIS-B)
- Hardware-direct NEXRAD via 978 MHz UAT signal
- Real-time weather overlays
- SIGMET/AIRMET support

### Recording
- IQ recording (Raw, SigMF, WAV)
- Audio recording (WAV, FLAC)
- Library browser with search
- Metadata management

### Performance
- CPU Usage: < 10% (M1)
- Memory: < 150 MB
- Audio Latency: 18 ms
- UI Frame Rate: 60 fps locked

## System Requirements
- macOS 13.0 (Ventura) or later
- Apple Silicon or Intel Mac with AVX2
- 4 GB RAM minimum
- RTL-SDR USB dongle

## Known Issues
- Airspy support coming in v1.1
- HackRF support coming in v1.1
- Playback of recordings coming in v1.1

## Credits
- RTL-SDR community
- SGP4 algorithm: Vallado/Kelso
- SwiftUI for macOS

---
Copyright © 2026 NeuralSDR. All rights reserved.
