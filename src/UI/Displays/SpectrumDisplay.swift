//
// SpectrumDisplay.swift
// NeuralSDR2
//
// Metal-based spectrum display
// High-performance rendering using Metal with real FFT data
//

import SwiftUI
import Metal
import MetalKit

struct RadioConsoleEmptyState: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: appState.deviceState == .disconnected ? "antenna.radiowaves.left.and.right.slash" : "dot.radiowaves.left.and.right")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(appState.deviceState == .disconnected ? .orange : .gray)

            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(appState.deviceState == .disconnected ? .orange : .white.opacity(0.82))
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                ConsoleHintPill(label: "Mode", value: appState.currentMode.rawValue)
                ConsoleHintPill(label: "Center", value: centerFrequencyLabel)
            }
        }
        .padding(28)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var title: String {
        if appState.deviceState == .disconnected {
            return "Receiver Offline"
        }
        return appState.isRunning ? "Tuning Receiver" : "Radio Console Ready"
    }

    private var subtitle: String {
        if appState.deviceState == .disconnected {
            return "Connect an RTL-SDR device to start live spectrum and waterfall monitoring."
        }
        if appState.isRunning {
            return "The receiver is running but no spectrum data has populated yet."
        }
        return "Press Start to begin live RF monitoring from the current workspace."
    }

    private var centerFrequencyLabel: String {
        if appState.frequency >= 1_000_000_000 {
            return String(format: "%.3f GHz", appState.frequency / 1_000_000_000)
        }
        return String(format: "%.3f MHz", appState.frequency / 1_000_000)
    }
}

private struct ConsoleHintPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.88))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

public struct SpectrumDisplayView: View {

    public init() {}
    @EnvironmentObject var appState: AppState
    @State private var spectrumData: [Float] = []

    private var frequencyLabels: [(position: CGFloat, label: String)] {
        let freq = appState.frequency
        let sr = appState.sampleRate
        let halfSR = sr / 2.0
        let startFreq = freq - halfSR
        let endFreq = freq + halfSR
        let numLabels = 9
        var labels: [(position: CGFloat, label: String)] = []
        for i in 0...numLabels {
            let fraction = CGFloat(i) / CGFloat(numLabels)
            let f = startFreq + (endFreq - startFreq) * Double(fraction)
            labels.append((position: fraction, label: formatFreq(f)))
        }
        return labels
    }

