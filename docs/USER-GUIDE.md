# NeuralSDR2 - User Guide

**Version**: 1.0.0
**Platform**: macOS 13.0+ (Ventura, Sonoma, Sequoia)
**Hardware**: RTL-SDR USB dongles (RTL2832U + R820T/E4000)

---

## Table of Contents
1. [Getting Started](#getting-started)
2. [Main Interface](#main-interface)
3. [Tuning & Reception](#tuning--reception)
4. [Spectrum & Waterfall](#spectrum--waterfall)
5. [Recording](#recording)
6. [Satellite Tracking](#satellite-tracking)
7. [ADS-B Aircraft Tracking](#ads-b-aircraft-tracking)
8. [Weather Radar (UAT/FIS-B)](#weather-radar-uatfis-b)
9. [UI Themes](#ui-themes)
10. [Digital Modes](#digital-modes)
11. [Keyboard Shortcuts](#keyboard-shortcuts)
12. [Troubleshooting](#troubleshooting)

---

## Getting Started

### System Requirements
- **macOS**: 13.0 (Ventura) or later
- **Processor**: Apple Silicon (M1/M2/M3) or Intel with AVX2
- **Memory**: 4 GB RAM minimum, 8 GB recommended
- **Hardware**: RTL-SDR USB dongle (RTL2832U chipset)

### First Launch
1. Connect your RTL-SDR dongle to a USB port
2. Launch NeuralSDR2 from Applications
3. Grant USB permissions when prompted
4. The app will auto-detect your device
5. Click **Start** to begin receiving

### Tested Hardware
- ✅ Nooelec NESDR Nano 3 (R820T2)
- ✅ RTL-SDR Blog v3/v4
- ✅ Generic RTL2832U dongles
- ⏳ Airspy (planned for v1.1)
- ⏳ HackRF (planned for v1.1)

---

## Main Interface

### Layout Overview
```
┌─────────────────────────────────────────────────┐
│  Toolbar: Start/Stop | Freq | Bands | Device    │
├─────────┬──────────────────────┬────────────────┤
│ Sidebar │   Spectrum Display   │   Inspector    │
│ - Bands │   Waterfall Display  │  - Mode        │
│ - Books │   (Metal-rendered)   │  - Filter      │
│ - Recs  │                      │  - Gain/AGC    │
│         │                      │  - Squelch     │
├─────────┴──────────────────────┴────────────────┤
│  Status: Signal | Freq | Mode | Sample Rate     │
└─────────────────────────────────────────────────┘
```

### Three UI Themes
Switch between themes using the menu or keyboard shortcut `Cmd+T`:
- **Modern**: Clean, high-contrast (ICOM IC-7300 style)
- **Vintage**: Warm amber glow (Yaesu FT-101 style)
- **Military**: CRT phosphor green (tactical avionics style)

---

## Tuning & Reception

### Frequency Entry
- **Direct entry**: Type frequency in the toolbar
  - `100` → 100 MHz (default unit)
  - `100.5 MHz` → 100.5 MHz
  - `1090 MHz` → 1090 MHz
  - `7.074 MHz` → 7.074 MHz (FT8 band)

### Band Presets
| Band | Frequency | Mode |
|------|-----------|------|
| FM Broadcast | 88-108 MHz | WFM + RDS |
| Air Band | 108-137 MHz | AM |
| 2m Ham | 144-148 MHz | NFM |
| 70cm Ham | 420-450 MHz | NFM |
| ADS-B | 1090 MHz | Aircraft tracking |
| UAT | 978 MHz | Weather (FIS-B) |

### Tuning Shortcuts
- `↑/↓`: Fine tune (1 step)
- `Shift+↑/↓`: Coarse tune (10 steps)
- `Cmd+F`: Focus frequency field
- `B`: Add bookmark
- `N`: Next bookmark

---

## Spectrum & Waterfall

### Spectrum Display
- Real-time FFT display (2048 points)
- dB scale on left axis
- Frequency on bottom axis
- **Click-to-tune**: Click anywhere on spectrum to tune there
- **Drag**: Pan across frequency
- **Scroll**: Zoom in/out

### Waterfall
- Color-coded signal history
- Scroll speed adjustable (1-30 lines/sec)
- **Color Palettes**:
  - Thermal (default)
  - Grayscale
  - Rainbow
  - Night vision (green)

### Markers
- Click spectrum to place marker
- Delta markers for bandwidth measurement
- Auto peak-finding
- Bandwidth measurement (-3dB, -6dB)

---

## Recording

### IQ Recording
1. Click the **Record** button in the toolbar
2. Select **IQ Recording** type
3. Choose format:
   - **Raw IQ**: Binary interleaved I/Q
   - **WAV**: Standard WAV with IQ channels
   - **SigMF**: Signal Metadata Format (recommended)
4. Recording saves to `~/NeuralSDR2/Recordings/IQ/`

### Audio Recording
1. Click **Record** → Select **Audio**
2. Format options:
   - **WAV** (uncompressed)
   - **FLAC** (lossless compressed)
3. Saved to `~/NeuralSDR2/Recordings/Audio/`

### Library Browser
- Access via **Library** button
- Search by frequency, mode, date
- Delete old recordings
- Playback (coming in v1.1)

---

## Satellite Tracking

### TLE Management
1. Open **Satellite** menu
2. Click **Update TLEs** to fetch latest from Celestrak
3. Select satellites to track (NOAA 15/18/19, ISS, Meteor-M, etc.)

### Pass Prediction
- View upcoming passes in sidebar
- Color-coded by maximum elevation:
  - 🟢 Excellent (>60°)
  - 🟡 Good (30-60°)
  - 🟠 Marginal (<30°)

### Auto-Tuning with Doppler
1. Enable **Auto Doppler** in Satellite menu
2. Select active satellite
3. App automatically:
   - Tunes to correct frequency
   - Applies real-time Doppler correction
   - Starts recording when satellite rises
   - Stops when satellite sets

### Supported Satellites
- **NOAA 15/18/19**: APT weather images (137 MHz)
- **Meteor-M2/M2-2**: LRPT (137.9 MHz)
- **ISS**: Voice/packet (145.8/437 MHz)
- **GOES-16/18**: HRIT (1691 MHz)

---

## ADS-B Aircraft Tracking

### Setup
1. Tune to **1090 MHz**
2. Select **ADS-B** mode
3. Open the Map panel (View → Map)
4. Aircraft appear on map in real-time

### Map Features
- **Color-coded by altitude**:
  - 🟢 Green: <10,000 ft
  - 🟡 Yellow: 10-25,000 ft
  - 🟠 Orange: 25-40,000 ft
  - 🔴 Red: >40,000 ft
- **Historical tracks** with altitude coloring
- **Aircraft icons** by type
- **Range rings** from your location

### 3D Earth View
- Click the globe icon (bottom-right)
- Rotate, zoom, pan in 3D space
- See satellites in orbit
- View ground tracks over Earth

---

## Weather Radar (UAT/FIS-B)

### Hardware-Direct NEXRAD
NeuralSDR2 decodes real weather radar data from the 978 MHz UAT signal — the same technology used in professional aviation equipment.

### Setup
1. Tune to **978 MHz**
2. Enable **UAT Decoding** in the menu
3. Map shows real-time NEXRAD reflectivity

### What You Can Decode
- **NEXRAD Reflectivity**: Real weather radar
- **SIGMETs/AIRMETs**: Weather warnings
- **METARs**: Airport weather reports
- **TAFs**: Aviation forecasts
- **TFRs**: Temporary Flight Restrictions

### How It Works
UAT transmits FIS-B (Flight Information Service-Broadcast) data at 978 MHz. The app:
1. Demodulates the UAT signal
2. Extracts FIS-B packets
3. Assembles fragmented "laps" (11 total) into full radar image
4. Overlays on the map

---

## UI Themes

### Switching Themes
- **Menu**: View → Theme → [Modern/Vintage/Military]
- **Shortcut**: `Cmd+T` (cycles through themes)

### Vintage Theme
- Warm amber incandescent glow
- Brushed aluminum chassis
- Walnut wood veneer accents
- Analog VU meters with needle physics
- Knurled aluminum knobs
- Acrylic lens overlay on displays

### Modern Theme
- Matte black powder-coat chassis
- OLED-style displays
- Cyan accent LEDs
- Anodized aluminum trim
- Capacitive-style buttons
- Glassmorphism effects

### Military Theme
- Olive drab chassis
- CRT phosphor green displays
- Bat-handle toggle switches with safety covers
- Rugged rotary selectors
- Scanlines and phosphor bloom
- Stenciled labels

---

## Digital Modes

### CW (Morse Code)
- Auto-speed detection (5-30 WPM)
- Manual speed override
- CW skimmer mode (multi-frequency)

### FT8/FT4
- WSJT-X compatible decoding
- Signal-to-noise display
- Grid square tracking
- Auto-logging

### PSK31
- BPSK/QPSK support
- PSK63 high-speed mode
- Real-time text decode

### RTTY
- Baudot code (ITA2)
- 45.45 baud default
- 170 Hz shift detection

### RDS (FM Broadcast)
- Station name (PS)
- Radio text (RT)
- Program type (PTY)
- Traffic announcements

---

## Keyboard Shortcuts

### General
- `Cmd+S`: Start/Stop SDR
- `Cmd+E`: Stop SDR
- `Cmd+Q`: Quit
- `Cmd+,`: Preferences
- `Cmd+T`: Cycle themes

### Tuning
- `↑/↓`: Fine tune
- `Shift+↑/↓`: Coarse tune
- `Cmd+F`: Focus frequency
- `B`: Add bookmark
- `N`: Next bookmark
- `P`: Previous bookmark

### Modes
- `A`: AM
- `F`: NFM
- `W`: WFM
- `U`: USB
- `L`: LSB
- `C`: CW

### Display
- `1`: Spectrum only
- `2`: Waterfall only
- `3`: Combined view
- `M`: Toggle markers
- `Space`: Freeze waterfall

### Recording
- `R`: Start/stop recording
- `Cmd+R`: Open recording dialog
- `Cmd+L`: Library browser

---

## Troubleshooting

### Device Not Detected
1. **Check USB connection**: Try different USB port
2. **Check terminal**: Run `rtl_test -t` to verify hardware
3. **Restart app**: Sometimes the USB driver needs a reset
4. **Check permissions**: System Settings → Privacy & Security → USB

### No Audio
1. Check audio output device in System Settings
2. Verify volume is not muted in NeuralSDR2
3. Check squelch threshold (lower it)
4. Try different demodulator mode

### Poor Reception
1. **Antenna**: Use an appropriate antenna for the frequency
2. **Gain**: Try enabling AGC or adjusting manual gain
3. **Location**: Move to higher/clearer location
4. **Frequency correction**: Set PPM in Preferences

### Distorted Audio
1. Reduce gain (try 20-30 dB)
2. Increase filter bandwidth
3. Check sample rate (2.048 MSps recommended)
4. Verify USB cable quality

### High CPU Usage
1. Reduce FFT size in Preferences
2. Disable waterfall if not needed
3. Close 3D Earth view
4. Reduce display update rate

### Weather Radar Not Showing
1. Tune to exactly 978.000 MHz
2. Enable UAT decoder in menu
3. Wait 2-3 minutes for first lap cycle
4. NEXRAD broadcasts every ~10 minutes
5. Verify antenna is appropriate for UHF

---

## Performance Tips

### For Best Performance
- Use a good quality USB cable (short is better)
- Run on Apple Silicon for optimal speed
- Close other apps during heavy SDR use
- Use external antenna for better signal

### Recording Space
- **IQ at 2.048 MSps**: ~8 MB/sec, 480 MB/min
- **Audio WAV**: ~350 KB/sec, 21 MB/min
- **Audio FLAC**: ~100 KB/sec, 6 MB/min

---

## Community & Support

- **GitHub**: github.com/yourusername/NeuralSDR2
- **Discord**: [Join our Discord server]
- **Documentation**: docs.neuralsdr.org
- **Issues**: GitHub Issues page
- **Email**: support@neuralsdr.org

---

*NeuralSDR2 v1.0.0 — Professional SDR for macOS*
*Copyright © 2026 NeuralSDR. All rights reserved.*
