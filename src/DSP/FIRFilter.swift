//
//  FIRFilter.swift
//  NeuralSDR2
//
//  FIR Filter implementation using vDSP
//  IIR Filter using vDSP biquad cascade
//

import Foundation
import Accelerate

/// FIR Filter using vDSP for acceleration with proper state preservation
public class FIRFilter: DSPBlock {
    public var name: String
    public var sampleRate: Double
    public var inputChannels = 1
    public var outputChannels = 1

    private var coefficients: [Float]
    private var reversedCoefficients: [Float]
    private var delayLineReal: [Float]
    private var delayLineImag: [Float]
    private var tapCount: Int

    // Pre-allocated buffers to avoid heap allocations per call
    private var extReal: [Float] = []
    private var extImag: [Float] = []
    private var outputReal: [Float] = []
    private var outputImag: [Float] = []

    public init(name: String = "FIR Filter", coefficients: [Float], sampleRate: Double = 2_048_000) {
        self.name = name
        self.coefficients = coefficients
        self.sampleRate = sampleRate
        self.tapCount = coefficients.count
        self.reversedCoefficients = coefficients.reversed()
        self.delayLineReal = [Float](repeating: 0, count: max(tapCount - 1, 1))
        self.delayLineImag = [Float](repeating: 0, count: max(tapCount - 1, 1))
    }

    /// Ensure all internal buffers are large enough for the given count (grow-only)
    public func ensureCapacity(_ count: Int) {
        let stateLen = tapCount - 1
        let extLen = count + stateLen
        if extReal.count < extLen {
            extReal = [Float](repeating: 0, count: extLen)
        }
        if extImag.count < extLen {
            extImag = [Float](repeating: 0, count: extLen)
        }
        if outputReal.count < count {
            outputReal = [Float](repeating: 0, count: count)
        }
        if outputImag.count < count {
            outputImag = [Float](repeating: 0, count: count)
        }
    }

    public func process(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        guard count > 0, tapCount > 0 else { return }

        let stateLen = tapCount - 1
        let extLen = count + stateLen

        ensureCapacity(count)

        // Clear extended buffers
        vDSP_vclr(&extReal, 1, vDSP_Length(extLen))
        vDSP_vclr(&extImag, 1, vDSP_Length(extLen))

        // Copy delay line state into beginning of extended buffers
        if stateLen > 0 {
            extReal.withUnsafeMutableBufferPointer { extBuf in
                extBuf.baseAddress!.initialize(from: delayLineReal, count: stateLen)
            }
            extImag.withUnsafeMutableBufferPointer { extBuf in
                extBuf.baseAddress!.initialize(from: delayLineImag, count: stateLen)
            }
        }

        // Deinterleave input ComplexFloat into extReal[stateLen..] / extImag[stateLen..] using vDSP_ctoz
        input.withMemoryRebound(to: DSPComplex.self, capacity: count) { complexPtr in
            extReal.withUnsafeMutableBufferPointer { realBuf in
                extImag.withUnsafeMutableBufferPointer { imagBuf in
                    var split = DSPSplitComplex(realp: realBuf.baseAddress! + stateLen, imagp: imagBuf.baseAddress! + stateLen)
                    vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(count))
                }
            }
        }

        // FIR convolution (vDSP_conv computes correlation, so we use reversed coefficients)
        vDSP_conv(extReal, 1, reversedCoefficients, 1, &outputReal, 1, vDSP_Length(count), vDSP_Length(tapCount))
        vDSP_conv(extImag, 1, reversedCoefficients, 1, &outputImag, 1, vDSP_Length(count), vDSP_Length(tapCount))

        // Reinterleave outputReal/outputImag into ComplexFloat output using vDSP_ztoc
        output.withMemoryRebound(to: DSPComplex.self, capacity: count) { complexPtr in
            outputReal.withUnsafeMutableBufferPointer { realBuf in
                outputImag.withUnsafeMutableBufferPointer { imagBuf in
                    var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                    vDSP_ztoc(&split, 1, complexPtr, 2, vDSP_Length(count))
                }
            }
        }

