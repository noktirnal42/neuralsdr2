# Hardware

The hardware layer provides Swift wrappers for SDR devices, starting with RTL-SDR.

@Metadata {
  @PageImage(purpose: icon, source: "Hardware", alt: "Hardware icon")
}

## Overview

The hardware layer abstracts SDR device interaction through Swift-native APIs. The primary supported device is RTL-SDR, accessed via the `CLibRTLSDR` system library binding.

### Device Enumeration

Discover connected RTL-SDR devices before opening one:

@Code {
  let devices = RTLSDRDevice.enumerateDevices()
  for device in devices {
      print("\(device.name) — \(device.tunerName)")
  }
}

### Device Configuration

Configure sample rate, center frequency, gain, and other parameters using ``RTLSDRConfig``:

@Code {
  var config = RTLSDRConfig()
  config.sampleRate = 2_048_000
  config.centerFrequency = 1090_000_000
  config.gainMode = false
  config.tunerGain = 30.0
  try device.configure(config)
}

### Streaming

Start IQ sample streaming with a callback that receives ``ComplexFloat`` arrays:

@Code {
  try device.startStreaming { iqSamples in
      pipeline.process(samples: iqSamples)
  }
}

## Topics

### Device

- ``RTLSDRDevice``
- ``RTLSDRConfig``
- ``RTLSDRDeviceInfo``

### Errors

- ``RTLSDRDevice/DeviceError``
