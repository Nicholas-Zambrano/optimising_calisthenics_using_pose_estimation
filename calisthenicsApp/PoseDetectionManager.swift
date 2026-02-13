import MediaPipeTasksVision
import AVFoundation
import SwiftUI
import Combine

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

enum FormIssue: String {
    case hipSagCritical
    case elbowFlareCritical
    case hipSag
    case elbowFlare
    case shallowDepth
    case tooFast
    
    var severity: IssueSeverity {
        switch self {
        case .hipSagCritical, .elbowFlareCritical:
            return .critical
        case .hipSag, .elbowFlare, .shallowDepth, .tooFast:
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
    let mostCommonIssue: FormIssue?
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
    let elbowFlareRatio: Double
}

class PoseDetectionManager: NSObject, PoseLandmarkerLiveStreamDelegate, ObservableObject {
    nonisolated(unsafe) var poseLandmarker: PoseLandmarker?
    
    @Published var session = AVCaptureSession()
    @Published var latestLandmarks: [NormalizedLandmark]?
    @Published var currentRisk: RiskLevel = .low
    @Published var feedbackMessage: String = "Searching..."
    @Published var activeExercise: String = "Push-Up"
    @Published var cameraPosition: AVCaptureDevice.Position = .front
    @Published var isDetectionPaused: Bool = true
    @Published var isCoachingActive: Bool = false
    
    @Published var repCount = 0
    @Published var cleanReps = 0
    @Published var targetReps = 10
    @Published var overallScore: Int = 0
    @Published var depthProgress: Double = 0.0
    @Published var isSessionComplete: Bool = false
    @Published var sessionSummary: SessionSummary?
    @Published var overlayColors = OverlayColors.neutral
    @Published var debugText: String = ""
    @Published var secondaryHint: String = ""
    @Published var sensitivity: FeedbackSensitivity = .normal
    @Published var lastRepScore: Int = 0
    
    private var pushUpState: String = "UP"
    private var currentRepHasError = false
    var isProcessingFrame = false
    
    let evaluator = BiometricEvaluator()
    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpokenMessage = ""
    private var riskBuffer: [RiskLevel] = []
    
    private var angleBuffer: [Double] = []
    private let maxBufferSize = 10
    
    private var lastTimestampMS: Int?
    private var elbowAngleEMA: Double?
    private var elbowVelocityEMA: Double?
    private var lastElbowAngle: Double?
    private var belowDepthStartMS: Int?
    private var aboveLockoutStartMS: Int?
    private var lastDebugLogMS: Int?
    private let enablePoseDebugLogs = true
    private var lastPoseMode: PushUpPostureMode = .none
    private var lastPoseModeTimestampMS: Int?
    private var inRep = false
    private var criticalStreak = 0
    private let criticalStreakThreshold = 3
    private var isArmed = false
    private var lockoutHoldStartMS: Int?
    private var repMinElbowAngle: Double = 999
    private var repMaxElbowAngle: Double = 0
    private var repMinBackAngle: Double = 999
    private var repMaxElbowFlare: Double = 0
    private var repMaxHipDropRatio: Double = 0
    private var repMaxElbowFlareRatio: Double = 0
    private var repStartMS: Int?
    private var repEndMS: Int?
    private var repScores: [Int] = []
    private var issueCounts: [FormIssue: Int] = [:]
    private var lastRepFeedbackMessage: String = ""
    private var calibrationMinElbow: Double?
    private var calibrationMaxElbow: Double?
    private var calibrationRepCount = 0
    private let calibrationReps = 2
    private var calibrationHipDrop: Double?
    private var calibrationElbowFlareRatio: Double?

    private func chooseBestSide(landmarks: [NormalizedLandmark]) -> (shoulder: NormalizedLandmark, elbow: NormalizedLandmark, wrist: NormalizedLandmark, hip: NormalizedLandmark, knee: NormalizedLandmark, ankle: NormalizedLandmark) {
        let left = (landmarks[11], landmarks[13], landmarks[15], landmarks[23], landmarks[25], landmarks[27])
        let right = (landmarks[12], landmarks[14], landmarks[16], landmarks[24], landmarks[26], landmarks[28])
        
        func avgVis(_ side: (NormalizedLandmark, NormalizedLandmark, NormalizedLandmark, NormalizedLandmark, NormalizedLandmark, NormalizedLandmark)) -> Float {
            let values: [Float] = [
                side.0.visibility?.floatValue ?? 0.0,
                side.1.visibility?.floatValue ?? 0.0,
                side.2.visibility?.floatValue ?? 0.0,
                side.3.visibility?.floatValue ?? 0.0,
                side.4.visibility?.floatValue ?? 0.0,
                side.5.visibility?.floatValue ?? 0.0
            ]
            return values.reduce(0, +) / Float(values.count)
        }
        
        return avgVis(left) >= avgVis(right) ? left : right
    }

    private func logPushUpDebug(timestampMS: Int,
                                sideLabel: String,
                                postureMode: PushUpPostureMode,
                                elbowAngleRaw: Double,
                                elbowAngleSmoothed: Double?,
                                elbowVelocity: Double?,
                                currentRisk: RiskLevel,
                                shoulder: NormalizedLandmark,
                                wrist: NormalizedLandmark,
                                hip: NormalizedLandmark,
                                ankle: NormalizedLandmark) {
        guard enablePoseDebugLogs else { return }
        if let last = lastDebugLogMS, (timestampMS - last) < 250 { return }
        lastDebugLogMS = timestampMS

        let shoulderVis = shoulder.visibility?.floatValue ?? 0
        let wristVis = wrist.visibility?.floatValue ?? 0
        let hipVis = hip.visibility?.floatValue ?? 0
        let ankleVis = ankle.visibility?.floatValue ?? 0

        print("""
        [PushUpDebug] side=\(sideLabel) mode=\(postureMode) state=\(pushUpState) reps=\(repCount)
          elbowRaw=\(String(format: "%.1f", elbowAngleRaw)) elbowEMA=\(String(format: "%.1f", elbowAngleSmoothed ?? -1)) vel=\(String(format: "%.1f", elbowVelocity ?? 0))
          vis S/W/H/A=\(String(format: "%.2f", shoulderVis))/\(String(format: "%.2f", wristVis))/\(String(format: "%.2f", hipVis))/\(String(format: "%.2f", ankleVis))
          y S/W/H/A=\(String(format: "%.2f", shoulder.y))/\(String(format: "%.2f", wrist.y))/\(String(format: "%.2f", hip.y))/\(String(format: "%.2f", ankle.y))
          risk=\(currentRisk)
        """)
    }
    
    override init() {
        super.init()
        configureAudioSession()
        setupLandmarker()
    }
    
    func resetForNewSession(targetReps: Int, sensitivity: FeedbackSensitivity) {
        self.targetReps = targetReps
        self.sensitivity = sensitivity
        repCount = 0
        cleanReps = 0
        overallScore = 0
        lastRepScore = 0
        repScores = []
        issueCounts = [:]
        feedbackMessage = "Get into push-up position"
        currentRisk = .low
        isSessionComplete = false
        sessionSummary = nil
        depthProgress = 0
        overlayColors = .neutral
        pushUpState = "UP"
        isDetectionPaused = false
        resetRepMetrics()
        calibrationMinElbow = nil
        calibrationMaxElbow = nil
        calibrationRepCount = 0
        calibrationHipDrop = nil
        calibrationElbowFlareRatio = nil
        secondaryHint = ""
    }
    
    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, options: [.duckOthers, .mixWithOthers])
            try audioSession.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }
    
