//
// DSTARDecoder.swift
// NeuralSDR2
//
// D-STAR Digital Decoder
// GMSK (BT=0.5) at 4800 bps
//

import Foundation
import Accelerate

public struct DSTARHeader {
    public var mycall1: String
    public var mycall2: String
    public var yourcall: String
    public var rpt1: String
    public var rpt2: String
    public var flag: UInt8

    public init(mycall1: String = "", mycall2: String = "", yourcall: String = "",
                rpt1: String = "", rpt2: String = "", flag: UInt8 = 0) {
        self.mycall1 = mycall1
        self.mycall2 = mycall2
        self.yourcall = yourcall
        self.rpt1 = rpt1
        self.rpt2 = rpt2
        self.flag = flag
    }
}

public class DSTARDecoder: DSPBlock {
    public var name: String = "D-STAR Decoder"
    public var sampleRate: Double
    public var inputChannels = 1
    public var outputChannels = 1

    public var onHeader: ((DSTARHeader) -> Void)?
    public var onVoiceFrame: ((Data) -> Void)?
    public var onDataFrame: ((Data) -> Void)?

    private let bitRate: Double = 4800.0
    private static let syncPattern: UInt32 = 0x555575F5
    private static let syncPatternLength: Int = 32

    private var prevPhase: Float = 0.0
    private var samplesPerBit: Double
    private var bitPhase: Double = 0.0
    private var prevBitSample: Float = 0.0
    private var midBitSample: Float = 0.0
    private var sampleIndex: Int = 0

    private var bitBuffer: [Int] = []
    private var gaussianFiltered: [Float] = []
    private var prevDiscriminator: Float = 0.0

    private var headerDetected: Bool = false
    private var collectingFrame: Bool = false
    private var frameBits: [Int] = []
    private var frameBitCount: Int = 0

    private let headerBitLength: Int = 384
    private let voiceDataBitLength: Int = 360
    private let slowDataBitLength: Int = 240

    private var gaussianCoeffs: [Float] = []
    private var gaussianState: [Float] = []

    private var monitorFilter: FIRFilter?

    public init(sampleRate: Double = 64000) {
        self.sampleRate = sampleRate
        self.samplesPerBit = sampleRate / bitRate
        setupGaussianFilter()
        setupMonitorFilter()
    }

    private func setupGaussianFilter() {
        let bt: Float = 0.5
        let span = 4
        let samplesPerSymbol = Int(samplesPerBit)
        let numTaps = span * samplesPerSymbol + 1

        gaussianCoeffs = [Float](repeating: 0, count: numTaps)
        let sigma = sqrt(log(2.0)) / (2.0 * Float.pi) * bt
        let center = Float(numTaps - 1) / 2.0
        var sum: Float = 0

        for i in 0..<numTaps {
            let t = (Float(i) - center) / Float(samplesPerBit)
            let arg = Float(-0.5) * (t / sigma) * (t / sigma)
            gaussianCoeffs[i] = exp(arg)
            sum += gaussianCoeffs[i]
        }

        for i in 0..<numTaps {
            gaussianCoeffs[i] /= sum
        }

        gaussianState = [Float](repeating: 0, count: numTaps)
    }

    private func setupMonitorFilter() {
        let coeffs = DSPFilterDesign.lowpassFIR(
            cutoff: 3500,
            sampleRate: sampleRate,
            transitionWidth: 1500,
            attenuation: 40
        )
        if !coeffs.isEmpty {
            monitorFilter = FIRFilter(name: "D-STAR Monitor", coefficients: coeffs, sampleRate: sampleRate)
        }
    }

    public func process(_ input: UnsafePointer<ComplexFloat>, _ output: UnsafeMutablePointer<ComplexFloat>, count: Int) {
        for i in 0..<count {
            let angle = atan2(input[i].imag, input[i].real)
            var delta = angle - prevPhase
            if delta > Float.pi { delta -= 2.0 * Float.pi }
            else if delta < -Float.pi { delta += 2.0 * Float.pi }
            prevPhase = angle

            let freqOffset = delta * Float(sampleRate) / (2.0 * Float.pi)

            let filtered = applyGaussianFilter(freqOffset)

            let audioScale: Float = 1.0 / 3000.0
            output[i] = ComplexFloat(real: filtered * audioScale, imag: 0)

            recoverBit(filtered: filtered)
        }

        if let filter = monitorFilter {
            var filtered = [ComplexFloat](repeating: ComplexFloat(real: 0, imag: 0), count: count)
            filtered.withUnsafeMutableBufferPointer { outPtr in
                filter.process(input, outPtr.baseAddress!, count: count)
            }
            for i in 0..<count {
                output[i] = filtered[i]
            }
        }
    }

    private func applyGaussianFilter(_ sample: Float) -> Float {
        gaussianState.removeFirst(1)
        gaussianState.append(sample)

        var result: Float = 0
        let n = min(gaussianCoeffs.count, gaussianState.count)
        for i in 0..<n {
            result += gaussianState[gaussianState.count - n + i] * gaussianCoeffs[gaussianCoeffs.count - n + i]
        }
        return result
    }

    private func recoverBit(filtered: Float) {
        sampleIndex += 1

        if Double(sampleIndex) - bitPhase >= samplesPerBit {
            let timingError = (filtered - prevBitSample) * midBitSample * 0.05
            bitPhase += Double(timingError)

            let bit: Int = filtered >= 0 ? 1 : 0
            bitBuffer.append(bit)

            if collectingFrame {
                frameBits.append(bit)
                frameBitCount += 1
                checkFrameComplete()
            }

            detectSyncPattern()

            prevBitSample = filtered
            midBitSample = filtered
            bitPhase += samplesPerBit
        } else {
            let midPhase = Double(sampleIndex) - bitPhase - samplesPerBit * 0.5
            if midPhase >= 0 && midPhase < 1.0 {
                midBitSample = filtered
            }
        }
    }

