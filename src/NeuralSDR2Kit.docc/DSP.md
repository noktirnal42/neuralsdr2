# DSP

The DSP layer provides signal processing blocks, filters, and demodulators.

@Metadata {
  @PageImage(purpose: icon, source: "DSP", alt: "DSP pipeline icon")
}

## Overview

The DSP layer implements a GNU Radio-inspired flowgraph architecture. Signal data flows through connected ``DSPBlock`` instances, each performing a specific processing step.

The main entry point is ``DSPPipeline``, which orchestrates the full signal chain:

1. **IQ Input** — Raw complex samples from the SDR hardware
2. **Spectrum Analyzer** — Parallel FFT branch for display
3. **Channel Filter** — FIR lowpass at bandwidth/2
4. **Decimation** — Reduce sample rate (by 32 for narrow modes, by 4 for WFM)
5. **Demodulator** — Mode-specific demodulation (AM/FM/SSB/CW)
6. **AGC** — Automatic gain control at audio rate
7. **Squelch** — Mute weak signals below threshold
8. **Audio Output** — Callback with processed audio samples

### Complex Sample Type

All DSP blocks operate on ``ComplexFloat`` samples, which represent in-phase (I) and quadrature (Q) components of the signal.

@Code {
  let sample = ComplexFloat(real: 0.707, imag: 0.707)
  let magnitude = sample.magnitude
  let phase = sample.phase
}

### Filter Design

Use ``DSPFilterDesign`` to create FIR filter coefficients with the windowed-sinc method.

@Code {
  let coeffs = DSPFilterDesign.lowpassFIR(
      cutoff: 5000,
      sampleRate: 48000,
      transitionWidth: 1000,
      attenuation: 60
  )
  let filter = FIRFilter(name: "Channel", coefficients: coeffs, sampleRate: 48000)
}

### Spectrum Analysis

``SpectrumAnalyzer`` performs FFT-based spectral analysis using Accelerate.

@Code {
  let analyzer = SpectrumAnalyzer(fftSize: 2048, sampleRate: 2_048_000, centerFrequency: 100_000_000)
  let spectrum = analyzer.process(iqSamples)
  let frequencies = analyzer.getFrequencyAxis()
}

## Topics

### Core Types

- ``ComplexFloat``
- ``DSPBlock``
- ``Flowgraph``
- ``BufferPool``
- ``DSPFilterDesign``

### Pipeline

- ``DSPPipeline``
- ``DemodulatorType``

### Filters

- ``FIRFilter``
- ``IIRFilter``

### Demodulators

- ``AMDemodulator``
- ``FMDemodulator``
- ``SSBDemodulator``
- ``WBFMDemodulator``
- ``NBFMDemodulator``

### Spectrum

- ``SpectrumAnalyzer``
- ``WaterfallData``

### Processing

- ``AGCProcessor``
- ``SquelchProcessor``
- ``AGCType``
