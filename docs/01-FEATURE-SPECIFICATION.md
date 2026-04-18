# NeuralSDR2 - Comprehensive Feature Specification

## Executive Summary

NeuralSDR2 is a professional-grade, native macOS Software Defined Radio (SDR) application designed for RTL-SDR USB dongles. It combines the functionality of GQRX, SDR#, SDR++, GNU Radio, dump1090, SatDump, and gpredict into a unified, photorealistic interface with three distinct visual themes (Vintage, Modern, Military).

---

## 1. Core SDR Features

### 1.1 Frequency Control
- **Direct frequency entry**: Numeric keypad with unit suffixes (k, M, G)
- **Tuning steps**: 1 Hz, 10 Hz, 100 Hz, 1 kHz, 10 kHz, 100 kHz, 1 MHz (user-selectable)
- **Fine/coarse tuning**: Dual-speed tuning knob (drag mouse/touchpad)
- **Frequency bands**: Preset amateur, commercial, aviation, marine bands
- **RIT (Receiver Incremental Tuning)**: ±5 kHz fine adjustment
- **Frequency bookmarks**: Save/recall favorite frequencies with labels
- **Frequency scanning**: Programmable scan ranges with dwell time

### 1.2 Filter Controls
- **Filter types**:
  - Low-pass (audio output)
  - High-pass (DC removal)
  - Band-pass (IF filtering)
  - Notch (interference rejection, auto/manual)
  - Band-stop (optional)
- **Filter presets**:
  - AM: 6 kHz, 9 kHz, 12 kHz
  - FM: 12 kHz, 15 kHz, 25 kHz (wide), 5 kHz (narrow)
  - SSB: 2.4 kHz, 1.8 kHz, 500 Hz (narrow)
  - CW: 500 Hz, 250 Hz, 100 Hz
  - FM Broadcast: 200 kHz
  - ADS-B: 1 MHz
- **Custom filter creation**: User-definable bandwidths
- **Filter shape factor**: Selectable (soft, normal, sharp, ultra-sharp)
- **Visual filter display**: Overlay on spectrum showing passband/stopband

### 1.3 Demodulation Modes
| Mode | Bandwidth Options | Features |
|------|------------------|----------|
| **AM** | 3/6/9/12 kHz | Sync detection, sideband selection |
| **NFM** | 5/12/15/25 kHz | De-emphasis (50μs/75μs) |
| **WFM** | 200 kHz | Stereo, RDS, de-emphasis |
| **USB** | 500 Hz - 3 kHz | BFO adjustment |
| **LSB** | 500 Hz - 3 kHz | BFO adjustment |
| **CW** | 100-500 Hz | BFO, sidetone, reverse |
| **FM Broadcast** | 200 kHz | Stereo, RDS |
| **ADS-B** | 1 MHz | 1090 MHz, Mode S |
| **DAB** | 1.5 MHz | Digital audio broadcast |
| **Raw IQ** | Full bandwidth | For external decoders |

### 1.4 Gain Control
- **RF Gain**: Manual or automatic (AGC)
- **IF Gain**: Multi-stage gain control
- **Digital Gain**: Post-ADC gain adjustment
- **AGC modes**:
  - Fast attack/slow decay
  - Variable threshold
  - Hang time adjustment
  - AGC-off (manual)
- **Gain reduction display**: Visual indication of gain stages

### 1.5 Squelch
- **Noise squelch**: Threshold-based on noise floor
- **Signal squelch**: Threshold-based on signal level
- **CTCSS**: 50+ sub-audible tones
- **DCS**: Digital coded squelch
- **Tone scan**: Auto-detect CTCSS/DCS tones

---

## 2. Spectrum & Waterfall Displays

### 2.1 Pandapter (Spectrum Display)
- **Display modes**:
  - Peak hold
  - Average
  - Sample
  - RMS
- **Detection types**:
  - Positive peak
  - Negative peak
  - RMS
  - Average
- **Trace controls**:
  - Persistence (infinite, timed, off)
  - Smoothing (VBW control)
  - Reference level adjustment
  - Scale (dB/div)
- **Markers**:
  - Normal marker (frequency/amplitude readout)
  - Delta marker (relative measurement)
  - Peak search (next/previous)
  - Bandwidth measurement (-3dB, -6dB)
  - Noise marker (noise floor measurement)