    private func detectSyncPattern() {
        if bitBuffer.count < 32 { return }
        if headerDetected { return }

        let startIdx = bitBuffer.count - 32
        var pattern: UInt32 = 0
        for i in 0..<32 {
            if bitBuffer[startIdx + i] != 0 {
                pattern |= UInt32(1) << UInt32(31 - i)
            }
        }

        let xorVal = pattern ^ DSTARDecoder.syncPattern
        var hamming = 0
        var v = xorVal
        while v != 0 {
            hamming += 1
            v &= v - 1
        }

        if hamming <= 4 {
            headerDetected = true
            bitBuffer.removeFirst(startIdx + 32)

            collectingFrame = true
            frameBits.removeAll(keepingCapacity: true)
            frameBitCount = 0
        }

        if bitBuffer.count > 2048 {
            bitBuffer.removeFirst(1024)
        }
    }

    private func checkFrameComplete() {
        if !headerDetected && frameBitCount >= headerBitLength {
            let headerData = bitsToData(frameBits.prefix(headerBitLength))

            if checkCRC8(headerData) {
                let header = parseHeader(headerData)
                onHeader?(header)
            } else {
                let header = parseHeader(headerData)
                onHeader?(header)
            }

            headerDetected = true
            frameBits.removeFirst(headerBitLength)
            frameBitCount = frameBits.count
        }

        if headerDetected && frameBitCount >= voiceDataBitLength + slowDataBitLength {
            let voiceData = bitsToData(frameBits.prefix(voiceDataBitLength))
            let slowData = bitsToData(Array(frameBits.prefix(voiceDataBitLength + slowDataBitLength)).suffix(slowDataBitLength))

            onVoiceFrame?(voiceData)
            onDataFrame?(slowData)

            frameBits.removeFirst(voiceDataBitLength + slowDataBitLength)
            frameBitCount = frameBits.count

            if frameBitCount > slowDataBitLength * 10 {
                collectingFrame = false
                frameBits.removeAll(keepingCapacity: true)
                frameBitCount = 0
                headerDetected = false
            }
        }

        if frameBitCount > headerBitLength + (voiceDataBitLength + slowDataBitLength) * 50 {
            resetFrameState()
        }
    }

    private func resetFrameState() {
        collectingFrame = false
        headerDetected = false
        frameBits.removeAll(keepingCapacity: true)
        frameBitCount = 0
    }

    private func parseHeader(_ data: Data) -> DSTARHeader {
        guard data.count >= 48 else {
            return DSTARHeader()
        }

        let mycall1 = extractCallsign(data, offset: 3, length: 8)
        let mycall2 = extractCallsign(data, offset: 11, length: 4)
        let yourcall = extractCallsign(data, offset: 19, length: 8)
        let rpt1 = extractCallsign(data, offset: 27, length: 8)
        let rpt2 = extractCallsign(data, offset: 35, length: 8)

        let flag: UInt8 = data.count > 43 ? data[43] : 0

        return DSTARHeader(
            mycall1: mycall1,
            mycall2: mycall2,
            yourcall: yourcall,
            rpt1: rpt1,
            rpt2: rpt2,
            flag: flag
        )
    }

    private func extractCallsign(_ data: Data, offset: Int, length: Int) -> String {
        guard offset + length <= data.count else { return "" }
        var callsign = ""
        for i in 0..<length {
            let byte = data[offset + i]
            if byte >= 0x20 && byte < 0x7F {
                let char = Character(UnicodeScalar(byte))
                if char != " " || !callsign.isEmpty {
                    callsign.append(char)
                }
            }
        }
        return callsign.trimmingCharacters(in: CharacterSet(charactersIn: " "))
    }

    private func checkCRC8(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }

        let poly: UInt8 = 0x07
        var crc: UInt8 = 0

        for byte in data.dropLast(1) {
            crc ^= byte
            for _ in 0..<8 {
                if crc & 0x80 != 0 {
                    crc = (crc << 1) ^ poly
                } else {
                    crc <<= 1
                }
            }
        }

        return crc == data[data.count - 1]
    }

    private func bitsToData(_ bits: ArraySlice<Int>) -> Data {
        var data = Data()
        var byte: UInt8 = 0
        var bitIdx = 0

        for bit in bits {
            byte <<= 1
            if bit != 0 { byte |= 1 }
            bitIdx += 1
            if bitIdx == 8 {
                data.append(byte)
                byte = 0
                bitIdx = 0
            }
        }

        if bitIdx > 0 {
            byte <<= UInt8(8 - bitIdx)
            data.append(byte)
        }

        return data
    }

    public func reset() {
        prevPhase = 0
        bitPhase = 0
        sampleIndex = 0
        prevBitSample = 0
        midBitSample = 0
        bitBuffer.removeAll(keepingCapacity: true)
        gaussianState = [Float](repeating: 0, count: gaussianCoeffs.count)
        headerDetected = false
        collectingFrame = false
        frameBits.removeAll(keepingCapacity: true)
        frameBitCount = 0
        monitorFilter?.reset()
    }

    public func configure(params: [String: Any]) {
        if let sr = params["sampleRate"] as? Double {
            sampleRate = sr
            samplesPerBit = sr / bitRate
            setupGaussianFilter()
            setupMonitorFilter()
        }
    }
}