    private func formatFreq(_ hz: Double) -> String {
        if hz >= 1_000_000_000 {
            return String(format: "%.1fG", hz / 1_000_000_000)
        } else if hz >= 1_000_000 {
            return String(format: "%.1fM", hz / 1_000_000)
        } else if hz >= 1_000 {
            return String(format: "%.0fk", hz / 1_000)
        } else {
            return "\(Int(hz))"
        }
    }

public var body: some View {
        ZStack {
            Color.black
            
            if spectrumData.isEmpty || appState.deviceState == .disconnected {
                RadioConsoleEmptyState()
            } else {
            MetalSpectrumViewRepresentable(
                spectrumData: spectrumData,
                centerFrequency: appState.frequency,
                sampleRate: appState.sampleRate,
                onFrequencyClick: { freq in appState.setFrequency(freq) },
                onFrequencyDrag: { freq in appState.setFrequency(freq) }
            )
        }

            VStack {
                HStack {
                    Text("-130 dB")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Spacer()
                    Text("-100 dB")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Spacer()
                    Text("-70 dB")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Spacer()
                    Text("-40 dB")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Spacer()
                    Text("-20 dB")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)

                Spacer()

                HStack(spacing: 0) {
                    ForEach(Array(frequencyLabels.enumerated()), id: \.offset) { _, item in
                        if item.position == 0 {
                            Text(item.label)
                                .font(.system(size: 8))
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if item.position >= 1.0 {
                            Text(item.label)
                                .font(.system(size: 8))
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        } else {
                            Text(item.label)
                                .font(.system(size: 8))
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 2)
            }
        }
        .onChange(of: appState.spectrumData) { newData in
            spectrumData = newData
        }
    }
}

public class MetalSpectrumView: MTKView {

    public var spectrumData: [Float] = []
    public var onFrequencyClick: ((Double) -> Void)?
    public var centerFrequency: Double = 1090_000_000
    public var sampleRate: Double = 2_048_000
    public var onFrequencyDrag: ((Double) -> Void)?

    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var spectrumBuffer: MTLBuffer?
    private var isDragging = false

    private static let shaderSource: String = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float value;
    };

    vertex VertexOut vertex_spectrum(uint id [[vertex_id]],
                                      constant float* values [[buffer(0)]],
                                      constant float& count [[buffer(1)]]) {
        VertexOut out;
        float x = -1.0 + 2.0 * (float(id) / max(count - 1.0, 1.0));
        float dB = values[id];
        constexpr float floorDB = -130.0;
        constexpr float ceilingDB = -20.0;
        float normalized = clamp((dB - floorDB) / (ceilingDB - floorDB), 0.0, 1.0);
        float y = normalized * 2.0 - 1.0;
        out.position = float4(x, y, 0, 1);
        out.value = normalized;
        return out;
    }

    fragment float4 fragment_spectrum(VertexOut in [[stage_in]]) {
        float t = in.value;
        float r = smoothstep(0.5, 0.8, t);
        float g = smoothstep(0.2, 0.5, t) * (1.0 - smoothstep(0.7, 1.0, t));
        float b = (1.0 - smoothstep(0.0, 0.4, t)) * 0.3;
        return float4(r, g, b, 1.0);
    }
    """

    public init(frame frameRect: CGRect = .zero, spectrumData: [Float] = []) {
        self.spectrumData = spectrumData

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        super.init(frame: frameRect, device: device)
        self.colorPixelFormat = .bgra8Unorm
        self.delegate = self
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        self.preferredFramesPerSecond = 30
        self.isPaused = false

        setupPipeline()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupPipeline() {
        guard let device = self.device,
              let commandQueue = device.makeCommandQueue() else {
            fatalError("Could not create command queue")
        }
        self.commandQueue = commandQueue

        let library = try! device.makeLibrary(source: Self.shaderSource, options: nil)
        let vertexFunction = library.makeFunction(name: "vertex_spectrum")!
        let fragmentFunction = library.makeFunction(name: "fragment_spectrum")!

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        pipelineState = try! device.makeRenderPipelineState(descriptor: descriptor)
    }

    private func ensureBuffer(count: Int) -> MTLBuffer? {
        let requiredSize = count * MemoryLayout<Float>.size
        if let existing = spectrumBuffer, existing.length >= requiredSize {
            return existing
        }
        spectrumBuffer = device?.makeBuffer(length: requiredSize, options: .storageModeShared)
        return spectrumBuffer
    }

    public override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        isDragging = true
        let freq = pixelToFrequency(event)
        onFrequencyClick?(freq)
        onFrequencyDrag?(freq)
    }

    public override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        guard isDragging else { return }
        let freq = pixelToFrequency(event)
        onFrequencyDrag?(freq)
    }

    public override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        isDragging = false
    }

    public override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        let delta = event.scrollingDeltaY
        let step: Double
        if event.modifierFlags.contains(.shift) {
            step = 10_000
        } else if event.modifierFlags.contains(.command) {
            step = 100_000
        } else {
            step = 1_000
        }
        let freqAdjust = Double(delta) * step
        onFrequencyDrag?(centerFrequency + freqAdjust)
    }

    private func pixelToFrequency(_ event: NSEvent) -> Double {
        let point = convert(event.locationInWindow, from: nil)
        let viewWidth = bounds.width
        guard viewWidth > 0 else { return centerFrequency }
        let fraction = Double(point.x / viewWidth)
        let halfSR = sampleRate / 2.0
        return centerFrequency - halfSR + fraction * sampleRate
    }
}

extension MetalSpectrumView: MTKViewDelegate {

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        renderEncoder?.setRenderPipelineState(pipelineState)

        if !spectrumData.isEmpty, let buffer = ensureBuffer(count: spectrumData.count) {
            memcpy(buffer.contents(), spectrumData, spectrumData.count * MemoryLayout<Float>.size)
            renderEncoder?.setVertexBuffer(buffer, offset: 0, index: 0)
            var count = Float(spectrumData.count)
            renderEncoder?.setVertexBytes(&count, length: MemoryLayout<Float>.size, index: 1)
            renderEncoder?.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: spectrumData.count)
        }

        renderEncoder?.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

public struct SpectrumPlot: View {
    let data: [Float]

    public init(data: [Float]) {
        self.data = data
    }

    public var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard !data.isEmpty else { return }

                let width = geometry.size.width
                let height = geometry.size.height
                let step = width / CGFloat(data.count - 1)

                path.move(to: CGPoint(x: 0, y: height))

                for (index, value) in data.enumerated() {
                    let x = CGFloat(index) * step
                    let normalizedValue = max(-130, min(-20, value))
                    let y = height - (CGFloat((normalizedValue + 130) / 110) * height)
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(Color.green, lineWidth: 2)
        }
    }
}

public struct MetalSpectrumViewRepresentable: NSViewRepresentable {
    public var spectrumData: [Float]
    public var centerFrequency: Double
    public var sampleRate: Double
    public var onFrequencyClick: ((Double) -> Void)?
    public var onFrequencyDrag: ((Double) -> Void)?

    public init(spectrumData: [Float], centerFrequency: Double = 1090_000_000, sampleRate: Double = 2_048_000, onFrequencyClick: ((Double) -> Void)? = nil, onFrequencyDrag: ((Double) -> Void)? = nil) {
        self.spectrumData = spectrumData
        self.centerFrequency = centerFrequency
        self.sampleRate = sampleRate
        self.onFrequencyClick = onFrequencyClick
        self.onFrequencyDrag = onFrequencyDrag
    }

    public func makeNSView(context: Context) -> MetalSpectrumView {
        let view = MetalSpectrumView(spectrumData: spectrumData)
        view.onFrequencyClick = onFrequencyClick
        view.onFrequencyDrag = onFrequencyDrag
        view.centerFrequency = centerFrequency
        view.sampleRate = sampleRate
        return view
    }

    public func updateNSView(_ nsView: MetalSpectrumView, context: Context) {
        nsView.spectrumData = spectrumData
        nsView.onFrequencyClick = onFrequencyClick
        nsView.onFrequencyDrag = onFrequencyDrag
        nsView.centerFrequency = centerFrequency
        nsView.sampleRate = sampleRate
    }
}

#Preview {
    SpectrumDisplayView()
        .environmentObject(AppState())
}