- **Spectrum analyzer features**:
  - RBW/VBW controls (1 Hz - 10 MHz)
  - Sweep time display
  - Reference level offset
  - Pre-amplifier toggle
  - Attenuation control

### 2.2 Waterfall Display
- **Display modes**:
  - Intensity (grayscale)
  - Color (multiple palettes)
  - Spectrogram (3D perspective)
- **Color palettes**:
  - Grayscale
  - Inverted grayscale
  - Rainbow
  - Ironbow
  - Thermal
  - Night vision (red/green)
  - Military (amber/green phosphor)
- **Controls**:
  - Speed (scroll rate)
  - Gain/contrast
  - Offset (baseline)
  - Zoom (time axis)
- **Persistence**:
  - Infinite scroll
  - Loop (buffer replay)
  - Freeze frame
- **Waterfall markers**:
  - Time markers
  - Signal event markers
  - Pass prediction overlay

### 2.3 Combined View
- **Layout options**:
  - Spectrum above waterfall
  - Spectrum overlay on waterfall
  - Side-by-side
  - Stacked vertical
- **Synchronization**: Linked frequency/zoom controls
- **Independent scaling**: Separate dB scales per display

---

## 3. Recording & Playback

### 3.1 IQ Recording
- **Formats**:
  - WAV (16-bit, 24-bit, 32-bit float)
  - Complex IQ (I/Q interleaved)
  - SigMF (Signal Metadata Format)
  - GNU Radio compatible
- **Sample rates**: Match source or decimate
- **Compression**: Optional FLAC compression
- **Metadata**:
  - Timestamp
  - Center frequency
  - Sample rate
  - Mode/demodulator
  - Gain settings
  - Location (GPS if available)
  - Notes/annotations

### 3.2 Audio Recording
- **Formats**: WAV, FLAC, MP3, AAC
- **Sample rates**: 8 kHz - 192 kHz
- **Bit depths**: 16, 24, 32-bit
- **Metadata**: ID3 tags with frequency, time, mode
- **Auto-record**: Triggered by signal detection

### 3.3 Playback Features
- **IQ playback**: Re-process recorded IQ files
- **Audio playback**: Built-in audio player
- **Scrubbing**: Seek through recordings
- **Speed control**: 0.25x - 4x playback speed
- **Loop**: A-B repeat, continuous loop
- **Playlist**: Queue multiple recordings

### 3.4 Recording Triggers
- **Manual**: Start/stop recording
- **Schedule**: Time-based recording
- **Signal-based**: Record when signal detected
- **Satellite pass**: Auto-record during passes
- **Threshold**: Record when signal exceeds threshold

---

## 4. Satellite Tracking & Decoding

### 4.1 Satellite Tracking (gpredict-style)
- **TLE management**:
  - Import from CelesTrak, Space-Track
  - Auto-update TLEs (daily/hourly)
  - Manual TLE entry/edit
  - TLE age warning
- **Pass prediction**:
  - Rise, culmination, set times
  - Maximum elevation
  - Pass visibility (day/night)
  - Pass quality rating
- **Real-time tracking**:
  - Current azimuth/elevation
  - Range (distance)
  - Range rate (Doppler)
  - Sun illumination (eclipse status)
- **Multiple satellites**: Track unlimited satellites simultaneously
- **Favorite satellites**: Priority list for quick access

### 4.2 Automatic Doppler Correction
- **Real-time correction**: Continuous frequency adjustment
- **Prediction**: Pre-calculate Doppler curve
- **Manual offset**: Fine-tune correction
- **Display**: Show Doppler shift in real-time

### 4.3 Auto-Record Passes
- **Pre-pass**: Start recording before AOS (Acquisition of Signal)
- **Post-pass**: Continue after LOS (Loss of Signal)
- **Squelch-based**: Stop recording during noise
- **File naming**: Automatic with satellite name, time, frequency

### 4.4 Satellite Decoders

#### 4.4.1 NOAA APT (Automatic Picture Transmission)
- **Satellites**: NOAA-15, 18, 19; Meteor-M2
- **Frequencies**: 137 MHz band
- **Features**:
  - Real-time decoding
  - Sync pulse detection
  - Telemetry extraction
  - Contrast enhancement
  - Georeferencing (lat/lon overlay)
  - Channel selection (visible, IR)
  - Image stitching (for multiple passes)