    private func endSession() {
        isDetectionPaused = true
        DispatchQueue.global(qos: .userInitiated).async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }
    
    // MARK: - Core Logic & Scoring
    
    private func calculateOverallScore() {
        guard repCount > 0 else { return }
        let avg = repScores.reduce(0, +) / max(repScores.count, 1)
        overallScore = avg
    }
    
    private func getSmoothedAngle(newAngle: Double) -> Double {
        angleBuffer.append(newAngle)
        if angleBuffer.count > maxBufferSize { angleBuffer.removeFirst() }
        return angleBuffer.reduce(0, +) / Double(angleBuffer.count)
    }

    private func emaFilter(previous: Double?, value: Double, dtSeconds: Double, tau: Double) -> Double {
        guard let previous = previous else { return value }
        let alpha = 1.0 - exp(-dtSeconds / tau)
        return (alpha * value) + ((1.0 - alpha) * previous)
    }

    private func resetRepMetrics() {
        repMinElbowAngle = 999
        repMaxElbowAngle = 0
        repMinBackAngle = 999
        repMaxElbowFlare = 0
        repMaxHipDropRatio = 0
        repMaxElbowFlareRatio = 0
        repStartMS = nil
        repEndMS = nil
        criticalStreak = 0
        currentRepHasError = false
        isArmed = false
        lockoutHoldStartMS = nil
    }

