//
// EarthScene.swift
// NeuralSDR2
//
// 3D Earth visualization using SceneKit
// Renders orbital paths, satellites, and ground tracks in 3D space
//

import SwiftUI
import SceneKit
import MapKit
import CoreLocation
import CoreGraphics

public struct Earth3DView: NSViewRepresentable {
    @EnvironmentObject var mapState: MapState

    public func makeCoordinator() -> EarthSceneCoordinator {
        EarthSceneCoordinator()
    }

    public func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = context.coordinator.scene
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.backgroundColor = NSColor.black
        scnView.antialiasingMode = .multisampling4X

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 45
        cameraNode.camera?.zFar = 500
        cameraNode.position = SCNVector3(x: 0, y: 5, z: 18)
        cameraNode.name = "cameraNode"
        context.coordinator.scene.rootNode.addChildNode(cameraNode)

        context.coordinator.setupScene()
        context.coordinator.startAutoRotation(in: scnView)

        return scnView
    }

    public func updateNSView(_ nsView: SCNView, context: Context) {
        context.coordinator.updateSatellites(mapState: mapState)
    }
}

public class EarthSceneCoordinator: NSObject {
    public let scene = SCNScene()
    private var earthNode = SCNNode()
    private var atmosphereNode = SCNNode()
    private var satellitesGroup = SCNNode()
    private var orbitPathsGroup = SCNNode()
    private var groundTracksGroup = SCNNode()
    private var displayLink: CVDisplayLink?
    private var rotationAngle: Float = 0

    public override init() {
        super.init()
        satellitesGroup.name = "satellitesGroup"
        orbitPathsGroup.name = "orbitPathsGroup"
        groundTracksGroup.name = "groundTracksGroup"
    }

    deinit {
        stopAutoRotation()
    }

    public func setupScene() {
        let rootNode = scene.rootNode

        earthNode = createEarthNode()
        atmosphereNode = createAtmosphereNode()
        let gridLines = createGridLines()
        for line in gridLines {
            earthNode.addChildNode(line)
        }

        let starsNode = createStarsNode()
        let sunNode = createSunNode()

        rootNode.addChildNode(earthNode)
        rootNode.addChildNode(atmosphereNode)
        rootNode.addChildNode(satellitesGroup)
        rootNode.addChildNode(orbitPathsGroup)
        rootNode.addChildNode(groundTracksGroup)
        rootNode.addChildNode(starsNode)
        rootNode.addChildNode(sunNode)
    }

    // MARK: - Earth

    private func createEarthNode() -> SCNNode {
        let earthGeometry = SCNSphere(radius: 6.371)
        earthGeometry.segmentCount = 96
        let earthNode = SCNNode(geometry: earthGeometry)
        earthNode.name = "earthNode"

        let material = SCNMaterial()
        material.diffuse.contents = generateProceduralEarthTexture()
        material.specular.contents = NSColor(white: 0.15, alpha: 1.0)
        material.shininess = 0.05

        earthNode.geometry?.materials = [material]

        return earthNode
    }

    private func generateProceduralEarthTexture() -> NSImage {
        let width = 1024
        let height = 512
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return NSImage(size: NSSize(width: 1, height: 1))
        }

        let oceanColor = CGColor(red: 0.102, green: 0.227, blue: 0.361, alpha: 1.0)
        let landColor = CGColor(red: 0.176, green: 0.353, blue: 0.153, alpha: 1.0)
        let iceColor = CGColor(red: 0.92, green: 0.94, blue: 0.96, alpha: 1.0)
        let desertColor = CGColor(red: 0.761, green: 0.698, blue: 0.502, alpha: 1.0)

