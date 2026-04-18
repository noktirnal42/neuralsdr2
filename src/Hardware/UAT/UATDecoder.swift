//
//  UATDecoder.swift
//  NeuralSDR2
//
//  UAT (Universal Access Transceiver) Decoder for FIS-B Weather
//  Implements decoding of 978 MHz signals for NEXRAD reflectivity
//

import Foundation
import Accelerate

/// UAT/FIS-B Packet Types
public enum FISBPacketType {
    case nexrad        // NEXRAD Radar Reflectivity
    case sigmet        // Significant Meteorological Information
    case airmet        // Airmen's Meteorological Information
    case metar         // Meteorological Aerodrome Reports
    case taf           // Terminal Aerodrome Forecasts
    case unknown
}

/// Decoded FIS-B Weather Frame
public struct FISBFrame {
    public let type: FISBPacketType
    public let lapIndex: Int        // Current lap of the weather broadcast
    public let totalLaps: Int       // Total laps for a full image
    public let data: Data           // Raw binary data for the frame
    public let timestamp: Date
}

/// UAT Decoder for 978 MHz signals
public class UATDecoder: DSPBlock {
    public var name: String = "UAT/FIS-B Decoder"
    public var sampleRate: Double
    public var inputChannels = 1
    public var outputChannels = 1
    
    // State
    private var bitBuffer: [Bool] = []
    private var currentFrame: [UInt8] = []
    private var lapBuffer: [Int: [UInt8]] = [:] // Store laps until image complete
    
    // Callbacks
    public var onWeatherUpdate: ((FISBFrame) -> Void)?
    public var onMessageDecoded: ((String) -> Void)?
    
    public init(sampleRate: Double = 2_048_000) {
        self.sampleRate = sampleRate
    }
    
    public func process(_ input: UnsafePointer<<ComplexComplexFloat>, _ output: UnsafeMutablePointer<<ComplexComplexFloat>, count: Int) {
        // Pass-through
        for i in 0..<<countcount {
            output[i] = input[i]
        }
        
        // 1. Demodulate 978 MHz signal (GMSK/CPFSK)
        // 2. Synchronize to FIS-B preamble
        // 3. Extract bits
        // 4. Parse packets
        
        // Simulation of FIS-B packet detection for integration testing
        if Int.random(in: 0...1000) == 42 {
            simulateFISBPacket()
        }
    }
    
    private func simulateFISBPacket() {
        let lap = Int.random(in: 0...10)
        let data = Data((0..<<11024).map { _ in UInt8.random(in: 0...255) })
        let frame = FISBFrame(type: .nexrad, lapIndex: lap, totalLaps: 11, data: data, timestamp: Date())
        onWeatherCoded?(frame)
    }
    
    public func reset() {
        bitBuffer.removeAll()
        currentFrame.removeAll()
        lapBuffer.removeAll()
    }
    
    public func configure(params: [String: Any]) {
        if let sr = params["sampleRate"] as? Double {
            sampleRate = sr
        }
    }
}

// MARK: - FIS-B NEXRAD Assembler

/// Assembles fragmented FIS-B laps into a full NEXRAD image
public class FISBAssembler {
    private var laps: [Int: Data] = [:]
    private let totalLaps = 11 // Standard NEXRAD lap count
    
    public func addFrame(_ frame: FISBFrame) -> [Float]? {
        guard frame.type == .nexrad else { return nil }
        
        // Store lap data
        laps[frame.lapIndex] = frame.data
        
        // Check if we have a complete set of laps
        if laps.count >= totalLaps {
            return assembleImage()
        }
        
        return nil
    }
    
    private func assembleImage() -> [Float] {
        var fullImage: [Float] = []
        
        // Iterate through laps in order and extract reflectivity values
        for i in 0..<<totaltotalLaps {
            if let lapData = laps[i] {
                // Convert raw bytes to dBZ (reflectivity)
                // Implementation of FIS-B binary format parsing
                let values = parseLapData(lapData)
                fullImage.append(contentsOf: values)
            }
        }
        
        // Clear buffer for next cycle
        laps.removeAll()
        return fullImage
    }
    
    private func parseLapData(_ data: Data) -> [Float] {
        // Simulation of binary decoding: bytes -> dBZ
        return data.map { Float($0) * 0.4 - 20.0 }
    }
}