    private func updateRepMetrics(metrics: PushUpMetrics, frontMetrics: FrontViewMetrics?) {
        repMinElbowAngle = min(repMinElbowAngle, metrics.elbowFlexion)
        repMaxElbowAngle = max(repMaxElbowAngle, metrics.elbowFlexion)
        repMinBackAngle = min(repMinBackAngle, metrics.backAngle)
        repMaxElbowFlare = max(repMaxElbowFlare, metrics.elbowFlare)
        if let front = frontMetrics {
            repMaxHipDropRatio = max(repMaxHipDropRatio, front.hipDropRatio)
            repMaxElbowFlareRatio = max(repMaxElbowFlareRatio, front.elbowFlareRatio)
        }
    }

    private static func scoreForIssues(_ issues: [FormIssue]) -> Int {
        var score = 100
        for issue in issues {
            switch issue.severity {
            case .critical: score -= 35
            case .important: score -= 15
            case .minor: score -= 5
            }
        }
        return max(0, min(100, score))
    }

    private func scoreFrontViewRep() -> Int {
        let hipBase = calibrationHipDrop ?? 0.18
        let flareBase = calibrationElbowFlareRatio ?? 0.5
        let depthBase = calibrationMinElbow ?? 110.0
        let maxDepth = calibrationMaxElbow ?? 165.0

        let hipExcess = max(0.0, (repMaxHipDropRatio - hipBase) / max(0.001, hipBase))
        let flareExcess = max(0.0, (repMaxElbowFlareRatio - flareBase) / max(0.001, flareBase))
        let depthDeficit = max(0.0, (repMinElbowAngle - depthBase) / max(1.0, maxDepth - depthBase))

        let hipPenalty = min(40.0, hipExcess * 60.0)
        let flarePenalty = min(30.0, flareExcess * 50.0)
        let depthPenalty = min(30.0, depthDeficit * 60.0)

        let score = 100.0 - hipPenalty - flarePenalty - depthPenalty
        return max(0, min(100, Int(score.rounded())))
    }

    private static func messageForIssues(_ issues: [FormIssue]) -> String {
        if issues.isEmpty { return "GOOD: Form is clean" }
        if let critical = issues.first(where: { $0.severity == .critical }) {
            return "\(critical.label): \(critical.message)"
        }
        if let important = issues.first(where: { $0.severity == .important }) {
            return "\(important.label): \(important.message)"
        }
        if let minor = issues.first(where: { $0.severity == .minor }) {
            return "\(minor.label): \(minor.message)"
        }
        return "GOOD: Form is clean"
    }
    
    private static func secondaryMessageForIssues(_ issues: [FormIssue]) -> String {
        let primary = messageForIssues(issues)
        let secondary = issues.first(where: { !primary.contains($0.message) })
        if let sec = secondary {
            return "Also: \(sec.message)"
        }
        return ""
    }

    private static func colorsFor(metrics: PushUpMetrics, postureMode: PushUpPostureMode) -> OverlayColors {
        var colors = OverlayColors.neutral
        
        if postureMode == .side {
            if metrics.backAngle < 155 {
                colors.torso = .red
            } else if metrics.backAngle < 165 {
                colors.torso = .yellow
            } else {
                colors.torso = .green
            }
            
            if metrics.elbowFlare > 75 {
                colors.leftArm = .red
                colors.rightArm = .red
            } else if metrics.elbowFlare > 60 {
                colors.leftArm = .yellow
                colors.rightArm = .yellow
            } else {
                colors.leftArm = .green
                colors.rightArm = .green
            }
        }
        
        return colors
    }

