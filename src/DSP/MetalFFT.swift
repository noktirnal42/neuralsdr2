//
// MetalFFT.swift
// NeuralSDR2
//
// GPU-accelerated FFT using Metal compute shaders (Stockham FFT)
//

import Foundation
import Metal
import Accelerate

public class MetalFFT {
    private let fftSize: Int
    private let log2n: Int
    private var sampleRate: Double
    private var centerFrequency: Double
    private var window: [Float]

    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var fftPipeline: MTLComputePipelineState?
    private var windowPipeline: MTLComputePipelineState?
    private var magnitudePipeline: MTLComputePipelineState?
    private var dbPipeline: MTLComputePipelineState?

    private var inputBuffer: MTLBuffer?
    private var pingBuffer: MTLBuffer?
    private var pongBuffer: MTLBuffer?
    private var windowBuffer: MTLBuffer?
    private var outputBuffer: MTLBuffer?
    private var stageBuffer: MTLBuffer?
    private var sizeBuffer: MTLBuffer?

    private let threadgroupSize: MTLSize
    private var available = false

    private var cpuFallback: SpectrumAnalyzer?

    public init(fftSize: Int, sampleRate: Double, centerFrequency: Double) {
        self.fftSize = fftSize
        self.sampleRate = sampleRate
        self.centerFrequency = centerFrequency
        self.log2n = Int(log2(Double(fftSize)))
        self.window = MetalFFT.createHannWindow(size: fftSize)
        self.threadgroupSize = MTLSize(width: 64, height: 1, depth: 1)
        self.cpuFallback = SpectrumAnalyzer(
            fftSize: fftSize,
            sampleRate: sampleRate,
            centerFrequency: centerFrequency,
            windowType: .hann,
            useGPU: false
        )

        guard fftSize == 512 || fftSize == 1024 || fftSize == 2048 || fftSize == 4096 else {
            return
        }

        setupMetal()
    }

    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            cpuFallback = SpectrumAnalyzer(fftSize: fftSize, sampleRate: sampleRate, centerFrequency: centerFrequency)
            return
        }
        self.device = device

        guard let commandQueue = device.makeCommandQueue() else {
            cpuFallback = SpectrumAnalyzer(fftSize: fftSize, sampleRate: sampleRate, centerFrequency: centerFrequency)
            return
        }
        self.commandQueue = commandQueue

        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)

            guard let fftFunc = library.makeFunction(name: "fft_radix2"),
                  let windowFunc = library.makeFunction(name: "apply_window"),
                  let magFunc = library.makeFunction(name: "magnitude_squared"),
                  let dbFunc = library.makeFunction(name: "convert_to_db") else {
                cpuFallback = SpectrumAnalyzer(fftSize: fftSize, sampleRate: sampleRate, centerFrequency: centerFrequency)
                return
            }

            fftPipeline = try device.makeComputePipelineState(function: fftFunc)
            windowPipeline = try device.makeComputePipelineState(function: windowFunc)
            magnitudePipeline = try device.makeComputePipelineState(function: magFunc)
            dbPipeline = try device.makeComputePipelineState(function: dbFunc)
        } catch {
            cpuFallback = SpectrumAnalyzer(fftSize: fftSize, sampleRate: sampleRate, centerFrequency: centerFrequency)
            return
        }

        let bufferSize = fftSize * MemoryLayout<Float>.size * 2
        let halfBufferSize = (fftSize / 2) * MemoryLayout<Float>.size

        inputBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)
        pingBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)
        pongBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)
        outputBuffer = device.makeBuffer(length: halfBufferSize, options: .storageModeShared)

        windowBuffer = device.makeBuffer(bytes: window,
                                          length: fftSize * MemoryLayout<Float>.size,
                                          options: .storageModeShared)

        stageBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.size, options: .storageModeShared)
        sizeBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.size, options: .storageModeShared)

        guard inputBuffer != nil, pingBuffer != nil, pongBuffer != nil,
              outputBuffer != nil, windowBuffer != nil,
              stageBuffer != nil, sizeBuffer != nil,
              fftPipeline != nil, windowPipeline != nil,
              magnitudePipeline != nil, dbPipeline != nil else {
            cpuFallback = SpectrumAnalyzer(fftSize: fftSize, sampleRate: sampleRate, centerFrequency: centerFrequency)
            return
        }

        var n: UInt32 = UInt32(fftSize)
        memcpy(sizeBuffer!.contents(), &n, MemoryLayout<UInt32>.size)

        available = true
    }

    public func process(samples: [ComplexFloat]) -> [Float] {
        // Keep the live display path correct and centered for complex IQ input.
        // The Metal kernels still implement an older half-spectrum path, so we
        // delegate to the CPU analyzer until a full fft-shifted GPU path lands.
        if let cpuFallback {
            return cpuFallback.process(samples)
        }

        guard available else {
            return [Float](repeating: -120, count: fftSize)
        }

        let count = min(samples.count, fftSize)

        var interleaved = [Float](repeating: 0, count: fftSize * 2)
        for i in 0..<count {
            interleaved[i * 2] = samples[i].real
            interleaved[i * 2 + 1] = samples[i].imag
        }

        memcpy(inputBuffer!.contents(), interleaved, fftSize * MemoryLayout<Float>.size * 2)

        guard let commandBuffer = commandQueue?.makeCommandBuffer() else {
            return [Float](repeating: -120, count: fftSize)
        }

        let threadgroupCount = MTLSize(width: (fftSize + 63) / 64, height: 1, depth: 1)
        let halfThreadgroupCount = MTLSize(width: (fftSize / 2 + 63) / 64, height: 1, depth: 1)

        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setBuffer(inputBuffer, offset: 0, index: 0)
            encoder.setBuffer(windowBuffer, offset: 0, index: 1)
            encoder.setBuffer(pingBuffer, offset: 0, index: 2)
            encoder.setComputePipelineState(windowPipeline!)
            encoder.dispatchThreads(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
            encoder.endEncoding()
        }

        for stage in 0..<log2n {
            var stageVal: UInt32 = UInt32(stage)
            memcpy(stageBuffer!.contents(), &stageVal, MemoryLayout<UInt32>.size)

            if let encoder = commandBuffer.makeComputeCommandEncoder() {
                if stage % 2 == 0 {
                    encoder.setBuffer(pingBuffer, offset: 0, index: 0)
                    encoder.setBuffer(pongBuffer, offset: 0, index: 1)
                } else {
                    encoder.setBuffer(pongBuffer, offset: 0, index: 0)
                    encoder.setBuffer(pingBuffer, offset: 0, index: 1)
                }
                encoder.setBuffer(stageBuffer, offset: 0, index: 2)
                encoder.setBuffer(sizeBuffer, offset: 0, index: 3)
                encoder.setComputePipelineState(fftPipeline!)
                encoder.dispatchThreads(halfThreadgroupCount, threadsPerThreadgroup: threadgroupSize)
                encoder.endEncoding()
            }
        }

        let fftResultBuffer = (log2n % 2 == 0) ? pingBuffer! : pongBuffer!

        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setBuffer(fftResultBuffer, offset: 0, index: 0)
            encoder.setBuffer(outputBuffer, offset: 0, index: 1)
            encoder.setBuffer(sizeBuffer, offset: 0, index: 2)
            encoder.setComputePipelineState(magnitudePipeline!)
            encoder.dispatchThreads(halfThreadgroupCount, threadsPerThreadgroup: threadgroupSize)
            encoder.endEncoding()
        }

        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setBuffer(outputBuffer, offset: 0, index: 0)
            encoder.setBuffer(outputBuffer, offset: 0, index: 1)
            encoder.setBuffer(sizeBuffer, offset: 0, index: 2)
            encoder.setComputePipelineState(dbPipeline!)
            let quarterThreadgroupCount = MTLSize(width: (fftSize / 2 + 63) / 64, height: 1, depth: 1)
            encoder.dispatchThreads(quarterThreadgroupCount, threadsPerThreadgroup: threadgroupSize)
            encoder.endEncoding()
        }

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let halfSize = fftSize / 2
        var result = [Float](repeating: 0, count: halfSize)
        memcpy(&result, outputBuffer!.contents(), halfSize * MemoryLayout<Float>.size)
        return result
    }

    public func updateSampleRate(_ rate: Double) {
        sampleRate = rate
        cpuFallback?.updateSampleRate(rate)
    }

    public func updateCenterFrequency(_ freq: Double) {
        centerFrequency = freq
        cpuFallback?.updateCenterFrequency(freq)
    }

    private static func createHannWindow(size: Int) -> [Float] {
        var window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        return window
    }

    private static let shaderSource: String = """
    #include <metal_stdlib>
    using namespace metal;

    kernel void fft_radix2(
        device float2* input [[buffer(0)]],
        device float2* output [[buffer(1)]],
        constant uint& stage [[buffer(2)]],
        constant uint& N [[buffer(3)]],
        uint id [[thread_position_in_grid]]
    ) {
        if (id >= N / 2) return;

        uint halfSize = 1u << stage;
        uint groupSize = halfSize << 1;
        uint group = id / halfSize;
        uint pos = id % halfSize;

        uint i0 = group * groupSize + pos;
        uint i1 = i0 + halfSize;

        float2 x0 = input[i0];
        float2 x1 = input[i1];

        float angle = -2.0 * M_PI_F * float(pos) / float(groupSize);
        float cs = cos(angle);
        float sn = sin(angle);
        float2 twiddle = float2(cs, sn);

        float2 t = float2(
            twiddle.x * x1.x - twiddle.y * x1.y,
            twiddle.x * x1.y + twiddle.y * x1.x
        );

        output[i0] = x0 + t;
        output[i1] = x0 - t;
    }

    kernel void apply_window(
        device float2* input [[buffer(0)]],
        device float* window [[buffer(1)]],
        device float2* output [[buffer(2)]],
        uint id [[thread_position_in_grid]]
    ) {
        output[id] = input[id] * window[id];
    }

    kernel void magnitude_squared(
        device float2* input [[buffer(0)]],
        device float* output [[buffer(1)]],
        constant uint& N [[buffer(2)]],
        uint id [[thread_position_in_grid]]
    ) {
        if (id >= N / 2) return;
        float2 v = input[id];
        output[id] = v.x * v.x + v.y * v.y;
    }

    kernel void convert_to_db(
        device float* input [[buffer(0)]],
        device float* output [[buffer(1)]],
        constant uint& N [[buffer(2)]],
        uint id [[thread_position_in_grid]]
    ) {
        float normalization = max(float(N) * float(N), 1.0);
        float x = max(input[id] / normalization, 1e-12);
        float db = 10.0 * log2(x) / log2(10.0);
        output[id] = clamp(db, -140.0, 10.0);
    }
    """
}
