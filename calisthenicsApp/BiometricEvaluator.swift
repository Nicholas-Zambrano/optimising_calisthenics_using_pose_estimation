////
////  BiometricEvaluator.swift
////  calisthenicsApp
////
////  Created by Nicholas Zambrano on 22/01/2026.
////

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

enum PushUpPostureMode {
    case none, side, front
}

struct PushUpMetrics {
    let backAngle: Double
    let elbowFlexion: Double
    let elbowFlare: Double
}

class BiometricEvaluator {
    
    private func distance(_ a: NormalizedLandmark, _ b: NormalizedLandmark) -> Double {
        let dx = Double(a.x - b.x)
        let dy = Double(a.y - b.y)
        return sqrt(dx * dx + dy * dy)
    }
    
    func calculateAngle(p1: NormalizedLandmark, p2: NormalizedLandmark, p3: NormalizedLandmark) -> Double {
        let radians = atan2(Double(p3.y - p2.y), Double(p3.x - p2.x)) -
                      atan2(Double(p1.y - p2.y), Double(p1.x - p2.x))
        var angle = abs(radians * 180.0 / .pi)
        if angle > 180.0 { angle = 360.0 - angle }
        return angle
    }

    func pushUpPostureMode(shoulder: NormalizedLandmark,
                           wrist: NormalizedLandmark,
                           hip: NormalizedLandmark,
                           knee: NormalizedLandmark,
                           ankle: NormalizedLandmark,
                           minVisibility: Float = 0.45) -> PushUpPostureMode {
        let shoulderVis = shoulder.visibility?.floatValue ?? 1.0
        let wristVis = wrist.visibility?.floatValue ?? 1.0
        let hipVis = hip.visibility?.floatValue ?? 1.0
        let ankleVis = ankle.visibility?.floatValue ?? 1.0
        let kneeVis = knee.visibility?.floatValue ?? 1.0
        
        if shoulderVis < minVisibility ||
            wristVis < minVisibility ||
            hipVis < minVisibility {
            return .none
        }
        
        let torso = distance(shoulder, hip)
        if torso < 0.02 { return .none }
        
        let leg = (ankleVis >= minVisibility) ? distance(hip, ankle) : distance(hip, knee)
        if leg < 0.02 { return .none }
        
        let shoulderHipY = abs(Double(shoulder.y - hip.y))
        let hipAnkleY = (ankleVis >= minVisibility) ? abs(Double(hip.y - ankle.y)) : abs(Double(hip.y - knee.y))
        
        let torsoHorizontal = shoulderHipY < 0.55 * torso
        let legHorizontal = hipAnkleY < 0.55 * leg
        
        let wristBelowShoulder = Double(wrist.y) > Double(shoulder.y) - 0.1

        let hipBelowShoulder = Double(hip.y) > Double(shoulder.y) - 0.05
        let ankleBelowHip = (ankleVis >= minVisibility) ? (Double(ankle.y) > Double(hip.y) - 0.05) : (Double(knee.y) > Double(hip.y) - 0.05)
        let frontViewStack = wristBelowShoulder && hipBelowShoulder && ankleBelowHip
        
        if torsoHorizontal && legHorizontal && wristBelowShoulder { return .side }
        if frontViewStack { return .front }
        return .none
    }

    
    func evaluatePushUp(shoulder: NormalizedLandmark,
                        elbow: NormalizedLandmark,
                        wrist: NormalizedLandmark,
                        hip: NormalizedLandmark,
                        ankle: NormalizedLandmark,
                        checkElbowFlare: Bool,
                        checkBackAngle: Bool) -> (RiskLevel, String, Double) {
        
        let metrics = computePushUpMetrics(
            shoulder: shoulder,
            elbow: elbow,
            wrist: wrist,
            hip: hip,
            ankle: ankle
        )
        let backAngle = metrics.backAngle
        let elbowFlexion = metrics.elbowFlexion
        let elbowFlare = metrics.elbowFlare

        if checkBackAngle && backAngle < 155 {
            return (.critical, "FIX HIP SAG", elbowFlexion)
        }
        if checkElbowFlare && elbowFlare > 75 {
            return (.critical, "TUCK ELBOWS", elbowFlexion)
        }
        
        if backAngle < 165 { return (.medium, "Keep core tighter", elbowFlexion) }
        
        return (.low, "Form is Good", elbowFlexion)
    }
    
    func checkSquatForm(angle: Double) -> RiskLevel {
        if angle < 95 { return .low }
        if angle < 120 { return .medium }
        return .critical
    }

    func checkPullUpForm(angle: Double) -> RiskLevel {
        if angle < 65 { return .low }
        if angle < 95 { return .medium }
        return .critical
    }
    
    func computePushUpMetrics(shoulder: NormalizedLandmark,
                              elbow: NormalizedLandmark,
                              wrist: NormalizedLandmark,
                              hip: NormalizedLandmark,
                              ankle: NormalizedLandmark) -> PushUpMetrics {
        let backAngle = calculateAngle(p1: shoulder, p2: hip, p3: ankle)
        let elbowFlexion = calculateAngle(p1: shoulder, p2: elbow, p3: wrist)
        let elbowFlare = calculateAngle(p1: hip, p2: shoulder, p3: elbow)
        return PushUpMetrics(backAngle: backAngle, elbowFlexion: elbowFlexion, elbowFlare: elbowFlare)
    }
}
