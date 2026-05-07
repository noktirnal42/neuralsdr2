//
// WaterfallDisplay.swift
// NeuralSDR2
//
// Waterfall display using Metal for real-time spectrum history
//

import SwiftUI
import Metal
import MetalKit

public struct WaterfallDisplayView: View {

    public init() {}
    @EnvironmentObject var appState: AppState
    @State private var waterfallData: [[Float]] = []
    @State private var colorPalette: ColorPalette = .thermal

    let maxLines = 256

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

            if waterfallData.isEmpty || appState.deviceState == .disconnected {
                RadioConsoleEmptyState()
            } else {
                WaterfallRendererRepresentable(data: waterfallData, palette: colorPalette)
            }

            VStack {
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
        .onAppear {
            if !appState.spectrumData.isEmpty {
                appendSpectrumLine(appState.spectrumData)
            }
        }
        .onChange(of: appState.spectrumData) { newData in
            appendSpectrumLine(newData)
        }
        .onChange(of: appState.isRunning) { isRunning in
            if !isRunning {
                waterfallData.removeAll()
            }
        }
        .onChange(of: appState.deviceState) { newState in
            if newState == .disconnected {
                waterfallData.removeAll()
            }
        }
    }

    private func appendSpectrumLine(_ data: [Float]) {
        guard !data.isEmpty else { return }

        if waterfallData.count < maxLines {
            waterfallData.append(data)
        } else {
            waterfallData.removeFirst()
            waterfallData.append(data)
        }
    }
}