    private func colorsFor(metrics: PushUpMetrics, frontMetrics: FrontViewMetrics?, postureMode: PushUpPostureMode) -> OverlayColors {
        var colors = OverlayColors.neutral
        
        if postureMode == .side {
            if metrics.backAngle < 155 {
                colors.torso = .red
            } else if metrics.backAngle < 165 {
                colors.torso = .yellow
            } else {
                colors.torso = .green
            }
            
            if metrics.elbowFlare > 75 {
                colors.leftArm = .red
                colors.rightArm = .red
            } else if metrics.elbowFlare > 60 {
                colors.leftArm = .yellow
                colors.rightArm = .yellow
            } else {
                colors.leftArm = .green
                colors.rightArm = .green
            }
        } else if postureMode == .front {
            if let front = frontMetrics {
                let hipBase = calibrationHipDrop ?? 0.18
                let flareBase = calibrationElbowFlareRatio ?? 0.5
                let hipYellow = hipBase * sensitivity.yellowMultiplier
                let hipRed = hipBase * sensitivity.redMultiplier
                let flareYellow = flareBase * sensitivity.yellowMultiplier
                let flareRed = flareBase * sensitivity.redMultiplier
                
                if front.elbowFlareRatio > flareRed {
                    colors.leftArm = .red
                    colors.rightArm = .red
                } else if front.elbowFlareRatio > flareYellow {
                    colors.leftArm = .yellow
                    colors.rightArm = .yellow
                } else {
                    colors.leftArm = .green
                    colors.rightArm = .green
                }
                
                if front.hipDropRatio > hipRed {
                    colors.torso = .red
                } else if front.hipDropRatio > hipYellow {
                    colors.torso = .yellow
                } else {
                    colors.torso = .green
                }
            }
        }
        
        return colors
    }

    private static func depthProgressFor(currentAngle: Double, minAngle: Double, maxAngle: Double) -> Double {
        if maxAngle <= minAngle { return 0 }
        let progress = (maxAngle - currentAngle) / (maxAngle - minAngle)
        return max(0.0, min(1.0, progress))
    }

