//
//  EarthScene.swift
//  NeuralSDR2
//
//  3D Earth visualization using SceneKit
//  Renders orbital paths, satellites, and ground tracks in 3D space
//

import SwiftUI
import SceneKit
import MapKit

/// The 3D Earth View using SceneKit
public struct Earth3DView: NSViewRepresentable {
    @EnvironmentObject var mapState: MapState
    
    public func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = setupScene()
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.backgroundColor = .black
        
        // Setup camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 15)
        scnView.scene?.rootNode.addChildNode(cameraNode)
        
        return scnView
    }
    
    public func updateNSView(_ nsView: SCNView, context: Context) {
        updateSatellitePositions(in: nsView.scene!)
    }
    
    private func setupScene() -> SCNScene {
        let scene = SCNScene()
        
        // 1. The Earth
        let earthGeometry = SCNSphere(radius: 6.371) // Earth radius in 1000km
        let earthNode = SCNNode(geometry: earthGeometry)
        
        // Earth Texture
        let material = SCNMaterial()
        material.diffuse.contents = NSImage(named: "earth_day_map") // Fallback to color if asset missing
        material.specular.contents = NSColor.white
        material.shininess = 0.1
        earthNode.geometry?.materials = [material]
        
        // 2. Atmosphere Glow
        let atmosphereGeometry = SCNSphere(radius: 6.45)
        let atmosphereNode = SCNNode(geometry: atmosphereGeometry)
        let atmosphereMaterial = SCNMaterial()
        atmosphereMaterial.diffuse.contents = NSColor.cyan.withAlphaComponent(0.2)
        atmosphereMaterial.blendMode = .add
        atmosphereNode.geometry?.materials = [atmosphereMaterial]
        
        // 3. Sun / Lighting
        let sunNode = SCNNode()
        sunNode.light = SCNLight()
        sunNode.light?.type = .directional
        sunNode.light?.color = NSColor.white
        sunNode.position = SCNVector3(x: 100, y: 100, z: 100)
        sunNode.eulerAngles = SCNVector3(-Float.pi/4, -Float.pi/4, 0)
        
        scene.rootNode.addChildNode(earthNode)
        scene,rootNode.addChildNode(atmosphereNode)
        scene.rootNode.addChildNode(sunNode)
        
        return scene
    }
    
    private func updateSatellitePositions(in scene: SCNScene) {
        // Update orbits based on mapState.trackedSatellites
        for sat in mapState.trackedSatellites {
            // Convert Lat/Lon to Cartesian X,Y,Z
            let pos = calculateCartesianPosition(lat: sat.coordinate.latitude, lon: sat.coordinate.longitude, alt: 500)
            
            // Update or create satellite node
            let nodeName = "sat_\(sat.name)"
            let satNode: SCNNode
            if let existing = scene.rootNode.childNode(withName: nodeName, recursively: true) {
                satNode = existing
            } else {
                satNode = SCNNode(geometry: SCNSphere(radius: 0.1))
                satNode.name = nodeName
                satNode.geometry?.firstMaterial?.diffuse.contents = NSColor.yellow
                scene.rootNode.addChildNode(satNode)
            }
            
            satNode.position = SCNVector3(pos.x, pos.y, pos.z)
        }
    }
    
    private func calculateCartesianPosition(lat: Double, lon: Double, alt: Double) -> SIMD3<<DoubleDouble> {
        let r = 6371.0 + alt
        let phi = (90.0 - lat) * .pi / 180.0
        let theta = lon * .pi / 180, la = lat * .pi / 180.0
        
        return SIMD3<<DoubleDouble>(
            r * sin(phi) * cos(theta),
            r * cos(la),
            r * sin(phi) * sin(theta)
        )
    }
}