#### 4.4.2 Meteor LRPT (Low Rate Picture Transmission)
- **Satellites**: Meteor-M2, M2-2, M2-3, M2-4
- **Frequency**: 137.9 MHz
- **Features**:
  - QPSK demodulation
  - Viterbi decoding
  - Reed-Solomon error correction
  - RGB image composition
  - Georeferencing

#### 4.4.3 GOES HRIT/LRIT
- **Satellites**: GOES-16, GOES-18
- **Frequency**: 1691-1694 MHz (L-band)
- **Features**:
  - BPSK demodulation
  - LDPC decoding
  - Image decompression
  - Full disk imagery
  - Mesoscale regions

#### 4.4.4 Himawari HRIT
- **Satellites**: Himawari-8, Himawari-9
- **Frequency**: 1694-1710 MHz
- **Features**: Full disk Earth imagery

#### 4.4.5 ISS SSTV & Video
- **SSTV modes**: PD120, PD180, Martin, Scottie
- **Analog TV**: 2.4 GHz downlink (when active)
- **Packet radio**: APRS, packet TV

### 4.5 Library Organization
- **Recordings library**: Raw IQ and audio recordings
- **Decoded library**: Processed data (images, telemetry)
- **Images library**: Satellite imagery organized by satellite/date
- **TV library**: Analog/digital TV recordings
- **Metadata catalog**: SQLite database with search/filter

---

## 5. ADS-B Aircraft Tracking

### 5.1 ADS-B Decoding (dump1090-style)
- **Frequency**: 1090 MHz
- **Modes**:
  - Mode A (squawk)
  - Mode C (altitude)
  - Mode S (extended squitter)
- **Data displayed**:
  - Callsign
  - ICAO hex code
  - Altitude
  - Ground speed
  - Vertical rate
  - Track (heading)
  - Aircraft type
  - Registration

### 5.2 Map Display
- **Map types**:
  - Standard (road map)
  - Satellite
  - Hybrid
  - Terrain
  - Dark mode
- **Aircraft visualization**:
  - Dynamic icons (aircraft type-specific)
  - Rotation (heading)
  - Size (zoom-dependent)
  - Labels (callsign, altitude, speed)
- **Color coding**:
  - By altitude (low=green, medium=yellow, high=red)
  - By aircraft type
  - By vertical rate (climbing/descending)
- **Tracks**:
  - Trail lines (time-based)
  - Flight path prediction
- **Range rings**: Distance markers from center
- **User location**: Home station marker

### 5.3 Aircraft Features
- **Filtering**:
  - By altitude
  - By aircraft type
  - By callsign
  - By registration
  - By squawk code
- **Search**: Find specific aircraft
- **Click aircraft**: Detailed info popup
- **Follow aircraft**: Center map on selected aircraft
- **Statistics**:
  - Aircraft count
  - Max altitude aircraft
  - Nearest aircraft
  - Messages per second

### 5.4 Weather Radar Integration
- **NEXRAD overlay**:
  - Base reflectivity
  - Composite reflectivity
  - Precipitation estimates
- **Color scales**: dBZ values
- **Animation**: Loop recent scans
- **METAR/TAF**: Aviation weather reports
- **Storm tracking**: Cell movement prediction

### 5.5 Additional Map Features
- **3D Earth view**:
  - Rotatable globe
  - Satellite orbits
  - Ground tracks
  - User location
  - Day/night terminator
- **Ground station network**: See other receivers (optional)
- **FlightAware integration**: Enhanced aircraft data (subscription)

---

## 6. Police Scanner Features

### 6.1 Analog Trunking
- **Motorola Type I**:
  - Control channel decoding
  - Voice channel tracking
  - Talkgroup identification
- **Motorola Type II**:
  - SmartNet
  - SmartZone
  - Talkgroup aliases
- **EDACS**:
  - SCAT (Standard)
  - Narrowband
  - Talkgroup display
- **LTR (Logic Trunked Radio)**:
  - Home channel scanning
  - Talkgroup tracking

### 6.2 Digital Trunking
- **P25 Phase 1**:
  - C4FM demodulation
  - IMBE voice decoding
  - Talkgroup monitoring
  - Encryption detection
- **P25 Phase 2**:
  - H-QPSK modulation
  - AMBE+2 voice
  - TDMA decoding
