//
//  GameViewModel.swift
//  HitTheCorn
//
//  Created by Ziyi Lu on 2021/6/3.
//

import Foundation
import SwiftUI
import ARKit
import RealityKit

// MARK: Game Controller
class GameController: ObservableObject {
    public var arView: ARView = ARView(frame: .zero)
    
    public var score: Int = 0 {
        didSet {
            objectWillChange.send()
        }
    }
    public var level: Int = 0 {
        didSet {
            objectWillChange.send()
        }
    }
    
    private var timerCount: Int = 0
    
    private var lastCornAppear: Int = -1
    private var aliveCorn: [Int] = [0,1,2,3,4,5,6,7,8]
    private let pointsForNextLevel: [Int] = [40, 80, 160, 300, 500]
    private let speedForEachLevel: [Float] = [2.0, 1.5, 1.0, 0.8, 0.5]
    private let pointForEachLevel: [Int] = [10, 10, 15, 20, 25]
    private var timeTillNextAppear: Float = 0.0
    private var timeTillCurrentHide: Float = 0.0
    private var cornHiding: Bool = false
    private var cornRotateClockwise: Bool = false
    private var lastCornEntity: Entity? = nil
    // Audios
    private var popSound: AudioViewModel = AudioViewModel("Pop", withExtension: "aiff")
    private var pingSound: AudioViewModel = AudioViewModel("Ping", withExtension: "aiff")
    // Basic Data
    private var cornList: [Entity] = []
    private var currentSpeed: Float = 1.0
    private var panEntity: Entity
    
