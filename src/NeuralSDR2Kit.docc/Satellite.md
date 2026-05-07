# Satellite

The satellite layer provides orbit propagation, pass prediction, and Doppler correction.

@Metadata {
  @PageImage(purpose: icon, source: "Satellite", alt: "Satellite icon")
}

## Overview

NeuralSDR2Kit implements SGP4-lite satellite orbit propagation from Two-Line Element (TLE) sets. It calculates satellite positions, predicts passes, and computes Doppler shift corrections for satellite communications.

### TLE Parsing

Create a TLE from standard CelesTrak format lines:

@Code {
  let tle = TLE(
      name: "ISS",
      line1: "1 25544U 98067A 24001.50000000 .00016717 00000-0 30200-3 0 9993",
      line2: "2 25544 51.6416 247.4627 0006703 130.5360 325.0288 15.49560572449197"
  )
}

### Orbit Propagation

Use ``SGP4Propagator`` to compute satellite position at any time:

@Code {
  let propagator = SGP4Propagator(tle: tle)
  let position = propagator.getPosition(at: Date(), observerLat: 37.7749, observerLon: -122.4194)
  print("Altitude: \(position.altitude) km, Elevation: \(position.elevation)°")
}

### Pass Prediction

Find upcoming satellite passes for your location:

@Code {
  let predictor = PassPredictor(propagator: propagator, latitude: 37.7749, longitude: -122.4194)
  if let pass = predictor.findNextPass(maxDays: 14) {
      print("Max elevation: \(pass.maxElevation)°, Duration: \(pass.duration)s")
  }
}

### Doppler Correction

Calculate and apply Doppler shift for satellite frequencies:

@Code {
  let doppler = DopplerCorrection()
  let shift = doppler.calculateShift(rangeRate: position.rangeRate, frequency: 437_000_000)
  let correctedFreq = 437_000_000 + shift
}

## Topics

### Orbit Propagation

- ``TLE``
- ``SGP4Propagator``
- ``SatellitePosition``
- ``OrbitalElements``
- ``LookAngle``

### Pass Prediction

- ``PassPredictor``
- ``SatellitePass``
- ``TLEManager``

### Doppler

- ``DopplerCorrection``
- ``AutoDopplerTracker``
- ``DopplerPrecompensator``
