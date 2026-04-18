# Changelog

All notable changes to NeuralSDR2 are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial project structure and documentation
- Comprehensive feature specification
- System architecture documentation
- UI/UX specification with three themes
- Implementation roadmap (18-week plan)
- Build configuration with Homebrew dependencies
- Contributing guidelines
- GPL v3 license

### Changed
- N/A

### Deprecated
- N/A

### Removed
- N/A

### Fixed
- N/A

### Security
- N/A

---

## [0.1.0] - 2026-04-18

### Added
- Initial commit with project foundation
- README with project overview
- Feature specification covering:
  - Core SDR features (tuning, filtering, demodulation)
  - Spectrum analyzer and waterfall displays
  - Satellite tracking and decoding (APT, LRPT, HRIT)
  - ADS-B aircraft tracking with MapKit
  - Digital modes (FT8, PSK31, P25, DMR)
  - Police scanner features
  - Analog/digital TV decoding
  - RDS for FM broadcasting
  - AI/ML auto-classification
  - Three UI themes (Vintage, Modern, Military)
  - 3D Earth visualization
  - macOS integration (CoreAudio, Metal, MapKit)
- System architecture including:
  - DSP pipeline design (GNU Radio-inspired)
  - Hardware abstraction layer
  - Audio pipeline (CoreAudio)
  - Display engine (Metal)
  - Decoder architecture
  - Satellite tracking (SGP4)
  - Library database (SQLite)
- Implementation roadmap:
  - Phase 1: Foundation (Weeks 1-4)
  - Phase 2: Core Features (Weeks 5-8)
  - Phase 3: Advanced Features (Weeks 9-14)
  - Phase 4: Polish (Weeks 15-18)
- UI/UX specification:
  - Main window layout
  - Theme specifications (Vintage, Modern, Military)
  - Control designs
  - Display layouts
  - Map views (2D and 3D)
  - Library browser
  - Keyboard shortcuts
  - Accessibility requirements

---

## Version Numbering

- **Major** (X.0.0): Breaking changes or major new functionality
- **Minor** (0.X.0): New features, backward compatible
- **Patch** (0.0.X): Bug fixes and minor improvements

---

## Release Timeline

| Version | Target Date | Status |
|---------|-------------|--------|
| 0.1.0   | 2026-04-18  | ✅ Released |
| 0.2.0   | 2026-06-01  | 📅 Planned |
| 0.3.0   | 2026-07-15  | 📅 Planned |
| 1.0.0   | 2026-10-01  | 📅 Planned |

---

## Upgrade Notes

### From 0.0.x to 0.1.0
- Initial release, no upgrade path needed

---

## Known Issues

See [GitHub Issues](https://github.com/NeuralSDR/NeuralSDR2/issues) for current known issues.

---

## Contributors

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines.

---

*Last Updated: 2026-04-18*
