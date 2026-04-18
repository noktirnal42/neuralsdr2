# Contributing to NeuralSDR2

Thank you for your interest in contributing to NeuralSDR2! This document provides guidelines and instructions for contributing.

## Code of Conduct

This project adheres to a Code of Conduct. By participating, you are expected to uphold this code. Please report unacceptable behavior to the project maintainers.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/NeuralSDR2.git`
3. Create a branch: `git checkout -b feature/your-feature-name`
4. Make your changes
5. Test thoroughly
6. Commit with clear messages
7. Push and create a pull request

## Development Setup

### Prerequisites
- Xcode 15+
- macOS 13.0+
- Homebrew
- librtlsdr (`brew install librtlsdr`)
- SoapySDR (`brew install soapyrtlsdr`)

### Building

```bash
# Install dependencies
brew bundle install  # Uses Brewfile

# Build
xcodebuild -scheme NeuralSDR2 -configuration Debug build

# Run tests
xcodebuild -scheme NeuralSDR2 test
```

## Commit Message Format

We follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types
- `feat`: A new feature
- `fix`: A bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

### Examples

```
feat(dsp): Add FIR filter implementation

- Implement FIR filter using vDSP
- Add configurable coefficients
- Include unit tests

Closes #42
```

```
fix(ads-b): Correct altitude calculation

- Fix off-by-one error in altitude conversion
- Add test case for edge cases

Fixes #123
```

## Pull Request Process

1. **Update documentation** if adding features
2. **Add tests** for new functionality
3. **Ensure all tests pass**: `xcodebuild test`
4. **Update CHANGELOG.md** if applicable
5. **Request review** from maintainers

## Areas Needing Contribution

### High Priority
- DSP algorithm optimization
- Decoder implementations (satellite, digital modes)
- RTL-SDR driver improvements
- Performance optimization

### Medium Priority
- Additional demodulator modes
- UI theme improvements
- Accessibility features
- Documentation

### Low Priority
- Additional hardware support (Airspy, HackRF)
- Plugin architecture
- Network streaming

## Coding Standards

### Swift
- Follow [Swift.org API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- Use Swift 5.9+ features where appropriate
- Prefer `let` over `var`
- Use optionals appropriately
- Document public APIs

### C++
- Follow C++17 standard
- Use smart pointers for memory management
- Avoid raw pointers where possible
- Document all public functions
- Use `const` correctness

### DSP Code
- Prioritize performance
- Use Accelerate/vDSP for vectorization
- Avoid allocations in real-time paths
- Document algorithms with references

## Testing

### Unit Tests
- Test DSP algorithms
- Test decoders with known inputs
- Test database operations
- Test utility functions

### Integration Tests
- Test full signal chain
- Test with actual RTL-SDR hardware
- Test file I/O operations

### Performance Tests
- Benchmark DSP throughput
- Measure memory usage
- Test battery impact

## Documentation

### Code Documentation
- Document all public APIs
- Include parameter descriptions
- Document return values
- Add usage examples

### User Documentation
- Update user guide for new features
- Add screenshots where helpful
- Document keyboard shortcuts
- Include troubleshooting tips

## Release Process

1. Update version in `Info.plist`
2. Update `CHANGELOG.md`
3. Create release branch
4. Tag commit: `git tag -a v1.0.0 -m "Version 1.0.0"`
5. Build release
6. Notarize for macOS
7. Create DMG
8. Publish to GitHub Releases

## Questions?

If you have questions, please:
1. Check existing issues and discussions
2. Read the documentation
3. Ask in Discord/forums
4. Create an issue for discussion

---

Thank you for contributing to NeuralSDR2!
