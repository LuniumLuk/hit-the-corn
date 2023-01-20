//
//  CornEntity.swift
//  HitTheCorn
//
//  Created by Ziyi Lu on 2022/12/31.
//

import Foundation
import RealityKit

class CornEntity {
    private var corn: Entity
    
    init() {
        let box = try! Experience.loadBox()
        corn = box.corn as! (Entity & HasPhysics)
        
        
        
    }
    
    public func show(within speed: Float) {
        
    }
    
    public func hide(within speed: Float) {
        
    }
}
