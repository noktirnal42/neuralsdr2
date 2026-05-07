# NeuralSDR2 v1.1.1 - UI Bug Fixes

**Release Date:** April 21, 2026  
**Fixes:** UI layout, device detection, error messaging

---

## 🐛 Issues Fixed

### 1. USB Streaming Error (Code: -5)
**Problem:** App showed "Streaming error (code: -5)" when no device connected  
**Fix:** Enhanced error messaging to show "Device disconnected (USB)" with clear instructions  
**Files:** `RTLSDRDevice.swift`

### 2. Spectrum/Waterfall Not Rendering
**Problem:** Black screen with "Tuning..." even when device disconnected  
**Fix:** 
- Added device state check to show "No RTL-SDR Device Connected" message
- Improved icon to antenna symbol
- Shows orange warning text when disconnected

### 3. Sidebar Scrollbars Not Working
**Problem:** Left and right sidebars wouldn't scroll  
**Fix:** Added `.frame(maxHeight: .infinity)` to List components  
**Files:** `ContentView.swift`

### 4. Top Bar Too Tall
**Problem:** Toolbar height not constrained  
**Fix:** 
- Set explicit `frame(height: 44)` on toolbar
- Set explicit `frame(height: 44)` on status bar
- Added `GeometryReader` to properly size main display area

---

## 📝 Changes Summary

| Component | Change | Impact |
|-----------|--------|--------|
| `RTLSDRDevice.swift` | Enhanced error messages for codes -5, -7, -8 | Better UX |
| `SpectrumDisplay.swift` | Device state detection, improved "no device" UI | Clear feedback |
| `ContentView.swift` | Fixed sidebar scroll, toolbar height | Proper layout |
| `ControlPanel.swift` | Fixed List maxHeight | Scrollable sidebars |

---

## 🔧 Technical Details

### Error Code Mapping
```swift
errorCode == -5  // Device disconnected (USB)
errorCode == -7  // Streaming cancelled  
errorCode == -8  // Device busy
```

### Layout Fixes
- Main display: `.frame(maxWidth: .infinity, maxHeight: .infinity)`
- Sidebars: `.frame(maxHeight: .infinity)` for scrollable Lists
- Toolbar/Status: Fixed 44px height each
- Main content: `geometry.size.height - 88` for proper sizing

---

## ✅ Verification

- [x] Build: Clean
- [x] Tests: 117/117 pass
- [x] DMG: Created (1.7M)
- [x] Code signed: Ad-hoc

---

## 📦 Upgrade

Existing v1.1.0 users will see:
- Clearer error messages when device disconnected
- Proper "No Device" state in spectrum display
- Scrollable sidebars
- Correct toolbar height

