//
// PerformanceMonitor.swift
// NeuralSDR2
//
// Runtime performance metrics for DSP pipeline profiling
//

import Foundation
import os.log

public class PerformanceMonitor {
    private var fftTimes: [Double] = []
    private var audioBufferLevels: [Int] = []
    private var dspLatencies: [Double] = []
    private var frameTimes: [Double] = []
    private let maxSamples = 300

    private var lastReportTime: CFAbsoluteTime = 0
    private let reportInterval: TimeInterval
    private let reportQueue = DispatchQueue(label: "com.neuralsdr2.perfmon", qos: .utility)

    private let logger = Logger(subsystem: "com.neuralsdr2.app", category: "PerformanceMonitor")

    public init(reportInterval: TimeInterval = 5.0) {
        self.reportInterval = reportInterval
        self.lastReportTime = CFAbsoluteTimeGetCurrent()
    }

    public func recordFFTTime(_ microseconds: Double) {
        append(&fftTimes, value: microseconds)
        maybeReport()
    }

    public func recordAudioBufferLevel(_ level: Int) {
        append(&audioBufferLevels, value: level)
    }

    public func recordDSPLatency(_ microseconds: Double) {
        append(&dspLatencies, value: microseconds)
    }

    public func recordFrameTime(_ milliseconds: Double) {
        append(&frameTimes, value: milliseconds)
        maybeReport()
    }

    public var averageFFTTime: Double {
        return average(of: fftTimes)
    }

    public var averageDSPLatency: Double {
        return average(of: dspLatencies)
    }

    public var averageFrameRate: Double {
        let avg = average(of: frameTimes)
        return avg > 0 ? 1000.0 / avg : 0
    }

    public func reset() {
        fftTimes.removeAll()
        audioBufferLevels.removeAll()
        dspLatencies.removeAll()
        frameTimes.removeAll()
        lastReportTime = CFAbsoluteTimeGetCurrent()
    }

    private func append<T>(_ array: inout [T], value: T) {
        if array.count >= maxSamples {
            array.removeFirst()
        }
        array.append(value)
    }

    private func average(of array: [Double]) -> Double {
        guard !array.isEmpty else { return 0 }
        return array.reduce(0, +) / Double(array.count)
    }

    private func maybeReport() {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastReportTime >= reportInterval else { return }
        lastReportTime = now

        reportQueue.async { [weak self] in
            guard let self = self else { return }
            let avgFFT = self.average(of: self.fftTimes)
            let avgDSP = self.average(of: self.dspLatencies)
            let avgFrame = self.average(of: self.frameTimes)
            let fps = avgFrame > 0 ? 1000.0 / avgFrame : 0
            let avgAudio = self.averageAudioLevel()

            self.logger.info("[PerformanceMonitor] FFT: \(Int(avgFFT))μs | DSP: \(Int(avgDSP))μs | FPS: \(Int(fps)) | Audio buffer: \(avgAudio)")
        }
    }

private func averageAudioLevel() -> Int {
guard !audioBufferLevels.isEmpty else { return 0 }
let sum = audioBufferLevels.reduce(0, +)
return sum / audioBufferLevels.count
}
}