    init() {
        
        // Configure coachingOverlay
        let coachingOverlay = ARCoachingOverlayView(frame: arView.frame)
        coachingOverlay.translatesAutoresizingMaskIntoConstraints = false
        // add overlay to arView hierarchy
        arView.addSubview(coachingOverlay)
        // set layout constraints
        coachingOverlay.topAnchor.constraint(equalTo: arView.topAnchor).isActive = true
        coachingOverlay.leadingAnchor.constraint(equalTo: arView.leadingAnchor).isActive = true
        coachingOverlay.trailingAnchor.constraint(equalTo: arView.trailingAnchor).isActive = true
        coachingOverlay.bottomAnchor.constraint(equalTo: arView.bottomAnchor).isActive = true
        coachingOverlay.goal = .horizontalPlane
        coachingOverlay.session = arView.session
        
        // Load Pan Model Entity
        let box = try! Experience.loadBox()
        panEntity = box.pan!
        
        // MARK: Add gestureRecognizer
        let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapped))
        arView.addGestureRecognizer(gestureRecognizer)
        
        // MARK: Configure arView
        let config = ARWorldTrackingConfiguration()
        // Auto Focus
        config.isAutoFocusEnabled = true
        
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            config.frameSemantics.insert(.personSegmentationWithDepth)
        }
        arView.session.run(config)
        
        // anchor for a horizontal plane for minimum 40cm * 40cm
        let anchor = AnchorEntity(plane: .horizontal, minimumBounds: [0.4, 0.4])
        arView.scene.addAnchor(anchor)
        
        setupScene(anchor)
        
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            self.rotateCorns(in: 0.5)
        }
        
        Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) {
            timer in
            
            if (self.lastCornEntity != nil) {
                let dir = self.lastCornEntity!.transform.translation - self.arView.cameraTransform.translation
                self.popSound.audioPosition3D = AVAudio3DPoint(x: dir.x * 5, y: dir.y * 5, z: dir.z * 5)
                self.pingSound.audioPosition3D = AVAudio3DPoint(x: dir.x * 5, y: dir.y * 5, z: dir.z * 5)
            }
            
            if self.timeTillNextAppear < 0.0 {
                self.timeTillNextAppear = Float.random(in: 2...3) * self.currentSpeed
                let targetCornIndex = self.aliveCorn.randomElement()
                self.timeTillCurrentHide = self.currentSpeed
                self.cornHiding = false
                
                if let corn = self.arView.scene.findEntity(named: "Corn No.\(targetCornIndex ?? 0)") {
                    if corn.position.y > -0.2 {
                        corn.position.y = -0.2
                    }
                    let transform = Transform(scale: corn.transform.scale, rotation: corn.transform.rotation, translation: [0, 0.2, 0])
                    corn.move(to: transform, relativeTo: corn, duration: Double(self.currentSpeed / 2), timingFunction: .easeInOut)
                    self.popSound.playOrPause()
                    self.lastCornEntity = corn
                }
                self.lastCornAppear = targetCornIndex ?? 0
                
            }
            if self.timeTillCurrentHide < 0.0 && !self.cornHiding {
                if let corn = self.arView.scene.findEntity(named: "Corn No.\(self.lastCornAppear)") {
                    if corn.position.y < 0.0 {
                        corn.position.y = 0.0
                    }
                    self.cornHiding = true
                    let transform = Transform(scale: corn.transform.scale, rotation: corn.transform.rotation, translation: [0, -0.2, 0])
                    corn.move(to: transform, relativeTo: corn, duration: Double(self.currentSpeed / 2), timingFunction: .easeInOut)
                }
            }
            self.timeTillNextAppear -= 0.02
            self.timeTillCurrentHide -= 0.02
            self.timerCount += 1
        }
    }
    
    private func configureLevel() {
        if score >= pointsForNextLevel[level] {
            level += 1
            currentSpeed = speedForEachLevel[level]
        }
    }
    
    @objc func tapped(gesture: UITapGestureRecognizer) {
        // Get Hit Position
        let point = gesture.location(in: arView)
        print("Guesture Point Hit: \(point)")
        
        // Get Entity hit in arView
        if let hit = arView.entity(at: point) {
            print("Hit Entity Name: \(hit.name), current Corn: Corn No.\(lastCornAppear)")
            if hit.name == "Corn No.\(lastCornAppear)" {
                
                self.pingSound.playOrPause()
                
                score += self.pointForEachLevel[self.level]
                self.configureLevel()
                self.timeTillCurrentHide = 0.0
                
                // Make Pan Animation
                panEntity.position = hit.position + [0, 0.25, 0]
                panEntity.isEnabled = true
                panEntity.transform.rotation = simd_quatf(angle: 0, axis: [1,0,0])
                let translate = Transform(scale: [1,1,1], rotation: simd_quatf(angle: -.pi / 6, axis: [1,0,0]), translation: [0, -0.1, 0])
                panEntity.move(to: translate, relativeTo: panEntity, duration: 0.5, timingFunction: .easeInOut)
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                    self.panEntity.isEnabled = false
                }
            }
        }
        
        let results = arView.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal)
        if let result = results.first {
            print("Raycast results[0]: \(result.worldTransform)")
        }
    }
    
    func setupScene(_ anchor: AnchorEntity) {
        // Attach Occlusion Box
        let boxSize: Float = 1
        let boxMesh = MeshResource.generateBox(size: boxSize)
        let boxMaterial = OcclusionMaterial()
        let occlusionBox = ModelEntity(mesh: boxMesh, materials: [boxMaterial])
        occlusionBox.position = [0, -0.5, 0]
        anchor.addChild(occlusionBox)
        
        // Load Corn Model Entity
        let box = try! Experience.loadBox()
        
        let cornEntityTemplate = box.corn as! (Entity & HasPhysics)
        var cornEntities: [Entity] = []
        
        for _ in 1...9 {
            cornEntities.append(cornEntityTemplate.clone(recursive: true))
        }
        
        for (index, corn) in cornEntities.enumerated() {
            let x = Float(index % 3) - 1
            let z = Float(index / 3) - 1
            let collisionShape = ShapeResource.generateCapsule(height: 0.2, radius: 0.05)
                .offsetBy(translation: [0, 0.1, 0])
            corn.components.set(CollisionComponent(shapes: [collisionShape]))
            corn.position = [x * 0.15, -0.2, z * 0.15]
            corn.name = "Corn No.\(index)"
            cornList.append(corn)
            anchor.addChild(corn)
        }
        
        panEntity.isEnabled = false
        anchor.addChild(panEntity)
    }
    
    private func rotateCorns(in speed: Double) {
        for (_, corn) in cornList.enumerated() {
            if corn.children.count > 0 {
                let cornBody = corn.children[0]
                let cornEyes = corn.children[1]
                let rotateYaw: Float = cornRotateClockwise ? .pi / 4 : -.pi / 4
                let rotate = Transform(pitch: 0, yaw: rotateYaw, roll: 0)
                cornBody.move(to: rotate, relativeTo: cornBody, duration: speed, timingFunction: .easeInOut)
                cornEyes.move(to: rotate, relativeTo: cornEyes, duration: speed, timingFunction: .easeInOut)
                cornRotateClockwise.toggle()
            }
        }
    }
}

struct ARGameViewContainer: UIViewRepresentable {
    
    public let arView: ARView
    
    init(_ view: ARView) {
        arView = view
    }
    
    func makeUIView(context: Context) -> ARView {
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        
    }
}