public class WaterfallRenderer: MTKView {

public var waterfallData: [[Float]] = []
public var palette: ColorPalette = .thermal

private var commandQueue: MTLCommandQueue!
private var pipelineState: MTLRenderPipelineState!
private var waterfallTexture: MTLTexture?
private var textureWidth: Int = 512
private var textureHeight: Int = 256

// Zero-copy waterfall buffer (shared storage on Apple Silicon)
private var waterfallDataBuffer: MTLBuffer?
private var waterfallBufferWidth: Int = 0
private var waterfallBufferHeight: Int = 0

private static let shaderSource: String = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
    };

    vertex VertexOut vertex_waterfall(uint vid [[vertex_id]]) {
        VertexOut out;
        float2 pos[6] = {
            float2(-1, -1), float2(1, -1), float2(-1, 1),
            float2(-1, 1),  float2(1, -1), float2(1, 1)
        };
        float2 uv[6] = {
            float2(0, 1), float2(1, 1), float2(0, 0),
            float2(0, 0), float2(1, 1), float2(1, 0)
        };
        out.position = float4(pos[vid], 0, 1);
        out.texCoord = uv[vid];
        return out;
    }

    float3 thermalPalette(float t) {
        float r = smoothstep(0.5, 1.0, t);
        float g = smoothstep(0.25, 0.75, t) * (1.0 - smoothstep(0.75, 1.0, t));
        float b = 1.0 - smoothstep(0.0, 0.5, t);
        return float3(r, g, b);
    }

    float3 grayscalePalette(float t) {
        return float3(t, t, t);
    }

    float3 rainbowPalette(float t) {
        float h = (1.0 - t) * 240.0;
        float s = 1.0;
        float v = t;
        float c = v * s;
        float hp = h / 60.0;
        float x = c * (1.0 - abs(fmod(hp, 2.0) - 1.0));
        float3 rgb;
        if (hp < 1.0)       rgb = float3(c, x, 0);
        else if (hp < 2.0)  rgb = float3(x, c, 0);
        else if (hp < 3.0)  rgb = float3(0, c, x);
        else if (hp < 4.0)  rgb = float3(0, x, c);
        else                rgb = float3(x, 0, c);
        float m = v - c;
        return rgb + float3(m, m, m);
    }

    float3 nightVisionPalette(float t) {
        return float3(t * 0.2, t, t * 0.1);
    }

    fragment float4 fragment_waterfall(VertexOut in [[stage_in]],
                                        texture2d<float, access::sample> waterfallTexture [[texture(0)]],
                                        constant int& paletteType [[buffer(0)]]) {
        constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);

        float value = waterfallTexture.sample(s, in.texCoord).r;
        constexpr float floorDB = -130.0;
        constexpr float ceilingDB = -20.0;
        float t = clamp((value - floorDB) / (ceilingDB - floorDB), 0.0, 1.0);

        float3 color;
        switch (paletteType) {
            case 0:  color = thermalPalette(t);     break;
            case 1:  color = grayscalePalette(t);   break;
            case 2:  color = rainbowPalette(t);     break;
            case 3:  color = nightVisionPalette(t);  break;
            default: color = thermalPalette(t);     break;
        }

        return float4(color, 1.0);
    }
    """

    public init(frame frameRect: CGRect = .zero, data: [[Float]] = [], palette: ColorPalette = .thermal) {
        self.waterfallData = data
        self.palette = palette

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal not supported")
        }

        super.init(frame: frameRect, device: device)
        self.colorPixelFormat = .bgra8Unorm
        self.delegate = self
        self.preferredFramesPerSecond = 30
        self.isPaused = false

        setupPipeline()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private func setupPipeline() {
        guard let device = self.device,
              let commandQueue = device.makeCommandQueue() else {
            fatalError("Could not create command queue")
        }
        self.commandQueue = commandQueue

        let library = try! device.makeLibrary(source: Self.shaderSource, options: nil)
        let vertexFunction = library.makeFunction(name: "vertex_waterfall")!
        let fragmentFunction = library.makeFunction(name: "fragment_waterfall")!

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        pipelineState = try! device.makeRenderPipelineState(descriptor: descriptor)
    }

private func ensureTexture(width: Int, height: Int) -> MTLTexture? {
guard let device = self.device else { return nil }

if let existing = waterfallTexture,
existing.width == width, existing.height == height {
return existing
}

let texDescriptor = MTLTextureDescriptor.texture2DDescriptor(
pixelFormat: .r32Float,
width: width,
height: height,
mipmapped: false
)
texDescriptor.usage = [.shaderRead, .shaderWrite]
texDescriptor.storageMode = .shared

waterfallTexture = device.makeTexture(descriptor: texDescriptor)
textureWidth = width
textureHeight = height
return waterfallTexture
}

private func ensureWaterfallBuffer(width: Int, height: Int) -> MTLBuffer? {
guard let device = self.device else { return nil }

if waterfallBufferWidth == width, waterfallBufferHeight == height,
let existing = waterfallDataBuffer {
return existing
}

let bufferSize = width * height * MemoryLayout<Float>.size
waterfallDataBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)
waterfallBufferWidth = width
waterfallBufferHeight = height
return waterfallDataBuffer
}

private func uploadWaterfallData() {
guard !waterfallData.isEmpty else { return }

let width = waterfallData[0].count
let height = waterfallData.count

guard let texture = ensureTexture(width: width, height: height),
let buffer = ensureWaterfallBuffer(width: width, height: height) else { return }

let bufferPtr = buffer.contents().assumingMemoryBound(to: Float.self)
let rowsToWrite = min(height, waterfallBufferHeight)
let bytesPerRow = waterfallBufferWidth * MemoryLayout<Float>.size

for row in 0..<rowsToWrite {
let lineData = waterfallData[row]
let destOffset = row * waterfallBufferWidth
let copyCount = min(lineData.count, waterfallBufferWidth)

for col in 0..<copyCount {
    bufferPtr[destOffset + col] = lineData[col]
}

if copyCount < waterfallBufferWidth {
    for col in copyCount..<waterfallBufferWidth {
        bufferPtr[destOffset + col] = -120.0
    }
}
}

let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                        size: MTLSize(width: waterfallBufferWidth, height: rowsToWrite, depth: 1))
texture.replace(region: region,
                mipmapLevel: 0,
                withBytes: bufferPtr,
                bytesPerRow: bytesPerRow)
}

}

extension WaterfallRenderer: MTKViewDelegate {

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        uploadWaterfallData()

        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        renderEncoder?.setRenderPipelineState(pipelineState)

        if let texture = waterfallTexture {
            renderEncoder?.setFragmentTexture(texture, index: 0)
            var paletteIndex = palette.metalIndex
            renderEncoder?.setFragmentBytes(&paletteIndex, length: MemoryLayout<Int>.size, index: 0)
            renderEncoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }

        renderEncoder?.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

public enum ColorPalette: Int, CaseIterable {
    case thermal = 0
    case grayscale = 1
    case rainbow = 2
    case nightVision = 3

    public var metalIndex: Int { rawValue }

    public var displayName: String {
        switch self {
        case .thermal: return "Thermal"
        case .grayscale: return "Grayscale"
        case .rainbow: return "Rainbow"
        case .nightVision: return "Night Vision"
        }
    }

    public func color(for value: Float) -> (Float, Float, Float) {
        let normalized = max(0, min(1, (value + 130) / 110))

        switch self {
        case .thermal:
            let r = smoothstep(0.5, 1.0, normalized)
            let g = smoothstep(0.25, 0.75, normalized) * (1.0 - smoothstep(0.75, 1.0, normalized))
            let b = 1.0 - smoothstep(0.0, 0.5, normalized)
            return (r, g, b)
        case .grayscale:
            return (normalized, normalized, normalized)
        case .rainbow:
            let hue = (1.0 - normalized) * 240.0
            return hslToRgb(h: hue, s: 1.0, l: normalized * 0.5)
        case .nightVision:
            return (normalized * 0.2, normalized, normalized * 0.1)
        }
    }

    private func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    private func hslToRgb(h: Float, s: Float, l: Float) -> (Float, Float, Float) {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = h / 60.0
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        var r: Float = 0, g: Float = 0, b: Float = 0
        if hp < 1 { r = c; g = x }
        else if hp < 2 { r = x; g = c }
        else if hp < 3 { g = c; b = x }
        else if hp < 4 { g = x; b = c }
        else if hp < 5 { r = x; b = c }
        else { r = c; b = x }
        let m = l - c / 2
        return (r + m, g + m, b + m)
    }
}

public struct WaterfallPlot: View {
    public let data: [[Float]]

    public init(data: [[Float]]) {
        self.data = data
    }

    public var body: some View {
        GeometryReader { geometry in
            if data.isEmpty {
                Color.black
            } else {
                Canvas { context, size in
                    let lineCount = data.count
                    let binCount = data[0].count
                    let lineHeight = size.height / CGFloat(lineCount)
                    let binWidth = size.width / CGFloat(binCount)

                    for (rowIdx, line) in data.enumerated() {
                        let y = size.height - CGFloat(rowIdx + 1) * lineHeight
                        for (colIdx, value) in line.enumerated() {
                            let x = CGFloat(colIdx) * binWidth
                            let normalized = max(0, min(1, (value + 130) / 110))
                            let color = Color(
                                red: Double(normalized),
                                green: Double(normalized * 0.5),
                                blue: Double(1 - normalized)
                            )
                            context.fill(
                                Path(CGRect(x: x, y: y, width: binWidth + 0.5, height: lineHeight + 0.5)),
                                with: .color(color)
                            )
                        }
                    }
                }
            }
        }
    }
}

public struct WaterfallRendererRepresentable: NSViewRepresentable {
    public var data: [[Float]]
    public var palette: ColorPalette

    public init(data: [[Float]], palette: ColorPalette) {
        self.data = data
        self.palette = palette
    }

    public func makeNSView(context: Context) -> WaterfallRenderer {
        WaterfallRenderer(data: data, palette: palette)
    }

    public func updateNSView(_ nsView: WaterfallRenderer, context: Context) {
        nsView.waterfallData = data
        nsView.palette = palette
    }
}

#Preview {
    WaterfallDisplayView()
        .environmentObject(AppState())
}
