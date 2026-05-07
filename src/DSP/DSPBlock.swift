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

/// A complex number representation using single-precision floating point.
///
/// `ComplexFloat` stores in-phase (real) and quadrature (imaginary) components
/// of a complex sample. All DSP blocks in NeuralSDR2Kit operate on arrays of
/// ``ComplexFloat`` values representing IQ sample streams.
///
/// ```swift
/// let sample = ComplexFloat(real: 0.707, imag: 0.707)
/// let magnitude = sample.magnitude  // 1.0
/// let phase = sample.phase          // π/4
/// ```
public struct ComplexFloat: Sendable {
    /// The in-phase (I) component of the complex sample.
    public var real: Float
    /// The quadrature (Q) component of the complex sample.
    public var imag: Float

    /// Creates a complex number with the given real and imaginary parts.
    /// - Parameters:
    ///   - real: The in-phase component.
    ///   - imag: The quadrature component.
    public init(real: Float, imag: Float) {
        self.real = real
        self.imag = imag
    }

    /// The magnitude (amplitude) of the complex number, computed as √(real² + imag²).
    public var magnitude: Float {
        return sqrt(real * real + imag * imag)
    }
    
    /// The magnitude squared, computed as real² + imag². Faster than ``magnitude`` when you only need relative values.
    public var magnitudeSquared: Float {
        return real * real + imag * imag
    }
    
    /// The phase (angle in radians) of the complex number, in the range [-π, π].
    public var phase: Float {
        return atan2(imag, real)
    }
    
    /// Converts a decibel value to linear amplitude (10^(dB/20)).
    /// - Parameter db: The value in decibels.
    /// - Returns: The linear amplitude.
    public static func fromDB(_ db: Float) -> Float {
        return pow(10.0, db / 20.0)
    }
    
    /// The magnitude in decibels, computed as 20·log₁₀(magnitude).
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

/// A protocol that defines the interface for all DSP processing blocks.
///
/// Conforming types represent a single processing stage in a signal flowgraph.
/// Each block has a name, sample rate, and a ``process(_:_:count:)`` method
/// that transforms input samples into output samples.
///
/// Blocks are connected via ``Flowgraph`` to form processing pipelines.
public protocol DSPBlock {
    /// A unique identifier for this block within a ``Flowgraph``.
    var name: String { get }

    /// The sample rate this block operates at, in samples per second.
    var sampleRate: Double { get set }

    /// The number of input channels this block accepts.
    var inputChannels: Int { get }

    /// The number of output channels this block produces.
    var outputChannels: Int { get }

    /// Process a buffer of complex samples.
    ///
    /// - Parameters:
    ///   - input: Pointer to input ``ComplexFloat`` samples.
    ///   - output: Pointer to the output buffer to fill with processed samples.
    ///   - count: The number of samples to process.
    func process(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int)

    /// Reset internal state (delay lines, phase accumulators, etc.).
    func reset()

    /// Configure the block with new parameters at runtime.
    /// - Parameter params: A dictionary of parameter names to values.
    func configure(params: [String: Any])
}

// MARK: - Flowgraph

/// Manages connections between DSP blocks in a GNU Radio-inspired flowgraph.
///
/// Add blocks with ``addBlock(_:)``, connect them with ``connect(from:to:)``,
/// then start the flowgraph to begin processing.
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

/// A reusable buffer pool that reduces heap allocations during DSP processing.
///
/// Acquire buffers with ``acquire()`` and return them with ``release(_:)``.
/// The pool caps the number of cached buffers to ``maxBuffers``.
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

/// Filter design utilities for creating FIR filter coefficients.
///
/// Use ``lowpassFIR(cutoff:sampleRate:transitionWidth:attenuation:)`` to design
/// windowed-sinc lowpass filters with Hamming windowing.
public enum DSPFilterDesign {
    /// Design a low-pass FIR filter using the windowed-sinc method with a Hamming window.
    ///
    /// - Parameters:
    ///   - cutoff: The -3dB cutoff frequency in Hz.
    ///   - sampleRate: The sample rate in Hz.
    ///   - transitionWidth: The transition bandwidth in Hz.
    ///   - attenuation: The stopband attenuation in dB (default 60).
    /// - Returns: An array of FIR filter coefficients normalized to unity DC gain.
    public static func lowpassFIR(cutoff: Double, sampleRate: Double, transitionWidth: Double, attenuation: Double = 60) -> [Float] {
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

/// Backward compatibility alias — delegates to DSPFilterDesign.lowpassFIR
public extension DSPBlock {
    static func designLowpassFIR(cutoff: Double, sampleRate: Double, transitionWidth: Double, attenuation: Double = 60) -> [Float] {
        return DSPFilterDesign.lowpassFIR(cutoff: cutoff, sampleRate: sampleRate, transitionWidth: transitionWidth, attenuation: attenuation)
    }
}
