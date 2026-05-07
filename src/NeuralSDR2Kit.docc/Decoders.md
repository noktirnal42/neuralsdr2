# Decoders

Decoders extract structured data from demodulated signals.

@Metadata {
  @PageImage(purpose: icon, source: "Decoders", alt: "Decoders icon")
}

## Overview

NeuralSDR2Kit includes decoders for various signal protocols. Each decoder conforms to the ``DSPBlock`` protocol and processes complex IQ samples to extract message-level data.

### ADS-B

The ADS-B decoder processes 1090 MHz Mode S messages from aircraft transponders. It handles CRC verification, Compact Position Reporting (CPR) decoding, and aircraft tracking.

@Code {
  let decoder = ADSBDecoder()
  let result = decoder.decodeMessage(rawBytes)
  if let result = result {
      print("ICAO: \(result.icao), Callsign: \(result.callsign ?? "unknown")")
  }
}

### CW (Morse Code)

The CW decoder detects Morse code on/off patterns from audio-frequency signals.

@Code {
  let decoder = CWDecoder(sampleRate: 64000)
  decoder.centerFrequency = 700
}

### PSK31

The PSK31 decoder demodulates 31.25 baud BPSK signals used in amateur radio.

### RTTY

The RTTY decoder demodulates radioteletype signals with configurable shift and baud rate.

### RDS

The RDS decoder extracts Radio Data System information from WFM broadcast signals.

## Topics

### ADS-B

- ``ADSBDecoder``
- ``ModeSCRC``
- ``CPRDecoder``

### Digital Modes

- ``CWDecoder``
- ``PSK31Decoder``
- ``RTTYDecoder``
- ``RDSDecoder``

### Digital Voice

- ``P25Decoder``
- ``DMRDecoder``

### Weak Signal

- ``FT8Decoder``