        context.setFillColor(oceanColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let continents: [[(lat: Double, lon: Double)]] = [
            northAmerica(),
            southAmerica(),
            europe(),
            africa(),
            asia(),
            australia(),
            antarctica()
        ]

        let desertRegions: [[(lat: Double, lon: Double)]] = [
            saharaDesert(),
            arabianDesert(),
            australianOutback(),
            gobiDesert()
        ]

        for continent in continents {
            drawPolygon(context: context, points: continent, color: landColor, width: width, height: height)
        }

        for desert in desertRegions {
            drawPolygon(context: context, points: desert, color: desertColor, width: width, height: height)
        }

        drawIceCap(context: context, minLat: 70, color: iceColor, width: width, height: height)
        drawIceCap(context: context, minLat: -75, color: iceColor, width: width, height: height)

        drawCoastlineGrid(context: context, width: width, height: height)

        image.unlockFocus()
        return image
    }

    private func drawPolygon(context: CGContext, points: [(lat: Double, lon: Double)], color: CGColor, width: Int, height: Int) {
        guard !points.isEmpty else { return }
        context.setFillColor(color)
        context.move(to: latLonToPixel(lat: points[0].lat, lon: points[0].lon, width: width, height: height))
        for i in 1..<points.count {
            context.addLine(to: latLonToPixel(lat: points[i].lat, lon: points[i].lon, width: width, height: height))
        }
        context.closePath()
        context.fillPath()
    }

    private func latLonToPixel(lat: Double, lon: Double, width: Int, height: Int) -> CGPoint {
        let x = (lon + 180.0) / 360.0 * Double(width)
        let y = (90.0 - lat) / 180.0 * Double(height)
        return CGPoint(x: x, y: y)
    }

