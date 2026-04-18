# NeuralSDR2 - UI/UX Specification

## 1. Main Window Layout

### 1.1 Overall Structure

```
┌─────────────────────────────────────────────────────────────┐
│  Menu Bar                                                   │
├─────────────────────────────────────────────────────────────┤
│  Toolbar                                                    │
├──────────┬──────────────────────────────────────┬───────────┤
│          │                                      │           │
│  Sidebar │     Main Display Area                │  Inspector│
│          │     - Spectrum                       │  Panel    │
│  - Bands │     - Waterfall                      │           │
│  - Book- │     - 3D Earth (optional)            │  - Freq   │
│  marks   │                                      │  - Mode   │
│  - Recs  │                                      │  - Filter │
│  - Lib   │                                      │  - Gain   │
│          │                                      │           │
├──────────┴──────────────────────────────────────┴───────────┤
│  Status Bar                                                 │
│  [Frequency] [Mode] [S-meter] [Sample Rate] [Device]       │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 Main Display Area

The central area displays one or more of:
- Spectrum analyzer (pandapter)
- Waterfall display
- 3D Earth view
- Map view (ADS-B)
- Satellite pass prediction
- TV/Video output

### 1.3 Sidebar

**Width**: 200-250px (collapsible)

**Sections**:
- **Bands**: Quick band selection (HF, VHF, UHF, etc.)
- **Bookmarks**: Saved frequencies
- **Recordings**: Recent recordings
- **Library**: Full library browser

### 1.4 Inspector Panel

**Width**: 250-300px (collapsible)

**Sections**:
- **Frequency**: Fine/coarse tuning, RIT
- **Mode**: Demodulator selection
- **Filter**: Bandwidth, filter type
- **Gain**: RF gain, IF gain, AGC
- **Audio**: Volume, squelch, deemphasis

---

## 2. Theme Specifications

### 2.1 Vintage Theme

**Inspiration**: Yaesu FT-101, Kenwood TS-520, Collins KWM-2

#### Colors
```swift
struct VintageColors {
    static let primaryBrown = NSColor(red: 0.25, green: 0.15, blue: 0.10, alpha: 1.0)
    static let secondaryBrown = NSColor(red: 0.35, green: 0.22, blue: 0.15, alpha: 1.0)
    static let cream = NSColor(red: 0.96, green: 0.92, blue: 0.85, alpha: 1.0)
    static let brass = NSColor(red: 0.70, green: 0.55, blue: 0.25, alpha: 1.0)
    static let amber = NSColor(red: 1.0, green: 0.50, blue: 0.0, alpha: 1.0)
    static let meterBackgound = NSColor(red: 0.15, green: 0.10, blue: 0.08, alpha: 1.0)
}
```

#### UI Elements
- **Tuning knob**: Large, photorealistic with grip texture
- **S-meter**: Analog needle meter with backlight
- **Frequency display**: Incandescent tube display (amber glow)
- **Buttons**: Mechanical push buttons with labels
- **Textures**: Bakelite, brushed metal, walnut veneer

#### Spectrum Display
- **Background**: Dark amber/black gradient
- **Trace**: Bright amber with phosphor persistence
- **Grid**: Subtle amber grid lines
- **Text**: Amber digits, retro font

#### Waterfall
- **Palette**: Amber monochrome or green phosphor
- **Scroll**: Smooth analog scroll
- **Persistence**: Phosphor decay effect

### 2.2 Modern Theme

**Inspiration**: ICOM IC-7300, FlexRadio 6000, Yaesu FT-DX10

#### Colors
```swift
struct ModernColors {
    static let background = NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1.0)
    static let panel = NSColor(red: 0.12, green: 0.12, blue: 0.18, alpha: 1.0)
    static let accent = NSColor(red: 0.0, green: 0.55, blue: 1.0, alpha: 1.0)
    static let text = NSColor.white
    static let textSecondary = NSColor(red: 0.70, green: 0.70, blue: 0.75, alpha: 1.0)
    static let green = NSColor(red: 0.20, green: 0.80, blue: 0.20, alpha: 1.0)
    static let yellow = NSColor(red: 1.0, green: 0.80, blue: 0.0, alpha: 1.0)
    static let red = NSColor(red: 1.0, green: 0.30, blue: 0.30, alpha: 1.0)
}
```

#### UI Elements
- **Buttons**: Touch-style with subtle gradients
- **Knobs**: Minimalist with LED indicators
- **Displays**: High-contrast LCD appearance
- **Panels**: Glass effect with subtle shadows

#### Spectrum Display
- **Background**: Deep charcoal (#14141F)
- **Trace**: Bright cyan/blue gradient
- **Grid**: Subtle dark grid
- **Text**: Clean sans-serif, white

#### Waterfall
- **Palettes**: Full color (rainbow, thermal, etc.)
- **Scroll**: Crisp digital scroll
- **Effects**: None (clean appearance)

### 2.3 Military Theme

**Inspiration**: Collins military radios, Harris tactical, avionics

#### Colors
```swift
struct MilitaryColors {
    static let oliveDrab = NSColor(red: 0.35, green: 0.35, blue: 0.25, alpha: 1.0)
    static let darkGreen = NSColor(red: 0.15, green: 0.18, blue: 0.12, alpha: 1.0)
    static let tacticalGreen = NSColor(red: 0.20, green: 0.25, blue: 0.18, alpha: 1.0)
    static let amberCRT = NSColor(red: 1.0, green: 0.60, blue: 0.0, alpha: 1.0)
    static let greenCRT = NSColor(red: 0.20, green: 1.0, blue: 0.20, alpha: 1.0)
    static let metal = NSColor(red: 0.30, green: 0.32, blue: 0.30, alpha: 1.0)
}
```

#### UI Elements
- **Buttons**: Rugged, weathered appearance
- **Knobs**: Military-style with grip patterns
- **Displays**: CRT phosphor glow
- **Textures**: Brushed metal, rubber grips

#### Spectrum Display
- **Background**: Dark green/amber CRT
- **Trace**: Bright green or amber with glow
- **Grid**: Military grid overlay
- **Text**: Green/amber, tactical font

#### Waterfall
- **Palette**: Night vision (green/red), thermal
- **Effects**: CRT scanlines, slight curvature

---

## 3. Control Specifications

### 3.1 Frequency Control

```
┌─────────────────────────────┐
│  ┌─────────────────────┐    │
│  │  145.525.000 MHz    │    │  ← Digital display
│  └─────────────────────┘    │
│                             │
│  [◄]  Tune  [►]            │  ← Left/right arrows
│                             │
│  Step: [▼ 1 kHz ▼]         │  ← Tuning step selector
│                             │
│  RIT: [====●====] ±0 kHz   │  ← Fine tuning slider
└─────────────────────────────┘
```

### 3.2 Mode Selector

```
┌─────────────────────────────┐
│  Mode:                      │
│  ┌─────┬─────┬─────┬─────┐  │
│  │ AM  │ NFM │ USB │ LSB │  │
│  └─────┴─────┴─────┴─────┘  │
│  ┌─────┬─────┬─────┬─────┐  │
│  │ CW  │ WFM │ DSB│ PAGC│  │
│  └─────┴─────┴─────┴─────┘  │
└─────────────────────────────┘
```

### 3.3 Filter Control

```
┌─────────────────────────────┐
│  Filter Bandwidth           │
│  ┌─────────────────────┐    │
│  │  ▓▓▓▓▓░░░░░░░░░░  │    │  ← Visual indicator
│  │  2.4 kHz           │    │
│  └─────────────────────┘    │
│                             │
│  [Narrow] [Normal] [Wide]  │  ← Presets
│                             │
│  Shape: [●───────○]         │  ← Filter shape
└─────────────────────────────┘
```

### 3.4 Gain Control

```
┌─────────────────────────────┐
│  RF Gain                    │
│  ┌─────────────────────┐    │
│  │  [●───────────○]    │ 45 │  ← Slider
│  └─────────────────────┘    │
│                             │
│  IF Gain                    │
│  ┌─────────────────────┐    │
│  │  [●───────○]        │ 20 │
│  └─────────────────────┘    │
│                             │
│  [✓] AGC  [ ] Pre-amp      │  ← Checkboxes
└─────────────────────────────┘
```

### 3.5 S-Meter

**Analog Style (Vintage/Military)**:
```
    ┌─────────────────────┐
    │  S-METER            │
    │  ┌───────────────┐  │
    │  │  ▓▓▓▓▓░░░░░░  │  │  ← Needle position
    │  │ S9 +20        │  │
    │  └───────────────┘  │
    └─────────────────────┘