        // Update delay line with last stateLen samples
        if stateLen > 0 {
            input.withMemoryRebound(to: Float.self, capacity: count * 2) { floatPtr in
                for i in 0..<stateLen {
                    let srcIdx = (count - stateLen + i) * 2
                    delayLineReal[i] = floatPtr[srcIdx]
                    delayLineImag[i] = floatPtr[srcIdx + 1]
                }
            }
        }
    }

    public func reset() {
        let stateLen = max(tapCount - 1, 1)
        delayLineReal = [Float](repeating: 0, count: stateLen)
        delayLineImag = [Float](repeating: 0, count: stateLen)
    }

    public func configure(params: [String: Any]) {
        if let newCoeffs = params["coefficients"] as? [Float] {
            setCoefficients(newCoeffs)
        }
        if let newSampleRate = params["sampleRate"] as? Double {
            sampleRate = newSampleRate
        }
    }

    public func setCoefficients(_ newCoeffs: [Float]) {
        coefficients = newCoeffs
        tapCount = coefficients.count
        reversedCoefficients = coefficients.reversed()
        reset()
    }

    public static func lowpass(cutoff: Double, sampleRate: Double, transitionWidth: Double = 0.1, attenuation: Double = 60) -> FIRFilter {
        let coeffs = DSPFilterDesign.lowpassFIR(cutoff: cutoff, sampleRate: sampleRate, transitionWidth: transitionWidth, attenuation: attenuation)
        return FIRFilter(name: "Lowpass \(cutoff)Hz", coefficients: coeffs, sampleRate: sampleRate)
    }

    public static func bandpass(lowCutoff: Double, highCutoff: Double, sampleRate: Double, transitionWidth: Double = 0.1, attenuation: Double = 60) -> FIRFilter {
        let bandwidth = (highCutoff - lowCutoff) / 2.0
        let centerFreq = (lowCutoff + highCutoff) / 2.0

        var lpCoeffs = DSPFilterDesign.lowpassFIR(cutoff: bandwidth, sampleRate: sampleRate, transitionWidth: transitionWidth, attenuation: attenuation)

        let center = Float(lpCoeffs.count - 1) / 2.0
        let twoPiFcOverFs = Float(2.0 * Double.pi * centerFreq / sampleRate)

        for i in 0..<lpCoeffs.count {
            let n = Float(i) - center
            lpCoeffs[i] *= 2.0 * cos(twoPiFcOverFs * n)
        }

        return FIRFilter(name: "Bandpass \(lowCutoff)-\(highCutoff)Hz", coefficients: lpCoeffs, sampleRate: sampleRate)
    }
}

// MARK: - IIR Filter (Biquad Cascade)

/// IIR Filter using vDSP biquad processing
public class IIRFilter: DSPBlock {
    public var name: String
    public var sampleRate: Double
    public var inputChannels = 1
    public var outputChannels = 1

    private var numSections: Int

    /// vDSP biquad setup object (created from Double coefficients)
    private var biquadSetup: OpaquePointer?

    /// State for real part: (numSections * 2) delay values
    private var stateReal: [Float]
    /// State for imaginary part
    private var stateImag: [Float]

    // Pre-allocated buffers to avoid heap allocations per call
    private var realPart: [Float] = []
    private var imagPart: [Float] = []
    private var outputReal: [Float] = []
    private var outputImag: [Float] = []

    /// Double-precision coefficients for vDSP_biquad_CreateSetup
    /// Each section: 5 doubles [b0, b1, b2, a1, a2] standard feedback coefficients (vDSP handles sign internally)
    private var flatCoeffsD: [Double]

    public enum FilterType: Int {
        case lowpass = 0
        case highpass = 1
    }