- **DMR (Digital Mobile Radio)**:
  - Tier I, II, III
  - 4FSK demodulation
  - AMBE voice decoding
  - Talkgroup/scanning
  - Color code selection
- **NXDN**:
  - NXDN-48 (6.25 kHz)
  - NXDN-96 (12.5 kHz)
  - AMBE voice decoding

### 6.3 Scanner Features
- **Quick frequency entry**: Direct numeric input
- **Channel memory**: Store frequencies with labels
- **Scan lists**: Multiple scan groups
- **Priority scan**: Monitor priority channels
- **Close Call** (Near-field detection):
  - Detect nearby transmissions
  - Frequency capture
  - Auto-tune to detected signal
- **Service search**:
  - Police
  - Fire
  - EMS
  - Railroad
  - Aircraft
  - Marine
  - Federal
- **Custom search**: User-defined frequency ranges
- **Hold functions**:
  - Hold on transmission
  - Skip locked channels
  - Delay before resuming scan
- **Weather alerts**:
  - SAME (Specific Area Message Encoding)
  - NOAA weather radio alerts

### 6.4 Scanner Display
- **Frequency display**: Large, clear readout
- **Signal meter**: S-meter with dB indication
- **Mode indicator**: AM, FM, P25, DMR, etc.
- **Talkgroup display**: Alpha tags when available
- **System info**: Trunking system identification
- **Scan status**: Active scan list display

---

## 7. Analog & Digital TV

### 7.1 Analog TV
- **NTSC** (North America):
  - Channel 2-6 (54-88 MHz)
  - Channel 7-13 (174-222 MHz)
  - UHF (470-890 MHz)
  - 525 lines, 29.97 fps
  - Color subcarrier: 3.58 MHz
  - Audio: 4.5 MHz offset (FM)
- **PAL** (Europe/Asia):
  - VHF/UHF bands
  - 625 lines, 25 fps
  - Color subcarrier: 4.43 MHz
- **SECAM** (France/Russia):
  - Sequential color
  - 625 lines, 25 fps
- **Features**:
  - Sync detection
  - Color demodulation
  - Audio extraction
  - Recording (video + audio)
  - Frame capture

### 7.2 Digital TV (DVB)
- **DVB-S/S2** (Satellite):
  - QPSK/8PSK modulation
  - MPEG-2/MPEG-4 video
  - AC3 audio
- **DVB-T/T2** (Terrestrial):
  - COFDM modulation
  - H.264/H.265 video
- **ATSC** (North America):
  - 8-VSB modulation
  - MPEG-2 video
  - AC3 audio
- **ISDB** (Japan/South America):
  - BST-OFDM
  - H.264 video
- **Features**:
  - Signal quality display
  - BER (Bit Error Rate)
  - MER (Modulation Error Ratio)
  - Channel scanning
  - EPG (Electronic Program Guide)

### 7.3 Slow-Scan TV (SSTV)
- **Modes**:
  - Martin (color, 110 seconds)
  - Scottie (color, 110 seconds)
  - PD120, PD180 (color)
  - Robot (B&W)
  - Wraase (various)
- **Features**:
  - Auto-mode detection
  - Color calibration
  - Image enhancement
  - Save decoded images

---

## 8. Ham Radio Digital Modes

### 8.1 FT4/FT8 (WSJT-X compatible)
- **FT8**:
  - 15-second cycles
  - 50 Hz bandwidth
  - -21 dB sensitivity
  - Time-synced (GPS/Internet)
  - 8-character messages
- **FT4**:
  - 7.5-second cycles
  - Faster QSOs
  - Contest mode
- **Features**:
  - Auto-decode
  - Message encoding
  - Log submission (PSK Reporter)
  - DX cluster integration

### 8.2 PSK Modes
- **PSK31**: 31.25 baud, narrow bandwidth
- **PSK63**: 62.5 baud, faster
- **QPSK variants**: Higher efficiency
- **Features**:
  - Waterfall display
  - Auto-tune
  - Text encoding/decoding

### 8.3 RTTY (Radio Teletype)
- **Baudot code**: 45.45 baud (standard)
- **Shift**: 170 Hz standard
- **Features**:
  - Auto-detect shift
  - Error correction
  - File transfer support

