# NeuralSDR2 v1.1.1

**Release Date:** May 7, 2026

NeuralSDR2 v1.1.1 is the first public GitHub release of the current mission-console direction of the app. It pushes the project beyond a basic tuner shell and closer to an operational macOS SDR workstation built around a universal map, satellite workflows, recording, and internal post-pass decode tooling.

## Highlights

### Universal Operations Map

- Shared map workspace for aircraft, weather, and satellite operations
- Observer location annotation and location-aware map behavior
- dump978 raw feed integration for FIS-B weather overlays
- Decoded NOAA artifact overlays tied back to the library

### Satellite Operations

- TLE-driven pass prediction and satellite tracking
- Doppler-aware pass workflows
- Auto-record queueing for upcoming passes
- Post-pass routing into internal decode/library flows

### Internal Decode Workflows

- Internal NOAA APT artifact generation
- Channel A / Channel B NOAA outputs
- Packet audio analysis and report generation
- Library-side `Decode Again` actions for supported recordings

### Radio Console Improvements

- IQ / no-demod mode
- Speaker monitor mute that does not affect recording
- Improved spectrum and waterfall rendering path for centered full-span IQ display

### Packaging and Repo

- GitHub Actions build workflow
- Local `.app` packaging flow
- Branded README and repository assets

## Validation

- `swift build`
- `swift test`
- `bash ./build_app.sh`

Test suite status at release cut:

- `130 tests`
- `0 failures`

## Release Assets

- `NeuralSDR2-v1.1.1.dmg`
- `NeuralSDR2-v1.1.1.dmg.sha256`

## Known Rough Edges

- Spectrum and waterfall presentation are improved, but still need more visual polish
- Some decoder modes exist but are not yet mature end to end
- The NOAA path is much deeper than the current digital voice path

## Direction

NeuralSDR2 is aiming to become a native macOS SDR mission console, not just a tuner window. This release is the point where that direction is finally visible in both the app shell and the workflow model.
