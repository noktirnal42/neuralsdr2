# NeuralSDR2Kit

NeuralSDR2 is a software-defined radio (SDR) framework for macOS built with Swift and Accelerate.

@Metadata {
  @PageImage(purpose: icon, source: "NeuralSDR2Kit", alt: "NeuralSDR2 logo")
}

## Overview

NeuralSDR2Kit provides a complete SDR processing chain from raw IQ samples through demodulation to audio output. It uses a GNU Radio-inspired flowgraph architecture where DSP blocks are connected into processing pipelines.

The framework supports RTL-SDR hardware devices, multiple demodulation modes (AM, NFM, WFM, USB, LSB, CW), FFT-based spectrum analysis, satellite orbit propagation via SGP4, and recording in WAV, raw IQ, and SigMF formats.

### Key Features

- **DSP Pipeline**: GNU Radio-style flowgraph with FIR/IIR filters, AGC, squelch
- **Demodulators**: AM (envelope/synchronous), FM (narrow/wideband), SSB (USB/LSB), CW
- **Spectrum Analyzer**: Accelerate-backed FFT with multiple window types
- **Hardware**: RTL-SDR device wrapper with streaming support
- **Satellite**: SGP4 orbit propagation, pass prediction, Doppler correction
- **Recording**: WAV, raw IQ, and SigMF recording with metadata

## Topics

### Getting Started

- <doc:DSP>
- <doc:Hardware>
- <doc:Decoders>
- <doc:Satellite>

### Core Types

- ``ComplexFloat``
- ``DSPBlock``
- ``DSPPipeline``
- ``DemodulatorType``

@Tutorials(name: NeuralSDR2Kit) {
  @Tutorial(name: Getting Started) {
    @Intro(title: "Welcome to NeuralSDR2Kit") {
      NeuralSDR2Kit makes it easy to build SDR applications on macOS using Swift and the Accelerate framework.
    }
    @Section(name: "Setting Up a DSP Pipeline") {
      Create a ``DSPPipeline`` with your sample rate and center frequency, then select a demodulation mode.
      @Code {
        let pipeline = DSPPipeline(sampleRate: 2_048_000, centerFrequency: 1090_000_000)
        pipeline.setDemodulator(.AM)
      }
    }
    @Section(name: "Processing Samples") {
      Feed IQ samples into the pipeline and receive audio output via callback.
      @Code {
        pipeline.onAudioOutput { audioSamples in
        }
        pipeline.process(samples: iqSamples)
      }
    }
  }
}