### 8.4 Olivia/MFSK
- **Olivia**: Multiple tones, robust in noise
- **MFSK**: Multi-frequency shift keying
- **Features**:
  - Multiple tone detection
  - Forward error correction

### 8.5 CW (Morse Code)
- **Decoder**:
  - Auto-speed detection
  - Manual speed setting
  - Farnsworth timing
  - Noise filtering
- **Encoder**:
  - Text-to-Morse
  - Keyer output
  - Practice mode
- **Display**:
  - Real-time decode
  - Speed readout
  - Signal quality

---

## 9. RDS (Radio Data System)

### 9.1 RDS Features
- **PI** (Program Identification): Station ID code
- **PS** (Program Service): Station name (8 chars)
- **RT** (Radio Text): Scrolling text (64 chars)
- **PTY** (Program Type): Content type
- **AF** (Alternative Frequencies): Other frequencies
- **TA/TP**: Traffic announcements
- **CT** (Clock Time): Time/date
- **EON**: Enhanced Other Networks
- **TMC**: Traffic Message Channel
- **RT+**: Extended Radio Text

### 9.2 Display
- **Station name**: Large, clear display
- **Scrolling text**: RT display
- **Program info**: PTY, time
- **Alternative freqs**: Show when tuned

---

## 10. Measurement Features

### 10.1 Spectrum Analyzer
- **RBW/VBW**: 1 Hz - 10 MHz
- **Detection modes**: Peak, RMS, Average, Sample
- **Trace math**: Max hold, min hold, average
- **Markers**:
  - Frequency/amplitude readout
  - Delta markers
  - Peak search
  - Bandwidth measurement
  - Noise marker
- **Reference level**: Adjustable dBm reference
- **Attenuation**: Input attenuation control
- **Pre-amp**: Optional pre-amplifier

### 10.2 Signal Measurements
- **Channel power**: Power in specified bandwidth
- **Occupied bandwidth**: -X dB bandwidth
- **Adjacent channel power**: ACPR measurements
- **THD+N**: Total harmonic distortion + noise
- **SINAD**: Signal-to-noise and distortion
- **Frequency counter**: High-accuracy measurement

### 10.3 S-Meter
- **S-scale**: S1-S9 + dB over S9
- **Calibration**: User-calibratable
- **Peak hold**: Show peak signal
- **Average**: Smoothing option

---

## 11. Descrambler Features

### 11.1 Analog Scrambling Detection
- **Voice inversion**:
  - Simple inversion detection
  - Split-band inversion
  - Carrier frequency estimation
- **Rolling code**:
  - Hop pattern detection
  - Synchronization
- **Frequency hopping**:
  - Pattern detection
  - Hop rate analysis

### 11.2 Digital Encryption Detection
- **P25**:
  - Algorithm ID display
  - Encryption indicator
  - Key ID display
- **DMR**:
  - Privacy mode indicator
  - Encryption detection
- **Display**:
  - Clear indication of encrypted signals
  - Algorithm type (when detectable)
  - No decryption of encrypted content

### 11.3 Legal Descrambling
- **Simple inversion descrambler**: For unencrypted inverted signals
- **Split-band descrambler**: For split-band inversion
- **Note**: Does not decrypt encrypted communications (P25-AES, etc.)

---

## 12. AI/ML Features

### 12.1 Automatic Modulation Classification
- **Supported modulations**:
  - AM, NFM, WFM
  - USB, LSB
  - CW
  - Digital modes (P25, DMR, etc.)
- **Neural network**: CNN-based classifier
- **Confidence display**: Show classification confidence
- **Auto-tune**: Automatically select demodulator

### 12.2 Signal Detection
- **Noise vs signal**: ML-based detection
- **Signal onset detection**: Start recording on signal
- **Interference detection**: Identify interference types

### 12.3 Auto-Classification
- **Signal type**: Broadcast, two-way, data, etc.
- **Service identification**: Police, fire, aircraft, etc.
- **Pattern recognition**: Repeating patterns

### 12.4 Denoising
- **Deep learning noise reduction**: For audio
- **Signal enhancement**: Improve weak signals

---

## 13. UI Themes

### 13.1 Vintage Theme
**Inspiration**: Yaesu FT-101, Kenwood TS-520, Collins KWM-2

