////
////  BiometricEvaluator.swift
////  calisthenicsApp
////
////  Created by Nicholas Zambrano on 22/01/2026.
////
//
//import Foundation
//import MediaPipeTasksVision
//
//enum RiskLevel {
//    case low, medium, critical
//    
//    var color: String {
//        switch self {
//        case .low: return "green"
//        case .medium: return "orange"
//        case .critical: return "red"
//        }
//    }
//}
//
//class BiometricEvaluator {
//    // Math to find the angle at a joint (e.g., Elbow)
//    func calculateAngle(p1: NormalizedLandmark, p2: NormalizedLandmark, p3: NormalizedLandmark) -> Double {
//        let radians = atan2(Double(p3.y - p2.y), Double(p3.x - p2.x)) -
//                      atan2(Double(p1.y - p2.y), Double(p1.x - p2.x))
//        var angle = abs(radians * 180.0 / .pi)
//        if angle > 180.0 { angle = 360.0 - angle }
//        return angle
//    }
//    
//    // Check for "Hip Sag" (Injury Prevention)
//    func checkPushUpForm(shoulder: NormalizedLandmark, hip: NormalizedLandmark, ankle: NormalizedLandmark) -> RiskLevel {
//        // In a perfect pushup, these three form a 180-degree line
//        let alignment = calculateAngle(p1: shoulder, p2: hip, p3: ankle)
//        
//        if alignment < 140 { return .critical } // Major hip sag = high injury risk
//        if alignment < 160 { return .medium }   // Slight deviation
//        return .low                             // Good form
//    }
//    
//    // For Squats: Tracking Knee Stability and Depth
//    func checkSquatForm(hip: NormalizedLandmark, knee: NormalizedLandmark, ankle: NormalizedLandmark) -> RiskLevel {
//        let depthAngle = calculateAngle(p1: hip, p2: knee, p3: ankle)
//        
//        // Professional benchmark: Depth below 90 degrees is "Good"
//        if depthAngle < 90 { return .low }
//        if depthAngle < 120 { return .medium }
//        return .critical // "Critical" here means failed depth for a rep
//    }
//
//    // For Pull-Ups: Tracking Range of Motion
//    func checkPullUpForm(shoulder: NormalizedLandmark, elbow: NormalizedLandmark, wrist: NormalizedLandmark) -> RiskLevel {
//        let pullAngle = calculateAngle(p1: shoulder, p2: elbow, p3: wrist)
//        
//        // Chin above bar usually results in a sharp elbow angle (< 60°)
//        if pullAngle < 60 { return .low }
//        if pullAngle < 90 { return .medium }
//        return .critical // Failed to reach the top
//    }
//}


import Foundation
import MediaPipeTasksVision

enum RiskLevel {
    case low, medium, critical
    
    var color: String {
        switch self {
        case .low: return "green"
        case .medium: return "orange"
        case .critical: return "red"
        }
    }
}

class BiometricEvaluator {
    func calculateAngle(p1: NormalizedLandmark, p2: NormalizedLandmark, p3: NormalizedLandmark) -> Double {
        let radians = atan2(Double(p3.y - p2.y), Double(p3.x - p2.x)) -
                      atan2(Double(p1.y - p2.y), Double(p1.x - p2.x))
        var angle = abs(radians * 180.0 / .pi)
        if angle > 180.0 { angle = 360.0 - angle }
        return angle
    }
    
    func checkPushUpForm(angle: Double) -> RiskLevel {
        if angle < 155 { return .critical } // Major hip sag = high injury risk
        if angle < 165 { return .medium }   // Slight deviation
        return .low                             // Good form
    }
    
    func checkSquatForm(angle: Double) -> RiskLevel {
        if angle < 95 { return .low }
        if angle < 120 { return .medium }
        return .critical

    func checkPullUpForm(angle: Double) -> RiskLevel {
        if angle < 65 { return .low }
        if angle < 95 { return .medium }
        return .critical // Failed to reach the top
    }
}