    private func drawIceCap(context: CGContext, minLat: Double, color: CGColor, width: Int, height: Int) {
        context.setFillColor(color)
        if minLat > 0 {
            let y = latLonToPixel(lat: minLat, lon: 0, width: width, height: height).y
            context.fill(CGRect(x: 0, y: y, width: CGFloat(width), height: CGFloat(height) - y))
        } else {
            let y = latLonToPixel(lat: minLat, lon: 0, width: width, height: height).y
            context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: y))
        }
    }

    private func drawCoastlineGrid(context: CGContext, width: Int, height: Int) {
        context.setStrokeColor(CGColor(red: 0.3, green: 0.5, blue: 0.65, alpha: 0.15))
        context.setLineWidth(0.5)
        for lon in stride(from: -180.0, through: 180.0, by: 30.0) {
            let x = (lon + 180.0) / 360.0 * Double(width)
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: CGFloat(height)))
        }
        for lat in stride(from: -90.0, through: 90.0, by: 30.0) {
            let y = (90.0 - lat) / 180.0 * Double(height)
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: CGFloat(width), y: y))
        }
        context.strokePath()
    }

    // MARK: - Continent Outlines (simplified lat/lon polygons)

    private func northAmerica() -> [(lat: Double, lon: Double)] {
        [
            (72, -168), (72, -140), (70, -140), (70, -100), (60, -95),
            (60, -80), (65, -65), (60, -65), (50, -55), (45, -65),
            (43, -70), (30, -80), (25, -80), (25, -90), (20, -90),
            (15, -90), (15, -85), (10, -80), (30, -115), (35, -120),
            (48, -125), (55, -130), (60, -140), (65, -168), (72, -168)
        ]
    }

    private func southAmerica() -> [(lat: Double, lon: Double)] {
        [
            (12, -75), (10, -72), (7, -60), (5, -52), (0, -50),
            (-5, -35), (-10, -37), (-15, -40), (-23, -43), (-30, -50),
            (-35, -57), (-40, -62), (-45, -65), (-50, -70), (-55, -68),
            (-55, -65), (-52, -70), (-48, -75), (-40, -73), (-30, -71),
            (-20, -70), (-15, -75), (-5, -80), (0, -78), (5, -77),
            (10, -75), (12, -75)
        ]
    }

    private func europe() -> [(lat: Double, lon: Double)] {
        [
            (70, 25), (72, 30), (70, 40), (65, 40), (60, 40),
            (55, 40), (50, 40), (47, 40), (45, 30), (40, 28),
            (37, 25), (35, 25), (38, 20), (37, 15), (40, 15),
            (44, 10), (43, 5), (46, 0), (48, -5), (50, -5),
            (55, -5), (58, -5), (60, 0), (62, 5), (65, 12),
            (68, 15), (70, 20), (70, 25)
        ]
    }

    private func africa() -> [(lat: Double, lon: Double)] {
        [
            (37, -10), (37, 10), (35, 12), (32, 13), (30, 10),
            (25, 15), (20, 20), (15, 20), (12, 15), (10, 10),
            (5, 10), (5, 5), (4, 2), (5, -5), (5, -10),
            (7, -15), (10, -17), (15, -17), (20, -17), (25, -15),
            (30, -10), (35, -5), (37, -10),
            (5, 42), (2, 45), (-5, 42), (-10, 40), (-15, 40),
            (-20, 35), (-25, 35), (-30, 32), (-34, 25), (-35, 20),
            (-34, 18), (-30, 17), (-25, 15), (-20, 12), (-15, 12),
            (-10, 15), (-5, 12), (0, 10), (5, 0), (5, 10),
            (10, 15), (15, 20), (20, 25), (25, 30), (30, 33),
            (32, 35), (37, 10), (37, -10)
        ]
    }

    private func asia() -> [(lat: Double, lon: Double)] {
        [
            (72, 40), (75, 70), (75, 100), (72, 130), (70, 140),
            (65, 170), (60, 165), (55, 155), (50, 145), (45, 140),
            (40, 130), (35, 130), (35, 125), (30, 120), (25, 120),
            (22, 115), (20, 110), (15, 108), (10, 105), (5, 105),
            (1, 104), (5, 100), (10, 100), (15, 100), (20, 95),
            (22, 90), (25, 90), (28, 88), (25, 80), (20, 75),
            (15, 75), (10, 77), (8, 77), (5, 80), (0, 100),
            (-8, 115), (-8, 120), (-5, 130), (-2, 135), (0, 140),
            (5, 140), (10, 125), (20, 120), (25, 122), (30, 122),
            (35, 140), (40, 142), (45, 145), (50, 155), (55, 160),
            (60, 160), (65, 170), (70, 140), (72, 130),
            (50, 50), (45, 50), (40, 45), (37, 40), (35, 35),
            (30, 35), (25, 45), (20, 55), (15, 50), (12, 45),
            (15, 42), (20, 40), (25, 35), (28, 35), (30, 33),
            (32, 35), (35, 40), (40, 45), (45, 50), (50, 50),
            (55, 50), (60, 50), (65, 50), (70, 60), (72, 70),
            (72, 40)
        ]
    }

    private func australia() -> [(lat: Double, lon: Double)] {
        [
            (-12, 130), (-12, 136), (-15, 140), (-18, 146),
            (-20, 148), (-25, 152), (-28, 153), (-33, 152),
            (-37, 150), (-38, 145), (-38, 140), (-35, 137),
            (-32, 132), (-28, 128), (-25, 114), (-22, 114),
            (-20, 118), (-15, 125), (-12, 130)
        ]
    }

    private func antarctica() -> [(lat: Double, lon: Double)] {
        [
            (-65, -60), (-70, -30), (-70, 0), (-68, 30), (-70, 60),
            (-68, 90), (-70, 120), (-68, 150), (-70, 180), (-68, -150),
            (-70, -120), (-68, -90), (-65, -60)
        ]
    }

    // MARK: - Desert Regions

    private func saharaDesert() -> [(lat: Double, lon: Double)] {
        [
            (30, -10), (30, 10), (25, 15), (20, 20), (15, 20),
            (15, 35), (20, 40), (25, 40), (30, 35), (32, 30),
            (30, 10), (30, -10)
        ]
    }

    private func arabianDesert() -> [(lat: Double, lon: Double)] {
        [
            (28, 35), (28, 45), (25, 50), (20, 55), (15, 50),
            (15, 42), (20, 40), (25, 35), (28, 35)
        ]
    }

    private func australianOutback() -> [(lat: Double, lon: Double)] {
        [
            (-20, 120), (-20, 130), (-25, 135), (-28, 140),
            (-30, 140), (-30, 130), (-28, 120), (-25, 115),
            (-20, 120)
        ]
    }

    private func gobiDesert() -> [(lat: Double, lon: Double)] {
        [
            (45, 90), (45, 105), (40, 110), (38, 105),
            (38, 95), (40, 90), (45, 90)
        ]
    }

    // MARK: - Grid Lines (3D on Earth surface)

    private func createGridLines() -> [SCNNode] {
        var nodes: [SCNNode] = []
        let gridRadius: Float = 6.372
        let gridColor = NSColor(white: 0.6, alpha: 0.25)

        for lat in stride(from: -60.0, through: 60.0, by: 30.0) {
            let node = createLatitudeLine(at: lat, radius: gridRadius, color: gridColor)
            node.name = "latLine_\(lat)"
            nodes.append(node)
        }

        for lon in stride(from: -180.0, through: 150.0, by: 30.0) {
            let node = createLongitudeLine(at: lon, radius: gridRadius, color: gridColor)
            node.name = "lonLine_\(lon)"
            nodes.append(node)
        }

        return nodes
    }

    private func createLatitudeLine(at latitude: Double, radius: Float, color: NSColor) -> SCNNode {
        let segments = 128
        var vertices: [SCNVector3] = []
        let latRad = Float(latitude * .pi / 180.0)
        let r = radius * cos(latRad)
        let y = radius * sin(latRad)

        for i in 0...segments {
            let lonRad = Float(i) / Float(segments) * 2.0 * Float.pi
            vertices.append(SCNVector3(r * cos(lonRad), y, r * sin(lonRad)))
        }

        let source = SCNGeometrySource(vertices: vertices)
        var indices: [Int32] = []
        for i in 0..<Int32(segments) {
            indices.append(i)
            indices.append(i + 1)
        }
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])

        let material = SCNMaterial()
        material.diffuse.contents = color
        material.isDoubleSided = true
        material.lightingModel = .constant
        geometry.materials = [material]

        return SCNNode(geometry: geometry)
    }

    private func createLongitudeLine(at longitude: Double, radius: Float, color: NSColor) -> SCNNode {
        let segments = 128
        var vertices: [SCNVector3] = []
        let lonRad = Float(longitude * .pi / 180.0)

        for i in 0...segments {
            let latRad = Float(i) / Float(segments) * Float.pi - Float.pi / 2.0
            vertices.append(SCNVector3(
                radius * cos(latRad) * cos(lonRad),
                radius * sin(latRad),
                radius * cos(latRad) * sin(lonRad)
            ))
        }

        let source = SCNGeometrySource(vertices: vertices)
        var indices: [Int32] = []
        for i in 0..<Int32(segments) {
            indices.append(i)
            indices.append(i + 1)
        }
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])

        let material = SCNMaterial()
        material.diffuse.contents = color
        material.isDoubleSided = true
        material.lightingModel = .constant
        geometry.materials = [material]

        return SCNNode(geometry: geometry)
    }

    // MARK: - Atmosphere

    private func createAtmosphereNode() -> SCNNode {
        let atmosphereGeometry = SCNSphere(radius: 6.45)
        atmosphereGeometry.segmentCount = 64
        let atmosphereNode = SCNNode(geometry: atmosphereGeometry)
        atmosphereNode.name = "atmosphereNode"

        let atmosphereMaterial = SCNMaterial()
        atmosphereMaterial.diffuse.contents = NSColor.cyan.withAlphaComponent(0.08)
        atmosphereMaterial.blendMode = .add
        atmosphereMaterial.lightingModel = .constant
        atmosphereMaterial.isDoubleSided = true
        atmosphereNode.geometry?.materials = [atmosphereMaterial]

        let outerAtmosphereGeometry = SCNSphere(radius: 6.55)
        outerAtmosphereGeometry.segmentCount = 64
        let outerNode = SCNNode(geometry: outerAtmosphereGeometry)
        outerNode.name = "outerAtmosphereNode"

        let outerMaterial = SCNMaterial()
        outerMaterial.diffuse.contents = NSColor.cyan.withAlphaComponent(0.03)
        outerMaterial.blendMode = .add
        outerMaterial.lightingModel = .constant
        outerMaterial.isDoubleSided = true
        outerNode.geometry?.materials = [outerMaterial]

        atmosphereNode.addChildNode(outerNode)

        return atmosphereNode
    }

    // MARK: - Stars

    private func createStarsNode() -> SCNNode {
        let starsNode = SCNNode()
        starsNode.name = "starsNode"
        let starDistance: Float = 100.0

        for _ in 0..<200 {
            let theta = Float.random(in: 0...2.0 * Float.pi)
            let phi = Float.random(in: -Float.pi / 2.0...Float.pi / 2.0)
            let starRadius = Float.random(in: 0.02...0.08)
            let brightness = Float.random(in: 0.4...1.0)

            let starGeometry = SCNSphere(radius: CGFloat(starRadius))
            starGeometry.segmentCount = 4
            let starNode = SCNNode(geometry: starGeometry)
            starNode.position = SCNVector3(
                starDistance * cos(phi) * cos(theta),
                starDistance * sin(phi),
                starDistance * cos(phi) * sin(theta)
            )

            let starMaterial = SCNMaterial()
            starMaterial.diffuse.contents = NSColor(white: CGFloat(brightness), alpha: 1.0)
            starMaterial.lightingModel = .constant
            starMaterial.isDoubleSided = true
            starNode.geometry?.materials = [starMaterial]

            starsNode.addChildNode(starNode)
        }

        return starsNode
    }

    // MARK: - Sun

    private func createSunNode() -> SCNNode {
        let sunNode = SCNNode()
        sunNode.name = "sunNode"
        sunNode.light = SCNLight()
        sunNode.light?.type = .directional
        sunNode.light?.color = NSColor.white
        sunNode.light?.intensity = 1200
        sunNode.position = SCNVector3(x: 50, y: 30, z: 50)
        sunNode.eulerAngles = SCNVector3(-Float.pi / 6, -Float.pi / 6, 0)

        let sunVisualGeometry = SCNSphere(radius: 1.0)
        let sunVisualNode = SCNNode(geometry: sunVisualGeometry)
        sunVisualNode.position = SCNVector3(x: 50, y: 30, z: 50)

        let sunMaterial = SCNMaterial()
        sunMaterial.diffuse.contents = NSColor.yellow
        sunMaterial.emission.contents = NSColor.yellow
        sunMaterial.lightingModel = .constant
        sunMaterial.isDoubleSided = true
        sunVisualNode.geometry?.materials = [sunMaterial]

        let containerNode = SCNNode()
        containerNode.addChildNode(sunNode)
        containerNode.addChildNode(sunVisualNode)

        return containerNode
    }

    // MARK: - Cartesian Position (Corrected)

    public static func calculateCartesianPosition(lat: Double, lon: Double, alt: Double) -> SIMD3<Float> {
        let r = Float(6371.0 + alt)
        let latRad = Float(lat * .pi / 180.0)
        let lonRad = Float(lon * .pi / 180.0)
        return SIMD3<Float>(
            r * cos(latRad) * cos(lonRad),
            r * sin(latRad),
            r * cos(latRad) * sin(lonRad)
        )
    }

    // MARK: - Satellite Updates

    public func updateSatellites(mapState: MapState) {
        var activeNames: Set<String> = []

        for sat in mapState.trackedSatellites {
            let nodeName = "sat_\(sat.name)"
            let orbitName = "orbit_\(sat.name)"
            let trackName = "groundTrack_\(sat.name)"
            activeNames.insert(nodeName)

            let pos = Self.calculateCartesianPosition(
                lat: sat.coordinate.latitude,
                lon: sat.coordinate.longitude,
                alt: 500
            )

            if let existing = satellitesGroup.childNode(withName: nodeName, recursively: false) {
                let moveAction = SCNAction.move(to: SCNVector3(pos.x, pos.y, pos.z), duration: 0.5)
                existing.runAction(moveAction)
            } else {
                let satDot = SCNSphere(radius: 0.12)
                let satNode = SCNNode(geometry: satDot)
                satNode.name = nodeName
                satNode.position = SCNVector3(pos.x, pos.y, pos.z)

                let satMaterial = SCNMaterial()
                satMaterial.diffuse.contents = sat.isVisible ? NSColor.green : NSColor.yellow
                satMaterial.emission.contents = sat.isVisible ? NSColor.green : NSColor.yellow
                satMaterial.lightingModel = .constant
                satNode.geometry?.materials = [satMaterial]

                let labelNode = createLabelNode(text: sat.name)
                labelNode.position = SCNVector3(0, 0.3, 0)
                satNode.addChildNode(labelNode)

                satellitesGroup.addChildNode(satNode)

                if mapState.showOrbits {
                    let orbitNode = createOrbitPath(for: sat)
                    orbitNode.name = orbitName
                    orbitPathsGroup.addChildNode(orbitNode)
                }

                if mapState.showGroundTracks && !sat.groundTrack.isEmpty {
                    let trackNode = createGroundTrack(for: sat)
                    trackNode.name = trackName
                    groundTracksGroup.addChildNode(trackNode)
                }
            }

            if let existing = satellitesGroup.childNode(withName: nodeName, recursively: false) {
                existing.geometry?.firstMaterial?.diffuse.contents = sat.isVisible ? NSColor.green : NSColor.yellow
                existing.geometry?.firstMaterial?.emission.contents = sat.isVisible ? NSColor.green : NSColor.yellow
            }

            if mapState.showOrbits {
                if orbitPathsGroup.childNode(withName: orbitName, recursively: false) == nil {
                    let orbitNode = createOrbitPath(for: sat)
                    orbitNode.name = orbitName
                    orbitPathsGroup.addChildNode(orbitNode)
                }
            } else {
                orbitPathsGroup.childNode(withName: orbitName, recursively: false)?.removeFromParentNode()
            }

            if mapState.showGroundTracks {
                if groundTracksGroup.childNode(withName: trackName, recursively: false) == nil && !sat.groundTrack.isEmpty {
                    let trackNode = createGroundTrack(for: sat)
                    trackNode.name = trackName
                    groundTracksGroup.addChildNode(trackNode)
                }
            } else {
                groundTracksGroup.childNode(withName: trackName, recursively: false)?.removeFromParentNode()
            }
        }

        for child in satellitesGroup.childNodes {
            if let name = child.name, name.hasPrefix("sat_") && !activeNames.contains(name) {
                child.removeFromParentNode()
                let satName = String(name.dropFirst(4))
                orbitPathsGroup.childNode(withName: "orbit_\(satName)", recursively: false)?.removeFromParentNode()
                groundTracksGroup.childNode(withName: "groundTrack_\(satName)", recursively: false)?.removeFromParentNode()
            }
        }
    }

    private func createOrbitPath(for satellite: SatelliteTrack) -> SCNNode {
        let segments = 256
        let alt: Float = 500.0
        let r: Float = 6.371 + alt / 1000.0
        var vertices: [SCNVector3] = []

        for i in 0...segments {
            let lonRad = Float(i) / Float(segments) * 2.0 * Float.pi
            vertices.append(SCNVector3(
                r * cos(lonRad),
                0,
                r * sin(lonRad)
            ))
        }

        let source = SCNGeometrySource(vertices: vertices)
        var indices: [Int32] = []
        for i in 0..<Int32(segments) {
            indices.append(i)
            indices.append(i + 1)
        }
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])

        let material = SCNMaterial()
        material.diffuse.contents = NSColor.cyan.withAlphaComponent(0.35)
        material.lightingModel = .constant
        material.isDoubleSided = true
        geometry.materials = [material]

        let orbitNode = SCNNode(geometry: geometry)

        let inclination: Float
        if !satellite.groundTrack.isEmpty {
            let maxLat = satellite.groundTrack.map { abs($0.latitude) }.max() ?? 51.6
            inclination = Float(min(maxLat + 2.0, 98.0)) * .pi / 180.0
        } else {
            inclination = 51.6 * .pi / 180.0
        }
        orbitNode.eulerAngles = SCNVector3(inclination, 0, 0)

        return orbitNode
    }

    private func createGroundTrack(for satellite: SatelliteTrack) -> SCNNode {
        guard !satellite.groundTrack.isEmpty else { return SCNNode() }

        let surfaceRadius: Float = 6.373
        var vertices: [SCNVector3] = []

        for coord in satellite.groundTrack {
            let pos = Self.calculateCartesianPosition(
                lat: coord.latitude,
                lon: coord.longitude,
                alt: 2.0
            )
            let normalized = normalize(pos, targetRadius: surfaceRadius)
            vertices.append(SCNVector3(normalized.x, normalized.y, normalized.z))
        }

        guard vertices.count >= 2 else { return SCNNode() }

        let source = SCNGeometrySource(vertices: vertices)
        var indices: [Int32] = []
        for i in 0..<Int32(vertices.count - 1) {
            indices.append(i)
            indices.append(i + 1)
        }
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])

        let material = SCNMaterial()
        material.diffuse.contents = NSColor.yellow.withAlphaComponent(0.6)
        material.lightingModel = .constant
        material.isDoubleSided = true
        geometry.materials = [material]

        return SCNNode(geometry: geometry)
    }

    private func normalize(_ v: SIMD3<Float>, targetRadius: Float) -> SIMD3<Float> {
        let len = length(v)
        guard len > 0 else { return v }
        return v / len * targetRadius
    }

    // MARK: - Label

    private func createLabelNode(text: String) -> SCNNode {
        let textGeometry = SCNText(string: text, extrusionDepth: 0.01)
        textGeometry.font = NSFont.systemFont(ofSize: 0.4)
        textGeometry.flatness = 0.1

        let textMaterial = SCNMaterial()
        textMaterial.diffuse.contents = NSColor.white
        textMaterial.lightingModel = .constant
        textMaterial.isDoubleSided = true
        textGeometry.materials = [textMaterial]

        let textNode = SCNNode(geometry: textGeometry)
        textNode.scale = SCNVector3(1, 1, 1)
        textNode.constraints = [SCNBillboardConstraint()]

        return textNode
    }

    // MARK: - Auto-Rotation

    public func startAutoRotation(in scnView: SCNView) {
        guard let cameraNode = scene.rootNode.childNode(withName: "cameraNode", recursively: true) else { return }

        let orbitNode = SCNNode()
        orbitNode.name = "cameraOrbitNode"
        scene.rootNode.addChildNode(orbitNode)

        let cameraHolder = SCNNode()
        cameraHolder.name = "cameraHolderNode"
        orbitNode.addChildNode(cameraHolder)

        cameraNode.removeFromParentNode()
        cameraNode.position = SCNVector3(x: 0, y: 5, z: 18)
        cameraHolder.addChildNode(cameraNode)

        let rotateAction = SCNAction.rotateBy(x: 0, y: CGFloat(Float.pi * 2), z: 0, duration: 120)
        let repeatAction = SCNAction.repeatForever(rotateAction)
        orbitNode.runAction(repeatAction)
    }

    private func stopAutoRotation() {
        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
            self.displayLink = nil
        }
    }
}
