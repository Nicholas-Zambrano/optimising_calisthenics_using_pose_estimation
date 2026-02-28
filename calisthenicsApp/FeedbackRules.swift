import SwiftUI

enum IssueSeverity {
    case critical, important, minor
}

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
    case armsOnly = "Arms Only"
    case fullBody = "Full Body"
}

enum FormIssue: String {
    case hipSagCritical
    case elbowFlareCritical
    case hipSag
    case elbowFlare
    case shallowDepth
    case tooFast
    case asymmetryCritical
    case asymmetry
    case hipsNotVisible
    case armsNotVisible
    
    var severity: IssueSeverity {
        switch self {
        case .hipSagCritical, .elbowFlareCritical, .asymmetryCritical:
            return .critical
        case .hipSag, .elbowFlare, .shallowDepth, .tooFast, .asymmetry, .hipsNotVisible, .armsNotVisible:
            return .important
        }
    }
    
    var message: String {
        switch self {
        case .hipSagCritical, .hipSag:
            return "Lift hips, keep body straight"
        case .elbowFlareCritical, .elbowFlare:
            return "Tuck elbows in"
        case .shallowDepth:
            return "Go deeper next rep"
        case .tooFast:
            return "Slow down the tempo"
        case .asymmetryCritical, .asymmetry:
            return "Press evenly through both hands"
        case .hipsNotVisible:
            return "Hips not visible — step back or lower camera"
        case .armsNotVisible:
            return "Arms not visible — move closer to camera"
        }
    }
    
    var label: String {
        switch severity {
        case .critical: return "CRITICAL"
        case .important: return "IMPORTANT"
        case .minor: return "MINOR"
        }
    }
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
    
    static let neutral = OverlayColors(
        leftArm: .white.opacity(0.6),
        rightArm: .white.opacity(0.6),
        torso: .white.opacity(0.6),
        leftLeg: .white.opacity(0.6),
        rightLeg: .white.opacity(0.6)
    )
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