```

**Digital Style (Modern)**:
```
┌─────────────────────────────┐
│  Signal: -53 dBm            │
│  [████████████░░░░] S9+20  │  ← Bargraph
│  Peak: -48 dBm              │
└─────────────────────────────┘
```

---

## 4. Display Specifications

### 4.1 Spectrum Display

**Dimensions**: Full width, 200-300px height minimum

**Elements**:
- Frequency axis (bottom)
- Amplitude axis (left)
- Current trace (live)
- Max hold trace (optional)
- Min hold trace (optional)
- Average trace (optional)
- Markers (frequency/amplitude readout)
- Filter overlay (passband visualization)

**Controls**:
- Zoom in/out (frequency span)
- Pan (center frequency)
- Reference level (dB)
- Scale (dB/div)
- RBW/VBW
- Trace mode (max hold, average, sample)
- Persistence (infinite, timed, off)

### 4.2 Waterfall Display

**Dimensions**: Full width, 200-400px height

**Elements**:
- Spectrum image (scrolling)
- Frequency axis (bottom)
- Time scale (right side)
- Current frequency marker
- Signal event markers

**Controls**:
- Speed (scroll rate)
- Gain/contrast
- Offset (baseline)
- Color palette selector
- Freeze toggle
- Zoom (time axis)

### 4.3 Combined View Layouts

**Layout A: Stacked**
```
┌─────────────────────────────┐
│     Spectrum Display        │
├─────────────────────────────┤
│     Waterfall Display       │
└─────────────────────────────┘
```

**Layout B: Overlay**
```
┌─────────────────────────────┐
│  Spectrum (transparent)     │
│  overlaid on Waterfall      │
└─────────────────────────────┘
```

**Layout C: Side-by-Side**
```
┌──────────────┬──────────────┐
│   Spectrum   │  Waterfall   │
│              │              │
└──────────────┴──────────────┘
```

---

## 5. Map Views

### 5.1 2D Aircraft Map

**Framework**: MapKit

**Elements**:
- Base map (standard, satellite, hybrid)
- Aircraft annotations (dynamic icons)
- User location marker
- Range rings
- Weather overlay (NEXRAD)
- Coverage area

**Aircraft Annotation**:
```
     ▲  ← Aircraft icon (rotates with heading)
    ╱ │ ╲
   ╱  │  ╲
  └───┴───┘
  N12345        ← Callsign
  FL350 450kts  ← Altitude, speed