**Visual Elements**:
- Warm brown/cream color scheme
- Analog S-meter with physical needle
- Large tuning knob (photorealistic)
- Incandescent frequency display (amber glow)
- Bakelite textures
- Mechanical buttons
- VU meters with backlighting

**Displays**:
- Spectrum: Phosphor persistence effect
- Waterfall: Amber/green monochrome
- Meters: Analog needle meters

### 13.2 Modern Theme
**Inspiration**: ICOM IC-7300, FlexRadio 6000, Yaesu FT-DX10

**Visual Elements**:
- Dark background (charcoal/black)
- Blue/white accent colors
- Touchscreen-style buttons
- LED indicators
- Minimalist design
- Glass panel effects
- Subtle gradients

**Displays**:
- Spectrum: High-contrast, multiple colors
- Waterfall: Full color palettes
- Meters: Digital bargraphs

### 13.3 Military Theme
**Inspiration**: Collins military radios, Harris tactical, avionics

**Visual Elements**:
- Olive drab/dark green primary
- Rugged button design
- MIL-STD displays
- Amber or green CRT phosphor
- Tactical markings
- Weathered metal textures
- Aviation instrument styling

**Displays**:
- Spectrum: Green/amber monochrome
- Waterfall: Thermal or night vision
- Meters: Aircraft-style gauges

### 13.4 Theme Switching
- Instant theme switch
- Per-window theme override
- Theme preview before applying
- Custom theme creation

---

## 14. 3D Earth Visualization

### 14.1 3D Globe
- **Earth rendering**:
  - Textured sphere (satellite imagery)
  - Day/night cycle (sun position)
  - Atmosphere glow
  - Cloud layer (optional)
- **Camera controls**:
  - Orbit around Earth
  - Zoom in/out
  - Track satellite
  - User location focus

### 14.2 Satellite Visualization
- **Real-time positions**: Updated from TLE
- **Orbit paths**: Elliptical orbit rendering
- **Ground tracks**: Path over Earth surface
- **Footprint circles**: Coverage area
- **Multiple satellites**: Show all tracked satellites

### 14.3 Visual Elements
- **Sun direction**: Lighting from correct direction
- **Day/night terminator**: Shadow line
- **Ground stations**: User and network markers
- **Pass predictions**: Show upcoming passes
- **Time control**: Scrub through time for predictions

---

## 15. VOR Navigation Display

### 15.1 VOR Features
- **Frequency range**: 108.00-117.95 MHz
- **Bearing display**: Radial from station
- **CDI (Course Deviation Indicator)**:
  - Needle deflection
  - TO/FROM indicator
  - OFF flag (poor signal)
- **OBS (Omni Bearing Selector)**:
  - Rotate to select course
  - Course readout

### 15.2 VOR Display
- **Photorealistic instrument**:
  - Analog gauge appearance
  - Needle animation
  - Backlit display
- **Multiple VORs**: Show nearby stations
- **Frequency database**: Built-in VOR database
- **Morse ID**: Audible station identification

---

## 16. macOS Integration

### 16.1 CoreAudio
- **Audio output**:
  - Low-latency AudioUnits
  - Multiple output devices
  - Audio routing
- **Audio input**: For recording from other sources
- **Format conversion**: Automatic sample rate conversion

### 16.2 Native Menus
- **File menu**:
  - New, Open, Save
  - Import/Export
  - Quit
- **Edit menu**:
  - Undo/Redo
  - Cut/Copy/Paste
  - Select All
- **View menu**:
  - Zoom controls
  - Display options
  - Full screen
- **Frequency menu**:
  - Band selection
  - Bookmark management
- **Window menu**:
  - Minimize
  - Bring all to front
- **Help menu**:
  - Documentation
  - About

### 16.3 macOS Features
- **Dark mode**: System dark mode support
- **Full screen**: Native full-screen mode
- **Split screen**: Side-by-side with other apps
- **Touch Bar**: Touch Bar support (if available)
- **Trackpad**: Gesture support
- **Keyboard**: Global shortcuts
- **Notifications**: Event notifications
- **Shortcuts app**: Automation support

---

## 17. Library Organization

