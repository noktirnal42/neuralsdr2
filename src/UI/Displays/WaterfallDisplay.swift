//
//  WaterfallDisplay.swift
//  NeuralSDR2
//
//  Waterfall display using Metal for real-time spectrum history
//

import SwiftUI
import Metal
import MetalKit

/// Waterfall display view
public struct WaterfallDisplayView: View {
    @EnvironmentObject var appState: AppState
    @State private var waterfallData: [[Float]] = []
    @State private var colorPalette: ColorPalette = .thermal
    
    let maxLines = 256
    let fftSize = 1024
    
    var body: some View {
        ZStack {
            Color.black
            
            if waterfallData.isEmpty {
                VStack {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("Waterfall")
                        .foregroundColor(.gray)
                }
            } else {
                WaterfallRenderer(data: $waterfallData, palette: colorPalette)
                    .overlay(
                        VStack {
                            Spacer()
                            HStack {
                                Text("−100 dB")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("−50 dB")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("0 dB")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            .padding(4)
                        }
                    )
            }
        }
        .onAppear {
            startWaterfallUpdates()
        }
    }
    
    private func startWaterfallUpdates() {
        // Simulate waterfall data for now
        Timer.scheduledTimer(withTimeInterval: 1.0/30, repeats: true) { _ in
            updateWaterfall()
        }
    }
    
    private func updateWaterfall() {
        // Generate simulated spectrum line
        var newLine: [Float] = []
        let center = Float(fftSize / 2)
        
        for i in 0..<fftSize/2 + 1 {
            let noise = Float.random(in: -90...-80)
            // Add fake signals
            let signal1 = -20 * exp(-pow(Float(i) - center + 100, 2) / 500)
            let signal2 = -30 * exp(-pow(Float(i) - center - 150, 2) / 300)
            newLine.append(noise + signal1 + signal2)
        }
        
        if waterfallData.count < maxLines {
            waterfallData.append(newLine)
        } else {
            waterfallData.removeFirst()
            waterfallData.append(newLine)
        }
    }
}

/// Metal-based waterfall renderer
struct WaterfallRenderer: MTKView, ObservableObject {
    @Binding var data: [[Float]]
    let palette: ColorPalette
    
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var texture: MTLTexture!
    
    init(data: Binding<[[Float]]>, palette: ColorPalette) {
        _data = data
        self.palette = palette
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal not supported")
        }
        
        self.device = device
        
        super.init(frame: .zero, device: device, colorPixelFormat: .bgra8Unorm)
        
        self.delegate = self
        setupTexture()
        setupPipeline()
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }
    
    private func setupTexture() {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: 512,
            height: 256,
            mipmapped: false
        )
        textureDescriptor.usage = .shaderWrite
        textureDescriptor.storageMode = .shared
        
        texture = device.makeTexture(descriptor: textureDescriptor)
    }
    
    private func setupPipeline() {
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Could not create command queue")
        }
        self.commandQueue = commandQueue
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = makeVertexFunction()
        descriptor.fragmentFunction = makeFragmentFunction()
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        pipelineState = try! device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    private func makeVertexFunction() -> MTLFunction {
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        
        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };
        
        vertex VertexOut vertex_waterfall(uint id [[vertex_id]]) {
            VertexOut out;
            out.texCoord = float2(float(id & 1), float(id >> 1) & 1);
            out.position = float4(float2(-1.0 + 2.0 * out.texCoord.x, -1.0 + 2.0 * out.texCoord.y), 0, 1);
            return out;
        }
        """
        
        let library = try! device.makeLibrary(source: source, options: nil)
        return library.makeFunction(name: "vertex_waterfall")!
    }
    
    private func makeFragmentFunction() -> MTLFunction {
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        
        fragment float4 fragment_waterfall(float2 texCoord [[stage_in]]) {
            // Simple grayscale for now
            return float4(0.5, 0.5, 0.5, 1.0);
        }
        """
        
        let library = try! device.makeLibrary(source: source, options: nil)
        return library.makeFunction(name: "fragment_waterfall")!
    }
}

extension WaterfallRenderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        // Update texture with new data
        // Render fullscreen quad with texture
    }
}

// MARK: - Color Palettes

public enum ColorPalette {
    case thermal
    case grayscale
    case rainbow
    case nightVision
    
    func color(for value: Float) -> (Float, Float, Float) {
        // Map value (-100 to 0 dB) to 0-1 range
        let normalized = max(0, min(1, (value + 100) / 100))
        
        switch self {
        case .thermal:
            // Blue -> Red -> Yellow
            return (normalized, 0, 1 - normalized)
        case .grayscale:
            return (normalized, normalized, normalized)
        case .rainbow:
            // Rainbow gradient
            let r = sin(normalized * Float.pi)
            let g = sin(normalized * Float.pi - Float.pi/2)
            let b = sin(normalized * Float.pi - Float.pi)
            return (max(0, r), max(0, g), max(0, b))
        case .nightVision:
            return (0, normalized, 0)
        }
    }
}

// MARK: - SwiftUI Fallback

struct WaterfallPlot: View {
    let data: [[Float]]
    
    var body: some View {
        GeometryReader { geometry in
            Image(decorative: "waterfall")
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
    }
}

#Preview {
    WaterfallDisplayView()
        .environmentObject(AppState())
}
