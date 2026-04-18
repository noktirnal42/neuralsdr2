//
//  SpectrumDisplay.swift
//  NeuralSDR2
//
//  Metal-based spectrum display
//  High-performance rendering using Metal
//

import SwiftUI
import Metal
import MetalKit

/// Spectrum display view using Metal for performance
public struct SpectrumDisplayView: View {
    @EnvironmentObject var appState: AppState
    @State private var spectrumData: [Float] = []
    @State private var frequencyLabels: [String] = []
    
    var body: some View {
        ZStack {
            Color.black
            
            if spectrumData.isEmpty {
                VStack {
                    Image(systemName: "waveform")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("No Signal")
                        .foregroundColor(.gray)
                }
            } else {
                MetalSpectrumView(spectrumData: $spectrumData)
                    .overlay(
                        VStack {
                            HStack {
                                Text("−60 dB")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("−30 dB")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("0 dB")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            .padding(4)
                            Spacer()
                        }
                    )
            }
        }
        .onAppear {
            startSpectrumUpdates()
        }
    }
    
    private func startSpectrumUpdates() {
        // Simulate spectrum data for now
        // In real implementation, this would come from DSP pipeline
        Timer.scheduledTimer(withTimeInterval: 1.0/30, repeats: true) { _ in
            updateSpectrum()
        }
    }
    
    private func updateSpectrum() {
        // Generate simulated spectrum data
        let fftSize = 1024
        var newData: [Float] = []
        
        for i in 0..<fftSize/2 + 1 {
            // Simulate noise floor around -90 dB
            let noise = Float.random(in: -95...-85)
            
            // Add some fake signals
            let center = Float(fftSize/2)
            let signal1 = -30 * exp(-pow(Float(i - Int(center) + 100), 2) / 500)
            let signal2 = -40 * exp(-pow(Float(i - Int(center) - 150), 2) / 300)
            
            newData.append(noise + signal1 + signal2)
        }
        
        spectrumData = newData
    }
}

/// Metal view for spectrum rendering
struct MetalSpectrumView: MTKView, ObservableObject {
    @Binding var spectrumData: [Float]
    
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var vertexBuffer: MTLBuffer?
    private var spectrumDataBuffer: [Float] = []
    
    init(spectrumData: Binding<[Float]>) {
        _spectrumData = spectrumData
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        
        self.device = device
        
        super.init(frame: .zero, device: device, colorPixelFormat: .bgra8Unorm)
        
        self.delegate = self
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        
        setupPipeline()
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupPipeline() {
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Could not create command queue")
        }
        self.commandQueue = commandQueue
        
        // Create pipeline state
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = makeVertexFunction(device: device)
        descriptor.fragmentFunction = makeFragmentFunction(device: device)
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError("Could not create pipeline state: \(error)")
        }
    }
    
    private func makeVertexFunction(device: MTLDevice) -> MTLFunction {
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        
        struct VertexIn {
            float2 position [[attribute(0)]];
            float value [[attribute(1)]];
        };
        
        struct VertexOut {
            float4 position [[position]];
            float value;
        };
        
        vertex VertexOut vertex_spectrum(uint id [[vertex_id]], constant float2* positions [[buffer(0)]], constant float* values [[buffer(1)]]) {
            VertexOut out;
            out.position = float4(positions[id], 0, 1);
            out.value = values[id];
            return out;
        }
        
        fragment float4 fragment_spectrum(VertexOut in [[stage_in]]) {
            float intensity = in.value;
            return float4(0.0, 1.0, 0.0, 1.0);  // Green line
        }
        """
        
        let library = try! device.makeLibrary(source: source, options: nil)
        return library.makeFunction(name: "vertex_spectrum")!
    }
    
    private func makeFragmentFunction(device: MTLDevice) -> MTLFunction {
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        
        fragment float4 fragment_spectrum(float value [[stage_in]]) {
            // Simple gradient based on value
            float r = max(0, min(1, (value + 60) / 30));
            return float4(r, 1.0 - r, 0, 1.0);
        }
        """
        
        let library = try! device.makeLibrary(source: source, options: nil)
        return library.makeFunction(name: "fragment_spectrum")!
    }
}

extension MetalSpectrumView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle resize
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.commandQueue.makeCommandBuffer() else {
            return
        }
        
        let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        renderCommandEncoder?.setRenderPipelineState(pipelineState)
        renderCommandEncoder?.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: 0)
        renderCommandEncoder?.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

// MARK: - Spectrum Plot (SwiftUI Fallback)

/// Simple SwiftUI spectrum plot (fallback if Metal not available)
struct SpectrumPlot: View {
    let data: [Float]
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard !data.isEmpty else { return }
                
                let width = geometry.size.width
                let height = geometry.size.height
                let step = width / CGFloat(data.count - 1)
                
                path.move(to: CGPoint(x: 0, y: height))
                
                for (index, value) in data.enumerated() {
                    let x = CGFloat(index) * step
                    // Map dB value (-100 to 0) to height
                    let normalizedValue = max(-100, min(0, value))
                    let y = height - (CGFloat((normalizedValue + 100) / 100) * height)
                    
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(Color.green, lineWidth: 2)
        }
    }
}

#Preview {
    SpectrumDisplayView()
        .environmentObject(AppState())
}