```

**Color Coding by Altitude**:
- 0-10,000 ft: Green
- 10,000-25,000 ft: Yellow
- 25,000-40,000 ft: Orange
- 40,000+ ft: Red

### 5.2 3D Earth View

**Framework**: SceneKit

**Elements**:
- Textured Earth sphere
- Atmosphere glow
- Cloud layer (optional)
- Satellite positions
- Orbit paths
- Ground tracks
- User location marker
- Sun direction (day/night terminator)
- Pass prediction overlay

**Camera Controls**:
- Orbit (drag to rotate)
- Zoom (scroll wheel)
- Track satellite (follow mode)
- Reset view (home position)

---

## 6. Library Browser

### 6.1 Layout

```
┌─────────────────────────────────────────┐
│  Library                                │
├─────────────┬───────────────────────────┤
│             │                           │
│  Recordings │  ┌─────┬─────┬─────┐     │
│  > Audio    │  │ ▓▓▓ │ ▓▓▓ │ ▓▓▓ │     │  ← Thumbnails
│  > IQ       │  │     │     │     │     │
│  > Images   │  └─────┴─────┴─────┘     │
│  > TV       │  2026-04-18 12:34        │
│             │  1090 MHz ADS-B          │
│  Satellites │  2.4 MB                  │
│  > NOAA     │                           │
│  > Meteor   │                           │
│  > GOES     │                           │
│             │                           │
└─────────────┴───────────────────────────┘
```

### 6.2 Metadata Display

Each recording shows:
- Thumbnail/waveform preview
- Date/time
- Frequency
- Mode
- Duration
- File size
- Notes/tags

---

## 7. Settings Windows

### 7.1 Device Settings

```
┌─────────────────────────────────────┐
│  Device Settings                    │
├─────────────────────────────────────┤
│                                     │
│  Device: [RTL-SDR USB Dongle ▼]    │
│  Sample Rate: [2.048 MSps ▼]       │
│                                     │
│  Gain Control:                      │
│  ○ Manual  ● AGC                   │
│                                     │
│  RF Gain: [████████░░] 45 dB       │
│                                     │
│  Frequency Correction: [±0 PPM]    │
│                                     │
│  [✓] Enable Bias Tee               │
│  [✓] Direct Sampling               │
│                                     │
│        [Cancel]        [Save]      │
└─────────────────────────────────────┘
```

### 7.2 Audio Settings

```
┌─────────────────────────────────────┐
│  Audio Settings                     │
├─────────────────────────────────────┤
│                                     │
│  Output Device: [Built-in Output ▼]│
│  Sample Rate: [48000 Hz ▼]         │
│                                     │
│  Buffer Size: [1024 samples ▼]     │
│  Latency: 21 ms                    │
│                                     │
│  [✓] Enable Deemphasis (FM)        │
│  [✓] Enable AGC                    │
│                                     │
│        [Cancel]        [Save]      │
└─────────────────────────────────────┘
```

---

## 8. Keyboard Shortcuts

### 8.1 Frequency Control
| Shortcut | Action |
|----------|--------|
| `Cmd+F` | Focus frequency entry |
| `↑/↓` | Tune step up/down |
| `Shift+↑/↓` | Coarse tune |
| `Option+↑/↓` | Fine tune |
| `Cmd+B` | Add bookmark |
| `Cmd+S` | Save frequency |

### 8.2 Display
| Shortcut | Action |
|----------|--------|
| `1` | Spectrum only |
| `2` | Waterfall only |
| `3` | Combined view |
| `Cmd+F` | Toggle full screen |
| `Cmd+M` | Toggle markers |
| `Cmd+W` | Freeze waterfall |

### 8.3 Recording
| Shortcut | Action |
|----------|--------|
| `Cmd+R` | Start/stop recording |
| `Cmd+P` | Pause recording |
| `Space` | Play/pause playback |

### 8.4 General
| Shortcut | Action |
|----------|--------|
| `Cmd+,` | Preferences |
| `Cmd+Q` | Quit |
| `Cmd+H` | Hide window |
| `Cmd+M` | Minimize |

---

## 9. Accessibility

### 9.1 Features
- **VoiceOver**: Full support for screen readers
- **Keyboard Navigation**: All functions accessible via keyboard
- **High Contrast Mode**: Enhanced visibility
- **Large Text**: Scalable UI text
- **Reduced Motion**: Disable animations
- **Custom Shortcuts**: User-definable keyboard shortcuts

### 9.2 Compliance
- **WCAG 2.1 Level AA**: Meets guidelines
- **Section 508**: Compliant
- **macOS Accessibility API**: Full implementation

---

## 10. Responsive Design

### 10.1 Minimum Window Size
- Width: 800px
- Height: 600px

### 10.2 Recommended Window Size
- Width: 1200px
- Height: 800px

### 10.3 Full Screen
- Optimized for user's display resolution
- All controls remain accessible
- Optional overlay controls

---

*Document Version: 1.0*
*Last Updated: 2026-04-18*