### 17.1 Directory Structure
``
NeuralSDR2 Library/
├── Recordings/
│   ├── IQ/
│   │   ├── 2026/
│   │   │   ├── 04/
│   │   │   │   ├── 18/
│   │   │   │   │   ├── recording_1090MHz_20260418_123456.iq
│   │   │   │   │   └── metadata.json
├── Audio/
│   ├── AM/
│   ├── FM/
│   ├── SSB/
│   └── Digital/
├── Decoded/
│   ├── Satellite/
│   │   ├── NOAA-18/
│   │   │   ├── 20260418_123000_APT.png
│   │   │   └── telemetry.json
│   ├── Digital/
│   │   ├── FT8/
│   │   └── ADS-B/
├── Images/
│   ├── Satellite/
│   │   ├── NOAA/
│   │   ├── Meteor/
│   │   └── GOES/
│   └── SSTV/
├── TV/
│   ├── Analog/
│   └── Digital/
└── Database/
    └── catalog.sqlite
``

### 17.2 Database Catalog
- **SQLite database**:
  - Recording metadata
  - Signal detections
  - Satellite passes
  - Aircraft sightings
- **Search**:
  - By date/time
  - By frequency
  - By mode
  - By satellite/aircraft
  - By notes/tags
- **Quick preview**: Thumbnail/preview playback
- **Export**: Export selected recordings

---

## 18. Keyboard Shortcuts

### 18.1 Frequency Control
- `F`: Focus frequency entry
- `↑/↓`: Tune step up/down
- `Shift + ↑/↓`: Coarse tune
- `Option + ↑/↓`: Fine tune
- `B`: Add bookmark
- `S`: Save frequency

### 18.2 Display
- `1`: Show spectrum only
- `2`: Show waterfall only
- `3`: Show combined view
- `F`: Toggle full screen
- `M`: Toggle markers
- `W`: Toggle waterfall freeze

### 18.3 Recording
- `R`: Start/stop recording
- `P`: Pause recording
- `Space`: Play/pause playback

### 18.4 General
- `Cmd + Q`: Quit
- `Cmd + ,`: Preferences
- `Cmd + W`: Close window
- `Cmd + H`: Hide window
- `Cmd + M`: Minimize

---

## 19. Settings & Preferences

### 19.1 Device Settings
- RTL-SDR device selection
- Sample rate selection
- Gain settings
- Bias tee control
- Direct sampling mode
- Frequency correction (PPM)

### 19.2 Audio Settings
- Output device
- Sample rate
- Buffer size
- Latency settings
- Audio format

### 19.3 Display Settings
- Default theme
- Color palettes
- Spectrum settings
- Waterfall settings
- Font sizes

### 19.4 Recording Settings
- Default format
- Default location
- Auto-save settings
- Metadata options

### 19.5 Satellite Settings
- TLE update frequency
- Default satellites
- Recording trigger settings

### 19.6 Map Settings
- Map type default
- Units (feet/meters, knots/km/h)
- Range ring distance
- Aircraft filtering

---

## 20. Accessibility

### 20.1 Features
- VoiceOver support
- Keyboard navigation
- High contrast mode
- Large text option
- Reduced motion option
- Customizable keyboard shortcuts

### 20.2 Compliance
- macOS Accessibility API
- WCAG 2.1 Level AA
- Section 508 compliance

---

## 21. Performance Requirements

### 21.1 Real-time Performance
- Spectrum update: ≥ 30 fps
- Waterfall update: ≥ 30 fps
- Audio latency: < 50 ms
- DSP processing: Real-time capable

### 21.2 Resource Usage
- CPU: < 50% on M1 for basic operation
- Memory: < 500 MB typical
- Disk: Efficient recording management

### 21.3 Compatibility
- macOS 13.0+ (Ventura)
- Apple Silicon native
- Intel Mac support
- RTL-SDR v3/v4 support
- Airspy, HackRF (future)

---

## 22. Future Features (Post-1.0)

### 22.1 Additional Hardware
- Airspy support
- HackRF support
- SDRplay support
- PlutoSDR support
- Network SDR (rtl_tcp)

### 22.2 Additional Decoders
- ACARS (aviation messaging)
- HFDL (HF aviation)
- Inmarsat STD-C
- Iridium
- DMR trunking

### 22.3 Advanced Features
- Multi-SDR synchronization
- Network streaming
- Remote SDR operation
- Plugin architecture
- Scripting (Python, JavaScript)
- Cloud integration

---

*Document Version: 1.0*
*Last Updated: 2026-04-18*
