import SwiftUI

enum FeedbackSensitivity: String, CaseIterable {
    case relaxed = "Relaxed"
    case normal = "Normal"
    case strict = "Strict"
    
    var yellowMultiplier: Double {
        switch self {
        case .relaxed: return 1.30
        case .normal: return 1.20
        case .strict: return 1.10
        }
    }
    
    var redMultiplier: Double {
        switch self {
        case .relaxed: return 1.50
        case .normal: return 1.35
        case .strict: return 1.20
        }
    }
}

enum FeedbackFocus: String, CaseIterable {
    case armsOnly = "Front View"
    case fullBody = "Side View"
}

struct SessionSummary {
    let totalReps: Int
    let averageScore: Int
    let cleanReps: Int
    let bestRep: Int
    let worstRep: Int
    let mostCommonIssueMessage: String?
}

struct OverlayColors {
    var leftArm: Color
    var rightArm: Color
    var torso: Color
    var leftLeg: Color
    var rightLeg: Color
    var hasCritical: Bool = false
    
    static let neutral = OverlayColors(
        leftArm: .white.opacity(0.6),
        rightArm: .white.opacity(0.6),
        torso: .white.opacity(0.6),
        leftLeg: .white.opacity(0.6),
        rightLeg: .white.opacity(0.6)
    )
}

struct RepMetric: Identifiable {
    let id = UUID()
    let repIndex: Int
    let timestampMS: Int
    let score: Int
    let primaryMessage: String
    let risk: RiskLevel
    let depthProgress: Double
    let kneeValgus: Double?
    let forwardLean: Double?
}

struct FrontViewMetrics {
    let hipDropRatio: Double
    let hipRiseRatio: Double
    let elbowFlareRatio: Double
    let shoulderAsym: Double
    let hipAsym: Double
    let hipsVisible: Bool
    let anklesVisible: Bool
    let armsVisible: Bool
}
