# NeuralSDR2 - Quick Start Guide

## For Developers Starting Week 1

This guide will help you get started with NeuralSDR2 development.

---

## Prerequisites

- [ ] macOS 13.0+ (Ventura or later)
- [ ] Xcode 15+ installed
- [ ] Xcode Command Line Tools installed
- [ ] Homebrew installed
- [ ] RTL-SDR dongle (for testing)
- [ ] Git installed

---

## Step 1: Install Dependencies

```bash
# Navigate to project directory
cd /Users/jeremymcvay/dev/NeuralSDR2

# Install Homebrew dependencies
brew bundle install

# Verify installations
rtl_test -t  # Should show your RTL-SDR device
```

### Dependencies Installed:
- `librtlsdr` - RTL-SDR driver
- `soapyrtlsdr` - SoapySDR abstraction layer
- `ffmpeg` - Codec support
- `sqlite` - Database
- `cmake` - Build system
- `pkg-config` - Build configuration

---

## Step 2: Create Xcode Project

### 2.1 Create New Project
1. Open Xcode
2. File → New → Project
3. macOS → App
4. Product Name: **NeuralSDR2**
5. Interface: **SwiftUI**
6. Language: **Swift**
7. Uncheck "Use Core Data"
8. Choose location: `/Users/jeremymcvay/dev/NeuralSDR2/`

### 2.2 Configure Project Settings
- **Deployment Target**: macOS 13.0
- **Device Orientation**: Landscape (primary)
- **App Icon**: Create or use default

### 2.3 Add Capabilities
- **App Sandbox**: Enable
- **Network**: Enable (for TLE updates, weather data)
- **USB**: Enable (for RTL-SDR access)

### 2.4 Project Structure
Create these groups in Xcode:
```
NeuralSDR2/
├── App/
│   ├── NeuralSDR2App.swift
│   └── AppDelegate.swift
├── Models/
├── Views/
│   ├── Main/
│   ├── Controls/
│   └── Displays/
├── DSP/
├── Hardware/
└── Resources/
```

---

## Step 3: Create Basic App Structure

### 3.1 Main App File
```swift
// NeuralSDR2App.swift
import SwiftUI

@main
struct NeuralSDR2App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1024, minHeight: 768)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
```

### 3.2 Content View
```swift
// ContentView.swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Text("NeuralSDR2")
                .font(.title)
            Text("Version 0.1.0")
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
```

---

## Step 4: Build and Test

```bash
# From project root
xcodebuild -scheme NeuralSDR2 -configuration Debug build

# Or open in Xcode and press Cmd+B
```

**Expected Result**: App builds successfully and displays basic window.

---

## Step 5: RTL-SDR Integration (Next Steps)

After basic app works, implement:

1. **Swift wrapper for librtlsdr**
   - Create C++ wrapper class
   - Bridge to Swift with SwiftPM or manual wrapper

2. **Sample streaming**
   - Test IQ sample acquisition
   - Verify sample rate and frequency tuning

3. **Basic UI controls**
   - Frequency entry
   - Mode selection
   - Gain control

---

## Testing

### Test 1: Basic App
- [ ] App launches
- [ ] Window appears
- [ ] No console errors

### Test 2: RTL-SDR Detection
- [ ] Device enumerated
- [ ] Can set frequency
- [ ] Can set sample rate

### Test 3: Sample Streaming
- [ ] IQ samples received
- [ ] Sample rate is correct
- [ ] No buffer underruns

---

## Common Issues

### Issue: "librtlsdr not found"
**Solution**: 
```bash
brew install librtlsdr
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"
```

### Issue: "USB permissions"
**Solution**: Create `/etc/usbx/51-rtlsdr.rules`:
```
# RTL-SDR
SUBSYSTEM=="usb", ATTR{idVendor}=="0bda", ATTR{idProduct}=="2838", MODE="0666"
```

### Issue: "Xcode build fails"
**Solution**:
- Check macOS version (13.0+ required)
- Update Xcode to latest version
- Clean build folder (Shift+Cmd+K)

---

## Next Steps After Week 1

Once basic structure is working:

1. **Week 2**: DSP pipeline implementation
2. **Week 3**: Spectrum display (Metal)
3. **Week 4**: Demodulators and audio output

See [IMPLEMENTATION-ROADMAP.md](docs/03-IMPLEMENTATION-ROADMAP.md) for full timeline.

---

## Resources

### Documentation
- [Feature Specification](docs/01-FEATURE-SPECIFICATION.md)
- [System Architecture](docs/02-SYSTEM-ARCHITECTURE.md)
- [UI/UX Specification](docs/04-UI-UX-SPECIFICATION.md)

### External References
- [RTL-SDR](https://www.rtl-sdr.com/)
- [librtlsdr](https://github.com/osmocom/rtl-sdr)
- [GNU Radio](https://www.gnuradio.org/)
- [Swift.org](https://swift.org)
- [Apple Developer](https://developer.apple.com)

### Getting Help
- Check existing issues on GitHub
- Review documentation thoroughly
- Ask in project Discord/forums

---

## Development Tips

1. **Start simple**: Get basic functionality working first
2. **Test frequently**: Use RTL-SDR with known signals
3. **Profile early**: Check performance from the start
4. **Document as you go**: Update docs when adding features
5. **Follow conventions**: Adhere to project coding standards

---

*Last Updated: 2026-04-18*  
*Document Version: 1.0*