    private func finalizeRep(postureMode: PushUpPostureMode, timestampMS: Int) {
        repEndMS = timestampMS
        let durationMS = (repStartMS != nil && repEndMS != nil) ? max(1, (repEndMS! - repStartMS!)) : 1
        let durationSec = Double(durationMS) / 1000.0
        
        var issues: [FormIssue] = []
        let depthThreshold = (postureMode == .front) ? 110.0 : 100.0
        
        if postureMode == .side {
            if repMinBackAngle < 155 { issues.append(.hipSagCritical) }
            else if repMinBackAngle < 165 { issues.append(.hipSag) }
            
            if repMaxElbowFlare > 75 { issues.append(.elbowFlareCritical) }
            else if repMaxElbowFlare > 60 { issues.append(.elbowFlare) }
        } else if postureMode == .front {
            let hipBase = calibrationHipDrop ?? 0.18
            let flareBase = calibrationElbowFlareRatio ?? 0.5
            let hipYellow = hipBase * sensitivity.yellowMultiplier
            let hipRed = hipBase * sensitivity.redMultiplier
            let flareYellow = flareBase * sensitivity.yellowMultiplier
            let flareRed = flareBase * sensitivity.redMultiplier
            
            if repMaxHipDropRatio > hipRed { issues.append(.hipSagCritical) }
            else if repMaxHipDropRatio > hipYellow { issues.append(.hipSag) }
            
            if repMaxElbowFlareRatio > flareRed { issues.append(.elbowFlareCritical) }
            else if repMaxElbowFlareRatio > flareYellow { issues.append(.elbowFlare) }
        }
        
        if repMinElbowAngle > depthThreshold { issues.append(.shallowDepth) }
        if durationSec < 0.6 { issues.append(.tooFast) }
        
        let repScore = (postureMode == .front) ? scoreFrontViewRep() : Self.scoreForIssues(issues)
        repScores.append(repScore)
        lastRepScore = repScore
        for issue in issues {
            issueCounts[issue, default: 0] += 1
        }
        
        if !issues.contains(where: { $0.severity == .critical }) {
            cleanReps += 1
        }
        
        calculateOverallScore()
        let message = Self.messageForIssues(issues)
        let secondary = Self.secondaryMessageForIssues(issues)
        if message != lastRepFeedbackMessage {
            feedbackMessage = message
            lastRepFeedbackMessage = message
            currentRisk = issues.contains(where: { $0.severity == .critical }) ? .critical :
                (issues.contains(where: { $0.severity == .important }) ? .medium :
                    (issues.contains(where: { $0.severity == .minor }) ? .low : .low))
        }
        secondaryHint = secondary
        
        if isCoachingActive {
            let spoken = "Rep \(repCount). \(message)"
            speakFeedback(spoken, force: true)
        }
        
        if repCount >= targetReps {
            isSessionComplete = true
            sessionSummary = SessionSummary(
                totalReps: repCount,
                averageScore: overallScore,
                cleanReps: cleanReps,
                bestRep: repScores.max() ?? 0,
                worstRep: repScores.min() ?? 0,
                mostCommonIssue: issueCounts.max(by: { $0.value < $1.value })?.key
            )
            endSession()
        }
        
        if calibrationRepCount < calibrationReps {
            calibrationMinElbow = min(calibrationMinElbow ?? repMinElbowAngle, repMinElbowAngle)
            calibrationMaxElbow = max(calibrationMaxElbow ?? repMaxElbowAngle, repMaxElbowAngle)
            calibrationHipDrop = max(calibrationHipDrop ?? repMaxHipDropRatio, repMaxHipDropRatio)
            calibrationElbowFlareRatio = max(calibrationElbowFlareRatio ?? repMaxElbowFlareRatio, repMaxElbowFlareRatio)
            calibrationRepCount += 1
        }
    }