    public init(name: String = "IIR Filter", cutoff: Double, sampleRate: Double, type: FilterType = .lowpass) {
        self.name = name
        self.sampleRate = sampleRate

        // Design 2nd-order Butterworth (single biquad section)
        let nyquist = sampleRate / 2.0
        let normalizedCutoff = cutoff / nyquist

        // Butterworth 2nd order coefficients (Double for vDSP_biquad_CreateSetup)
        let wc = tan(Double.pi * normalizedCutoff)
        let wc2 = wc * wc
        let k = sqrt(2.0) * wc
        let norm = 1.0 + k + wc2

        let b0: Double
        let b1: Double
        let b2: Double
        let a1: Double
        let a2: Double

        switch type {
        case .lowpass:
            b0 = wc2 / norm
            b1 = 2.0 * wc2 / norm
            b2 = wc2 / norm
            a1 = 2.0 * (wc2 - 1.0) / norm
            a2 = (1.0 - k + wc2) / norm
        case .highpass:
            b0 = 1.0 / norm
            b1 = -2.0 / norm
            b2 = 1.0 / norm
            a1 = 2.0 * (wc2 - 1.0) / norm
            a2 = (1.0 - k + wc2) / norm
        }

        self.numSections = 1
        self.flatCoeffsD = [b0, b1, b2, a1, a2]

        // vDSP_biquad needs 2 * numSections delay elements for state
        self.stateReal = [Float](repeating: 0, count: 2 * numSections)
        self.stateImag = [Float](repeating: 0, count: 2 * numSections)

        // Create vDSP biquad setup
        self.biquadSetup = flatCoeffsD.withUnsafeBufferPointer { coeffBuf in
            vDSP_biquad_CreateSetup(coeffBuf.baseAddress!, vDSP_Length(numSections))
        }
    }

    deinit {
        if let setup = biquadSetup {
            vDSP_biquad_DestroySetup(setup)
        }
    }

    public func process(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        guard count > 0, let setup = biquadSetup else { return }

        // Grow-only pre-allocation
        if realPart.count < count {
            realPart = [Float](repeating: 0, count: count)
            imagPart = [Float](repeating: 0, count: count)
            outputReal = [Float](repeating: 0, count: count)
            outputImag = [Float](repeating: 0, count: count)
        }

        // Deinterleave input using vDSP_ctoz
        input.withMemoryRebound(to: DSPComplex.self, capacity: count) { complexPtr in
            realPart.withUnsafeMutableBufferPointer { realBuf in
                imagPart.withUnsafeMutableBufferPointer { imagBuf in
                    var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                    vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(count))
                }
            }
        }

        // Process real part through biquad
        stateReal.withUnsafeMutableBufferPointer { stateBuf in
            realPart.withUnsafeBufferPointer { inBuf in
                outputReal.withUnsafeMutableBufferPointer { outBuf in
                    vDSP_biquad(
                        setup,
                        stateBuf.baseAddress!,
                        inBuf.baseAddress!, 1,
                        outBuf.baseAddress!, 1,
                        UInt(count)
                    )
                }
            }
        }

        // Process imaginary part through biquad
        stateImag.withUnsafeMutableBufferPointer { stateBuf in
            imagPart.withUnsafeBufferPointer { inBuf in
                outputImag.withUnsafeMutableBufferPointer { outBuf in
                    vDSP_biquad(
                        setup,
                        stateBuf.baseAddress!,
                        inBuf.baseAddress!, 1,
                        outBuf.baseAddress!, 1,
                        UInt(count)
                    )
                }
            }
        }

        // Reinterleave using vDSP_ztoc
        output.withMemoryRebound(to: DSPComplex.self, capacity: count) { complexPtr in
            outputReal.withUnsafeMutableBufferPointer { realBuf in
                outputImag.withUnsafeMutableBufferPointer { imagBuf in
                    var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                    vDSP_ztoc(&split, 1, complexPtr, 2, vDSP_Length(count))
                }
            }
        }
    }

    public func reset() {
        stateReal = [Float](repeating: 0, count: 2 * numSections)
        stateImag = [Float](repeating: 0, count: 2 * numSections)
    }

    public func configure(params: [String: Any]) {
    }
}
