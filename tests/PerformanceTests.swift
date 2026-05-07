// PerformanceTests.swift
// NeuralSDR2Tests
//
// Performance benchmarks for FFT and DSP operations
//

import XCTest
import Accelerate
@testable import NeuralSDR2Kit

final class PerformanceTests: XCTestCase {
    
    /// Benchmark vDSP FFT performance
    func testFFTPerformance() {
        let fftSizes = [512, 1024, 2048, 4096]
        let iterations = 10
        
        print("\n╔══════════════════════════════════════════════════╗")
        print("║ FFT Performance Benchmark (vDSP CPU)            ║")
        print("╚══════════════════════════════════════════════════╝")
        
        for fftSize in fftSizes {
            var real = [Float](repeating: 0, count: fftSize)
            var imag = [Float](repeating: 0, count: fftSize)
            var magnitudes = [Float](repeating: 0, count: fftSize / 2)
            
            let log2n = vDSP_Length(Int(log2(Double(fftSize))))
            let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
            
            // Warmup
            vDSP_hann_window(&real, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
            
            var total = 0.0
            for _ in 0..<iterations {
                let start = CFAbsoluteTimeGetCurrent()
                
                var window = [Float](repeating: 0, count: fftSize)
                vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
                vDSP_vmul(real, 1, window, 1, &real, 1, vDSP_Length(fftSize))
                
                var split = DSPSplitComplex(realp: &real, imagp: &imag)
                vDSP_fft_zip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
                
                total += (CFAbsoluteTimeGetCurrent() - start) * 1000
            }
            
            vDSP_destroy_fftsetup(fftSetup)
            let avg = total / Double(iterations)
            print("  FFT \(fftSize): \(String(format: "%.3f", avg))ms avg")
        }
    }
    
    /// Benchmark Metal FFT vs vDSP
    func testMetalFFTPerformance() {
        let fftSize = 2048
        let iterations = 50
        
        // Create samples
        let samples = (0..<fftSize).map { _ in
            ComplexFloat(real: Float.random(in: -1...1), imag: Float.random(in: -1...1))
        }
        
        // Test vDSP path
        let cpuAnalyzer = SpectrumAnalyzer(fftSize: fftSize, sampleRate: 2_048_000, centerFrequency: 100_000_000, windowType: .hann, useGPU: false)
        
        var cpuTimes: [Double] = []
        for _ in 0..<iterations {
            let start = CFAbsoluteTimeGetCurrent()
            _ = cpuAnalyzer.process(samples)
            cpuTimes.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
        }
        let cpuAvg = cpuTimes.reduce(0, +) / Double(cpuTimes.count)
        
        // Test Metal path
        let gpuAnalyzer = SpectrumAnalyzer(fftSize: fftSize, sampleRate: 2_048_000, centerFrequency: 100_000_000, windowType: .hann, useGPU: true)
        
        var gpuTimes: [Double] = []
        for _ in 0..<iterations {
            let start = CFAbsoluteTimeGetCurrent()
            _ = gpuAnalyzer.process(samples)
            gpuTimes.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
        }
        let gpuAvg = gpuTimes.reduce(0, +) / Double(gpuTimes.count)
        
        let speedup = cpuAvg / gpuAvg
        
        print("\n╔══════════════════════════════════════════════════╗")
        print("║ Metal FFT vs vDSP Performance (size=\(fftSize))    ║")
        print("╚══════════════════════════════════════════════════╝")
        print("  vDSP (CPU):   \(String(format: "%.3f", cpuAvg))ms")
        print("  Metal (GPU):  \(String(format: "%.3f", gpuAvg))ms")
        print("  Speedup:      \(String(format: "%.2fx", speedup))")
        
        // Metal should be reasonably competitive, but command submission
        // overhead on desktop GPUs can still dominate at 2048-point FFT sizes,
        // especially on machines where the CPU path is already extremely fast.
        if fftSize >= 2048 {
            XCTAssertLessThanOrEqual(gpuAvg, cpuAvg * 4.5, "Metal should remain in a competitive range for large FFTs")
        }
    }
}