    private func handlePushUpRep(elbowAngleRaw: Double,
                                 timestampMS: Int,
                                 postureMode: PushUpPostureMode,
                                 currentRisk: RiskLevel) {
        if isSessionComplete { return }
        let isInPushUpPose = postureMode != .none
        guard isInPushUpPose else { return }
        
        let dtSeconds: Double
        if let last = lastTimestampMS {
            dtSeconds = max(0.001, Double(timestampMS - last) / 1000.0)
        } else {
            dtSeconds = 0.033
        }
        lastTimestampMS = timestampMS
        
        let smoothedAngle = emaFilter(previous: elbowAngleEMA, value: elbowAngleRaw, dtSeconds: dtSeconds, tau: 0.08)
        elbowAngleEMA = smoothedAngle
        
        let velocity: Double
        if let lastAngle = lastElbowAngle {
            velocity = (smoothedAngle - lastAngle) / dtSeconds
        } else {
            velocity = 0.0
        }
        lastElbowAngle = smoothedAngle
        elbowVelocityEMA = emaFilter(previous: elbowVelocityEMA, value: velocity, dtSeconds: dtSeconds, tau: 0.12)
        let v = elbowVelocityEMA ?? 0.0
        
        let depthAngle = (postureMode == .front) ? 120.0 : 95.0
        let lockoutAngle = (postureMode == .front) ? 145.0 : 165.0
        let minDownVelocity = (postureMode == .front) ? -1.0 : -20.0
        let minUpVelocity = (postureMode == .front) ? 1.0 : 20.0
        let dwellMS = (postureMode == .front) ? 40 : 80
        
        if pushUpState == "UP" {
            // Arm the rep counter only after a brief lockout hold to avoid false starts.
            if smoothedAngle > lockoutAngle {
                if lockoutHoldStartMS == nil { lockoutHoldStartMS = timestampMS }
                if let start = lockoutHoldStartMS, (timestampMS - start) >= 300 {
                    isArmed = true
                }
            } else {
                lockoutHoldStartMS = nil
            }
            
            if smoothedAngle < depthAngle && v < minDownVelocity {
                if belowDepthStartMS == nil { belowDepthStartMS = timestampMS }
                if let start = belowDepthStartMS, (timestampMS - start) >= dwellMS {
                    if isArmed {
                        pushUpState = "DOWN"
                        aboveLockoutStartMS = nil
                        inRep = true
                        resetRepMetrics()
                        repStartMS = timestampMS
                    }
                }
            } else {
                belowDepthStartMS = nil
            }
        } else {
            if smoothedAngle > lockoutAngle && v > minUpVelocity {
                if aboveLockoutStartMS == nil { aboveLockoutStartMS = timestampMS }
                if let start = aboveLockoutStartMS, (timestampMS - start) >= dwellMS {
                    pushUpState = "UP"
                    repCount += 1
                    inRep = false
                    finalizeRep(postureMode: postureMode, timestampMS: timestampMS)
                    belowDepthStartMS = nil
                }
            } else {
                aboveLockoutStartMS = nil
            }
        }
        
        if inRep {
            if currentRisk == .critical {
                criticalStreak += 1
                if criticalStreak >= criticalStreakThreshold {
                    currentRepHasError = true
                }
            } else {
                criticalStreak = 0
            }
        }
    }

    
    func poseLandmarker(_ poseLandmarker: PoseLandmarker, didFinishDetection result: PoseLandmarkerResult?, timestampInMilliseconds: Int, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            defer { self.isProcessingFrame = false }

            guard let landmarks = result?.landmarks.first else {
                self.latestLandmarks = nil
                self.feedbackMessage = "Searching..."
                return
            }

            self.latestLandmarks = landmarks
            var rawRisk: RiskLevel = .low
            var displayMessage: String = ""

            switch self.activeExercise {
            case "Push-Up":
                let leftSide = (landmarks[11], landmarks[13], landmarks[15], landmarks[23], landmarks[25], landmarks[27])
                let rightSide = (landmarks[12], landmarks[14], landmarks[16], landmarks[24], landmarks[26], landmarks[28])
                let side = chooseBestSide(landmarks: landmarks)
                let sideLabel: String
                if side.0.x == leftSide.0.x && side.1.x == leftSide.1.x { sideLabel = "L" } else { sideLabel = "R" }
                let shoulder = side.shoulder
                let elbow = side.elbow
                let wrist = side.wrist
                let hip = side.hip
                let knee = side.knee
                let ankle = side.ankle
                
                let postureMode = self.evaluator.pushUpPostureMode(
                    shoulder: shoulder,
                    wrist: wrist,
                    hip: hip,
                    knee: knee,
                    ankle: ankle
                )
                
                let effectivePostureMode: PushUpPostureMode
                if postureMode != .none {
                    effectivePostureMode = postureMode
                    lastPoseMode = postureMode
                    lastPoseModeTimestampMS = timestampInMilliseconds
                } else if let lastTS = lastPoseModeTimestampMS,
                          (timestampInMilliseconds - lastTS) <= 800 {
                    effectivePostureMode = lastPoseMode
                } else {
                    effectivePostureMode = .none
                }
                
                if effectivePostureMode == .none {
                    rawRisk = .low
                    displayMessage = "Get into push-up position"
                    if feedbackMessage != displayMessage {
                        feedbackMessage = displayMessage
                        currentRisk = .low
                    }
                    if let lastTS = lastPoseModeTimestampMS, (timestampInMilliseconds - lastTS) > 800 {
                        pushUpState = "UP"
                        belowDepthStartMS = nil
                        aboveLockoutStartMS = nil
                        currentRepHasError = false
                        lastTimestampMS = timestampInMilliseconds
                        lastElbowAngle = nil
                        elbowAngleEMA = nil
                        elbowVelocityEMA = nil
                    }
                    self.handlePushUpRep(elbowAngleRaw: 180, timestampMS: timestampInMilliseconds, postureMode: .none, currentRisk: rawRisk)
                    self.logPushUpDebug(
                        timestampMS: timestampInMilliseconds,
                        sideLabel: sideLabel,
                        postureMode: .none,
                        elbowAngleRaw: 180,
                        elbowAngleSmoothed: self.elbowAngleEMA,
                        elbowVelocity: self.elbowVelocityEMA,
                        currentRisk: rawRisk,
                        shoulder: shoulder,
                        wrist: wrist,
                        hip: hip,
                        ankle: ankle
                    )
                } else {
                    let metrics = self.evaluator.computePushUpMetrics(
                        shoulder: shoulder,
                        elbow: elbow,
                        wrist: wrist,
                        hip: hip,
                        ankle: ankle
                    )
                    
                    let leftShoulder = landmarks[11]
                    let rightShoulder = landmarks[12]
                    let leftHip = landmarks[23]
                    let rightHip = landmarks[24]
                    let shoulderMid = NormalizedLandmark(
                        x: (leftShoulder.x + rightShoulder.x) / 2,
                        y: (leftShoulder.y + rightShoulder.y) / 2,
                        z: (leftShoulder.z + rightShoulder.z) / 2,
                        visibility: nil,
                        presence: nil
                    )
                    let hipMid = NormalizedLandmark(
                        x: (leftHip.x + rightHip.x) / 2,
                        y: (leftHip.y + rightHip.y) / 2,
                        z: (leftHip.z + rightHip.z) / 2,
                        visibility: nil,
                        presence: nil
                    )
                    let shoulderWidth = max(0.001, abs(Double(leftShoulder.x - rightShoulder.x)))
                    let torsoLength = max(0.001, sqrt(pow(Double(shoulderMid.x - hipMid.x), 2) + pow(Double(shoulderMid.y - hipMid.y), 2)))
                    let hipDropRatio = max(0.0, (Double(hipMid.y - shoulderMid.y)) / torsoLength)
                    let elbowFlareRatio = min(1.0, abs(Double(wrist.x - shoulder.x)) / shoulderWidth)
                    let frontMetrics = FrontViewMetrics(hipDropRatio: hipDropRatio, elbowFlareRatio: elbowFlareRatio)
                    
                    let evaluation = self.evaluator.evaluatePushUp(
                        shoulder: shoulder,
                        elbow: elbow,
                        wrist: wrist,
                        hip: hip,
                        ankle: ankle,
                        checkElbowFlare: effectivePostureMode == .side,
                        checkBackAngle: effectivePostureMode == .side
                    )
                    rawRisk = evaluation.0
                    displayMessage = evaluation.1
                    updateRepMetrics(metrics: metrics, frontMetrics: frontMetrics)
                    self.handlePushUpRep(elbowAngleRaw: metrics.elbowFlexion, timestampMS: timestampInMilliseconds, postureMode: effectivePostureMode, currentRisk: rawRisk)
                    self.overlayColors = self.colorsFor(metrics: metrics, frontMetrics: frontMetrics, postureMode: effectivePostureMode)
                    
                    if let minElbow = calibrationMinElbow, let maxElbow = calibrationMaxElbow {
                        self.depthProgress = Self.depthProgressFor(currentAngle: metrics.elbowFlexion, minAngle: minElbow, maxAngle: maxElbow)
                    } else {
                        let minElbow = (effectivePostureMode == .front) ? 120.0 : 95.0
                        let maxElbow = (effectivePostureMode == .front) ? 145.0 : 165.0
                        self.depthProgress = Self.depthProgressFor(currentAngle: metrics.elbowFlexion, minAngle: minElbow, maxAngle: maxElbow)
                    }
                    self.logPushUpDebug(
                        timestampMS: timestampInMilliseconds,
                        sideLabel: sideLabel,
                        postureMode: effectivePostureMode,
                        elbowAngleRaw: metrics.elbowFlexion,
                        elbowAngleSmoothed: self.elbowAngleEMA,
                        elbowVelocity: self.elbowVelocityEMA,
                        currentRisk: rawRisk,
                        shoulder: shoulder,
                        wrist: wrist,
                        hip: hip,
                        ankle: ankle
                    )
                    
                    if enablePoseDebugLogs {
                        let hipBase = self.calibrationHipDrop ?? 0.0
                        let flareBase = self.calibrationElbowFlareRatio ?? 0.0
                        self.debugText = String(
                            format: "mode=%@ elbow=%.1f hip=%.2f(%.2f) flare=%.2f(%.2f) depth=%.2f score=%d last=%d",
                            "\(effectivePostureMode)",
                            metrics.elbowFlexion,
                            frontMetrics.hipDropRatio,
                            hipBase,
                            frontMetrics.elbowFlareRatio,
                            flareBase,
                            self.depthProgress,
                            self.overallScore,
                            self.lastRepScore
                        )
                    }
                }

            case "Squat":
                let rawAngle = self.evaluator.calculateAngle(p1: landmarks[24], p2: landmarks[26], p3: landmarks[28])
                let smoothed = self.getSmoothedAngle(newAngle: rawAngle)
                rawRisk = self.evaluator.checkSquatForm(angle: smoothed)
                displayMessage = self.getSquatFeedback(risk: rawRisk)
                
            default: break
            }

            if self.activeExercise != "Push-Up" {
                self.processPriorityFeedback(newRisk: rawRisk, newMessage: displayMessage)
            }
        }
    }


    func checkPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: self.startCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { self.startCamera() }
            }
        default: print("Please enable camera in iPhone Settings")
        }
    }
    
    func toggleCamera() {
        cameraPosition = (cameraPosition == .back) ? .front : .back
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.stopRunning()
            self.startCamera()
        }
    }

    private func startCamera() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            self.session.inputs.forEach { self.session.removeInput($0) }
            
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.cameraPosition),
                  let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
                  self.session.canAddInput(videoInput) else { return }
            self.session.addInput(videoInput)
            
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
            
            if self.session.canAddOutput(videoOutput) {
                self.session.addOutput(videoOutput)
                if let connection = videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                    if self.cameraPosition == .front { connection.isVideoMirrored = true }
                }
            }
            self.session.commitConfiguration()
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    private func setupLandmarker() {
        guard let modelPath = Bundle.main.path(forResource: "pose_landmarker_lite", ofType: "task") else { return }
        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .liveStream
        options.poseLandmarkerLiveStreamDelegate = self
        do { poseLandmarker = try PoseLandmarker(options: options) } catch { print(error) }
    }


    func speakFeedback(_ message: String, force: Bool = false) {
        if !force {
            guard message != lastSpokenMessage, !synthesizer.isSpeaking else { return }
        } else if synthesizer.isSpeaking {
            return
        }
        let utterance = AVSpeechUtterance(string: message)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
        utterance.rate = 0.45
        synthesizer.speak(utterance)
        lastSpokenMessage = message
    }

    private func processPriorityFeedback(newRisk: RiskLevel, newMessage: String) {
        riskBuffer.append(newRisk)
        if riskBuffer.count > 5 { riskBuffer.removeFirst() }
        let stableRisk = riskBuffer.reduce(into: [:]) { $0[$1, default: 0] += 1 }.max(by: { $0.value < $1.value })?.key ?? .low
        if self.currentRisk == .critical && stableRisk != .low { return }
        
        if self.feedbackMessage != newMessage {
            self.feedbackMessage = newMessage
            self.currentRisk = stableRisk
            self.speakFeedback(newMessage)
        }
    }

    private func getSquatFeedback(risk: RiskLevel) -> String {
        switch risk {
        case .critical: return "CRITICAL: KNEE VALGUS"
        case .medium: return "Go deeper for full rep"
        case .low: return "Perfect Depth"
        }
    }
}

extension PoseDetectionManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isProcessingFrame, !isDetectionPaused, !isSessionComplete else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestampInMS = Int(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1000)
        
        if let image = try? MPImage(pixelBuffer: pixelBuffer, orientation: .up) {
            isProcessingFrame = true
            try? self.poseLandmarker?.detectAsync(image: image, timestampInMilliseconds: timestampInMS)
        }
    }
}
