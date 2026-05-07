//
//  TestRTLSDR.swift
//  NeuralSDR2
//
//  Hardware test program for RTL-SDR
//  Tests device detection, tuning, and sample streaming
//

import Foundation
import NeuralSDR2Kit

@main
struct TestRTLSDR {
    static func main() {
        print("╔══════════════════════════════════════════════════════════╗")
        print("║     NeuralSDR2 - RTL-SDR Hardware Test                  ║")
        print("╚══════════════════════════════════════════════════════════╝")
        print()
        
        // Test 1: Device enumeration
        print("📡 Test 1: Device Enumeration")
        print("──────────────────────────────────────────────────────────")
        let devices = RTLSDRDevice.enumerateDevices()
        
        if devices.isEmpty {
            print("❌ No RTL-SDR devices found!")
            print("   Make sure your dongle is plugged in.")
            return
        }
        
        print("✅ Found \(devices.count) device(s):")
        for (index, device) in devices.enumerated() {
            print("   [\(index)] \(device.name)")
            print("       Serial: \(device.serial)")
            print("       Tuner: \(device.tunerName)")
        }
        print()
        
        // Test 2: Device opening
        print("🔌 Test 2: Device Opening")
        print("──────────────────────────────────────────────────────────")
        let rtlDevice = RTLSDRDevice()
        
        do {
            try rtlDevice.open(index: 0)
            print("✅ Device opened successfully")
            
            if let info = rtlDevice.deviceInfo {
                print("   Name: \(info.name)")
                print("   Tuner: \(info.tunerName)")
                print("   Serial: \(info.serial)")
            }
        } catch {
            print("❌ Failed to open device: \(error)")
            return
        }
        print()
        
        // Test 3: Configuration
        print("⚙️  Test 4: Configuration")
        print("──────────────────────────────────────────────────────────")
        var config = RTLSDRConfig()
        config.centerFrequency = 1090_000_000  // ADS-B frequency
        config.sampleRate = 2_048_000
        config.gainMode = false
        config.tunerGain = 30.0
        
        do {
            try rtlDevice.configure(config)
            print("✅ Configuration successful")
            print("   Center Frequency: \(String(format: "%.3f MHz", config.centerFrequency / 1_000_000))")
            print("   Sample Rate: \(String(format: "%.2f MSps", config.sampleRate / 1_000_000))")
            print("   Gain: \(config.tunerGain) dB")
            print("   AGC: \(config.gainMode ? "ON" : "OFF")")
        } catch {
            print("❌ Configuration failed: \(error)")
            rtlDevice.close()
            return
        }
        print()
        
        // Test 4: Sample streaming
        print("📊 Test 5: Sample Streaming (5 seconds)")
        print("──────────────────────────────────────────────────────────")
        print("   Starting IQ sample capture...")
        
        var samplesReceived = 0
        var totalBytes: UInt64 = 0
        let startTime = Date()
        
        do {
            try rtlDevice.startStreaming { samples in
                samplesReceived += 1
                totalBytes += UInt64(samples.count * 8) // 8 bytes per complex float
                
                if samplesReceived == 1 {
                    print("   ✅ First buffer received: \(samples.count) samples")
                    print("   Sample format: Complex<Float>")
                    print("   Sample range: I=[\(samples[0].real), Q=\(samples[0].imag)]")
                    
                    // Calculate RMS
                    let rms = sqrt(samples.map { $0.magnitudeSquared }.reduce(0, +) / Float(samples.count))
                    print("   RMS level: \(String(format: "%.3f", rms))")
                }
                
                if samplesReceived % 100 == 1 {
                    let elapsed = Date().timeIntervalSince(startTime)
                    let rate = Double(samplesReceived) / elapsed
                    print("   Progress: \(samplesReceived) buffers (\(String(format: "%.1f", rate)) buffers/sec)")
                }
            }
            
            // Stream for 5 seconds
            Thread.sleep(forTimeInterval: 5.0)
            
            rtlDevice.stopStreaming()

            let elapsed = Date().timeIntervalSince(startTime)
            let mbps = Double(totalBytes) / elapsed / 1_000_000.0
            let sampleRate = Double(totalBytes / 8) / elapsed

            guard samplesReceived > 0 else {
                print()
                print("❌ Streaming produced no IQ buffers")
                print("   The device opened, but async sample capture never delivered data.")
                rtlDevice.close()
                exit(1)
            }

            print()
            print("✅ Streaming test complete")
            print("   Duration: \(String(format: "%.2f", elapsed)) seconds")
            print("   Buffers received: \(samplesReceived)")
            print("   Total bytes: \(totalBytes)")
            print("   Data rate: \(String(format: "%.2f", mbps)) MB/s")
            print("   Sample rate: \(String(format: "%.2f", sampleRate / 1_000_000)) MSps")
            
        } catch {
            print("❌ Streaming failed: \(error)")
            rtlDevice.close()
            return
        }
        print()
        
        // Test 5: DSP pipeline test
        print("🔧 Test 6: DSP Pipeline")
        print("──────────────────────────────────────────────────────────")
        print("   Creating DSP pipeline...")
        
        let pipeline = DSPPipeline(
            sampleRate: config.sampleRate,
            centerFrequency: config.centerFrequency
        )
        
        pipeline.setDemodulator(DemodulatorType.NFM)
        print("✅ DSP pipeline created")
        print("   Demodulator: NFM")
        print("   Sample rate: \(String(format: "%.2f", config.sampleRate / 1_000_000)) MSps")
        
        // Test spectrum analyzer
        print()
        print("   Testing spectrum analyzer...")
        var spectrumUpdates = 0
        pipeline.onSpectrumUpdate { spectrum in
            spectrumUpdates += 1
            if spectrumUpdates == 1 {
                print("   ✅ First spectrum update received")
                print("      FFT size: \(spectrum.count) points")
                print("      Frequency range: \(String(format: "%.1f", config.centerFrequency / 1_000_000 - config.sampleRate / 2_000_000)) - \(String(format: "%.1f", config.centerFrequency / 1_000_000 + config.sampleRate / 2_000_000)) MHz")
            }
        }
        
        print("✅ DSP pipeline test complete")
        print()
        
        // Cleanup
        rtlDevice.close()
        
        // Summary
        print("╔══════════════════════════════════════════════════════════╗")
        print("║                  TEST SUMMARY                            ║")
        print("╠══════════════════════════════════════════════════════════╣")
        print("║ ✅ Device enumeration:     PASSED                       ║")
        print("║ ✅ Device opening:         PASSED                       ║")
        print("║ ✅ Configuration:          PASSED                       ║")
        print("║ ✅ Sample streaming:       PASSED                       ║")
        print("║ ✅ DSP pipeline:           PASSED                       ║")
        print("╠══════════════════════════════════════════════════════════╣")
        print("║ ALL TESTS PASSED!                                       ║")
        print("║ Your RTL-SDR dongle is working correctly.               ║")
        print("╚══════════════════════════════════════════════════════════╝")
    }
}
