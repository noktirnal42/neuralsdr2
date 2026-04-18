//
//  DSPBlock.swift
//  NeuralSDR2
//
//  Base class for DSP processing blocks
//  Implements GNU Radio-inspired flowgraph architecture
//

import Foundation
import Accelerate
import simd

/// Complex float using SIMD for performance
public struct ComplexFloat: Sendable {
    public var real: Float
    public var imag: Float
    
    public init(real: Float, imag: Float) {
        self.real = real
        self.imag = imag
    }
    
    /// Magnitude (amplitude)
    public var magnitude: Float {
        return sqrt(real * real + imag * imag)
    }
    
    /// Magnitude squared (faster, no sqrt)
    public var magnitudeSquared: Float {
        return real * real + imag * imag
    }
    
    /// Phase (angle in radians)
    public var phase: Float {
        return atan2(imag, real)
    }
    
    /// Convert from dB to linear
    public static func fromDB(_ db: Float) -> Float {
        return pow(10.0, db / 20.0)
    }
    
    /// Convert to dB
    public var toDB: Float {
        return 20.0 * log10(magnitude + 1e-10)
    }
}

// MARK: - SIMD Operations

extension ComplexFloat {
    /// Add two complex numbers
    public static func + (lhs: ComplexFloat, rhs: ComplexFloat) -> ComplexFloat {
        return ComplexFloat(real: lhs.real + rhs.real, imag: lhs.imag + rhs.imag)
    }
    
    /// Subtract two complex numbers
    public static func - (lhs: ComplexFloat, rhs: ComplexFloat) -> ComplexFloat {
        return ComplexFloat(real: lhs.real - rhs.real, imag: lhs.imag - rhs.imag)
    }
    
    /// Multiply two complex numbers
    public static func * (lhs: ComplexFloat, rhs: ComplexFloat) -> ComplexFloat {
        return ComplexFloat(
            real: lhs.real * rhs.real - lhs.imag * rhs.imag,
            imag: lhs.real * rhs.imag + lhs.imag * rhs.real
        )
    }
    
    /// Divide two complex numbers
    public static func / (lhs: ComplexFloat, rhs: ComplexFloat) -> ComplexFloat {
        let denominator = rhs.real * rhs.real + rhs.imag * rhs.imag
        return ComplexFloat(
            real: (lhs.real * rhs.real + lhs.imag * rhs.imag) / denominator,
            imag: (lhs.imag * rhs.real - lhs.real * rhs.imag) / denominator
        )
    }
    
    /// Multiply by scalar
    public static func * (lhs: ComplexFloat, rhs: Float) -> ComplexFloat {
        return ComplexFloat(real: lhs.real * rhs, imag: lhs.imag * rhs)
    }
    
    /// Conjugate
    public var conjugate: ComplexFloat {
        return ComplexFloat(real: real, imag: -imag)
    }
}

// MARK: - DSP Block Protocol

/// Protocol for all DSP processing blocks
public protocol DSPBlock {
    /// Unique identifier for this block
    var name: String { get }
    
    /// Sample rate the block operates at
    var sampleRate: Double { get set }
    
    /// Number of input channels
    var inputChannels: Int { get }
    
    /// Number of output channels
    var outputChannels: Int { get }
    
    /// Process a buffer of samples
    /// - Parameters:
    ///   - input: Input samples (interleaved if multi-channel)
    ///   - output: Output buffer to fill
    ///   - count: Number of samples to process
    func process(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int)
    
    /// Reset internal state
    func reset()
    
    /// Configure block with new parameters
    func configure(params: [String: Any])
}

// MARK: - Flowgraph

/// Manages connections between DSP blocks
public class Flowgraph {
    private var blocks: [String: DSPBlock] = [:]
    private var connections: [(from: String, to: String)] = []
    private var isRunning = false
    
    public init() {}
    
    /// Add a block to the flowgraph
    public func addBlock(_ block: DSPBlock) {
        blocks[block.name] = block
    }
    
    /// Connect two blocks
    public func connect(from: String, to: String) {
        connections.append((from, to))
    }
    
    /// Start processing
    public func start() {
        isRunning = true
        // Initialize all blocks
        blocks.values.forEach { $0.reset() }
    }
    
    /// Stop processing
    public func stop() {
        isRunning = false
    }
    
    /// Configure all blocks
    public func configure(params: [String: [String: Any]]) {
        for (blockName, blockParams) in params {
            if let block = blocks[blockName] {
                block.configure(params: blockParams)
            }
        }
    }
}

// MARK: - Buffer Pool

/// Manages reusable buffers to reduce allocations
public class BufferPool {
    private var availableBuffers: [[ComplexFloat]] = []
    private let bufferSize: Int
    private let maxBuffers: Int
    
    public init(bufferSize: Int, maxBuffers: Int = 10) {
        self.bufferSize = bufferSize
        self.maxBuffers = maxBuffers
    }
    
    /// Acquire a buffer from the pool
    public func acquire() -> [ComplexFloat] {
        if let buffer = availableBuffers.popLast() {
            return buffer
        }
        return [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: bufferSize)
    }
    
    /// Release a buffer back to the pool
    public func release(_ buffer: [ComplexFloat]) {
        if availableBuffers.count < maxBuffers {
            availableBuffers.append(buffer)
        }
    }
}

// MARK: - Utility Functions

public extension DSPBlock {
    /// Design a low-pass FIR filter using windowed-sinc method
    static func designLowpassFIR(cutoff: Double, sampleRate: Double, transitionWidth: Double, attenuation: Double = 60) -> [Float] {
        let normalizedCutoff = cutoff / (sampleRate / 2.0)
        let numTaps = Int((attenuation - 22) / (22 * transitionWidth / (sampleRate / 2.0)))
        
        guard numTaps > 0 else { return [] }
        
        // Make sure numTaps is odd for symmetric filter
        let taps = numTaps % 2 == 0 ? numTaps + 1 : numTaps
        
        var coefficients = [Float](repeating: 0, count: taps)
        let center = Float(taps - 1) / 2.0
        
        // Apply windowed-sinc
        for i in 0..<taps {
            let n = Float(i) - center
            let wc = Float(2.0 * Double(normalizedCutoff))
            
            if n == 0 {
                coefficients[i] = wc
            } else {
                coefficients[i] = sin(2.0 * .pi * wc * n) / (.pi * n)
            }
            
            // Apply Hamming window
            let window = 0.54 - 0.46 * cos(2.0 * .pi * Float(i) / Float(taps - 1))
            coefficients[i] *= window
        }
        
        // Normalize to unity gain at DC
        let sum = coefficients.reduce(0, +)
        coefficients = coefficients.map { $0 / sum }
        
        return coefficients
    }
}
