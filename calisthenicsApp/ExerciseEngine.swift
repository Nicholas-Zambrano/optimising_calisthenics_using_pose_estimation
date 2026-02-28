import Foundation
import SwiftUI
import MediaPipeTasksVision

struct EngineOutput {
    let repCount: Int
    let cleanReps: Int
    let overallScore: Int
    let depthProgress: Double
    let overlayColors: OverlayColors
    let feedbackMessage: String
    let secondaryHint: String
    let currentRisk: RiskLevel
    let lastRepScore: Int
    let isSessionComplete: Bool
    let sessionSummary: SessionSummary?
    let debugText: String
    let speakMessage: String?
}

final class ExerciseEngine {
    private let evaluator: BiometricEvaluator
    private let pushUpConfig: PushUpConfig
    private let squatConfig: SquatConfig
    private let pullUpConfig: PullUpConfig
    
    private var pushUpState: String = "UP"
    private var currentRepHasError = false
    private var lastTimestampMS: Int?
    private var elbowAngleEMA: Double?
    private var elbowVelocityEMA: Double?
    private var lastElbowAngle: Double?
    private var belowDepthStartMS: Int?
    private var aboveLockoutStartMS: Int?
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
    private var repMaxHipRiseRatio: Double = 0
    private var repMaxElbowFlareRatio: Double = 0
    private var repMaxShoulderAsym: Double = 0
    private var repMaxHipAsym: Double = 0
    private var repMaxElbowAngleDiff: Double = 0
    private var repHipsVisible: Bool = true
    private var repStartMS: Int?
    private var repEndMS: Int?
    private var repScores: [Int] = []
    private var issueCounts: [String: Int] = [:]
    private var lastRepFeedbackMessage: String = ""
    private var lastRepTooFast: Bool = false
    private var lastFeedbackMessage: String = ""
    private var lastFeedbackUpdateMS: Int64 = 0
    private var repArmsVisible: Bool = true
    private var debugEnabled: Bool = false
    private var lastMetricsTimestampMS: Int?
    private var smoothedElbowFlexion: Double?
    private var smoothedBackAngle: Double?
    private var smoothedElbowFlare: Double?
    private var smoothedElbowFlareRatio: Double?
    private var smoothedShoulderAsym: Double?
    private var smoothedHipDropRatio: Double?
    private var smoothedHipRiseRatio: Double?
    private var smoothedHipAsym: Double?
    private var smoothedElbowAngleDiff: Double?
    private var fsmCurrentState: String?
    private var fsmPrevState: String?
    private var fsmRepStartMS: Int?
    private var fsmCounted: Bool = false
    private var calibrationMinElbow: Double?
    private var calibrationMaxElbow: Double?
    private var calibrationRepCount = 0
    private let calibrationReps = 3
    private var calibrationHipDrop: Double?
    private var calibrationElbowFlareRatio: Double?
    private var calibrationShoulderAsym: Double?
    private var calibrationElbowAngleDiff: Double?
    private var calibrationDepthProgress: Double?

    private var squatState: String = "UP"
    private var squatRepMinAngle: Double = 999
    private var squatRepStartMS: Int?

    private var pullUpState: String = "DOWN"
    private var pullUpRepMinAngle: Double = 999
    private var pullUpRepStartMS: Int?
    
    private(set) var repCount: Int = 0
    private(set) var cleanReps: Int = 0
    private(set) var overallScore: Int = 0
    private(set) var depthProgress: Double = 0
    private(set) var overlayColors: OverlayColors = .neutral
    private(set) var feedbackMessage: String = "Searching..."
    private(set) var secondaryHint: String = ""
    private(set) var currentRisk: RiskLevel = .low
    private(set) var lastRepScore: Int = 0
    private(set) var isSessionComplete: Bool = false
    private(set) var sessionSummary: SessionSummary?
    private(set) var debugText: String = ""
    
    private var targetReps: Int = 10
    private var sensitivity: FeedbackSensitivity = .normal
    private var feedbackFocus: FeedbackFocus = .armsOnly
    private var isPortraitMode: Bool = true
    
    init(evaluator: BiometricEvaluator, pushUpConfig: PushUpConfig, squatConfig: SquatConfig, pullUpConfig: PullUpConfig) {
        self.evaluator = evaluator
        self.pushUpConfig = pushUpConfig
        self.squatConfig = squatConfig
        self.pullUpConfig = pullUpConfig
    }
    
    func reset(targetReps: Int, sensitivity: FeedbackSensitivity, focus: FeedbackFocus, isPortraitMode: Bool) {
        self.targetReps = targetReps
        self.sensitivity = sensitivity
        self.feedbackFocus = focus
        self.isPortraitMode = isPortraitMode
        
        repCount = 0
        cleanReps = 0
        overallScore = 0
        lastRepScore = 0
        feedbackMessage = "Get into push-up position"
        currentRisk = .low
        isSessionComplete = false
        sessionSummary = nil
        depthProgress = 0
        overlayColors = .neutral
        resetRepMetrics()
        calibrationMinElbow = nil
        calibrationMaxElbow = nil
        calibrationHipDrop = nil
        calibrationElbowFlareRatio = nil
        calibrationShoulderAsym = nil
        calibrationElbowAngleDiff = nil
        calibrationDepthProgress = nil
        calibrationRepCount = 0
        lastMetricsTimestampMS = nil
        smoothedElbowFlexion = nil
        smoothedBackAngle = nil
        smoothedElbowFlare = nil
        smoothedElbowFlareRatio = nil
        smoothedShoulderAsym = nil
        smoothedHipDropRatio = nil
        smoothedHipRiseRatio = nil
        smoothedHipAsym = nil
        smoothedElbowAngleDiff = nil
        fsmCurrentState = nil
        fsmPrevState = nil
        fsmRepStartMS = nil

        squatState = "UP"
        squatRepMinAngle = 999
        squatRepStartMS = nil
        pullUpState = "DOWN"
        pullUpRepMinAngle = 999
        pullUpRepStartMS = nil
    }

    func updatePushUp(metrics: PushUpMetrics,
                      frontMetrics: FrontViewMetrics,
                      elbowAngleDiff: Double,
                      postureMode: PushUpPostureMode,
                      timestampMS: Int,
                      isPortraitMode: Bool,
                      sensitivity: FeedbackSensitivity,
                      feedbackFocus: FeedbackFocus,
                      enableDebug: Bool) -> EngineOutput {
        self.isPortraitMode = isPortraitMode
        self.sensitivity = sensitivity
        self.feedbackFocus = feedbackFocus
        self.debugEnabled = enableDebug
        let ruleMode: PushUpPostureMode = (feedbackFocus == .armsOnly ? .front : postureMode)

        let (smoothedMetrics, smoothedFront, smoothedElbowDiff) = smoothPushUpMetrics(
            metrics: metrics,
            frontMetrics: frontMetrics,
            elbowAngleDiff: elbowAngleDiff,
            timestampMS: timestampMS
        )
        
        var speakMessage: String?

        if postureMode == .none {
            feedbackMessage = "Get into push-up position"
            secondaryHint = ""
            currentRisk = .low
            overlayColors = .neutral
            depthProgress = 0
            debugText = enableDebug ? "mode=none" : ""
            return EngineOutput(
                repCount: repCount,
                cleanReps: cleanReps,
                overallScore: overallScore,
                depthProgress: depthProgress,
                overlayColors: overlayColors,
                feedbackMessage: feedbackMessage,
                secondaryHint: secondaryHint,
                currentRisk: currentRisk,
                lastRepScore: lastRepScore,
                isSessionComplete: isSessionComplete,
                sessionSummary: sessionSummary,
                debugText: debugText,
                speakMessage: nil
            )
        }
        
        updateRepMetrics(metrics: smoothedMetrics, frontMetrics: smoothedFront, elbowAngleDiff: smoothedElbowDiff)
        handlePushUpRep(elbowAngleRaw: metrics.elbowFlexion, timestampMS: timestampMS, postureMode: postureMode)
        
        overlayColors = colorsFor(metrics: smoothedMetrics, frontMetrics: smoothedFront, postureMode: postureMode)
        
        if let minElbow = calibrationMinElbow, let maxElbow = calibrationMaxElbow {
            depthProgress = depthProgressFor(currentAngle: smoothedMetrics.elbowFlexion, minAngle: minElbow, maxAngle: maxElbow)
        } else {
            let minElbow = (postureMode == .front) ? pushUpConfig.depthFrontThreshold : pushUpConfig.depthSideThreshold
            let maxElbow = (postureMode == .front) ? pushUpConfig.lockoutFrontThreshold : pushUpConfig.lockoutSideThreshold
            depthProgress = depthProgressFor(currentAngle: smoothedMetrics.elbowFlexion, minAngle: minElbow, maxAngle: maxElbow)
        }
        
        if enableDebug {
            let hipBase = calibrationHipDrop ?? pushUpConfig.hipBaseDefault
            let flareBase = calibrationElbowFlareRatio ?? pushUpConfig.flareBaseDefault
            debugText = String(
                format: "mode=%@ view=%@ elbow=%.1f hip=%.2f(%.2f) flare=%.2f(%.2f) asymS=%.2f asymH=%.2f diff=%.1f hipVis=%@ ankleVis=%@ depth=%.2f score=%d last=%d calib=%d/%d",
                "\(postureMode)",
                isPortraitMode ? "portrait" : "landscape",
                smoothedMetrics.elbowFlexion,
                smoothedFront.hipDropRatio,
                hipBase,
                smoothedFront.elbowFlareRatio,
                flareBase,
                smoothedFront.shoulderAsym,
                smoothedFront.hipAsym,
                smoothedElbowDiff,
                smoothedFront.hipsVisible ? "Y" : "N",
                smoothedFront.anklesVisible ? "Y" : "N",
                depthProgress,
                overallScore,
                lastRepScore,
                calibrationRepCount,
                calibrationReps
            )
        }

        if repCompletedMessage != nil {
            speakMessage = repCompletedMessage
            repCompletedMessage = nil
        } else {
            applyRuleBasedFeedback(
                frontMetrics: smoothedFront,
                elbowAngleDiff: smoothedElbowDiff,
                postureMode: ruleMode
            )
        }

        if calibrationRepCount < calibrationReps && secondaryHint.isEmpty {
            secondaryHint = "Calibrating: \(calibrationRepCount)/\(calibrationReps)"
        }

        lastRepTooFast = false
        
        return EngineOutput(
            repCount: repCount,
            cleanReps: cleanReps,
            overallScore: overallScore,
            depthProgress: depthProgress,
            overlayColors: overlayColors,
            feedbackMessage: feedbackMessage,
            secondaryHint: secondaryHint,
            currentRisk: currentRisk,
            lastRepScore: lastRepScore,
            isSessionComplete: isSessionComplete,
            sessionSummary: sessionSummary,
            debugText: debugText,
            speakMessage: speakMessage
        )
    }

    func updateSquat(shoulder: NormalizedLandmark,
                     hip: NormalizedLandmark,
                     knee: NormalizedLandmark,
                     ankle: NormalizedLandmark,
                     hipWidth: Double,
                     torsoLength: Double,
                     timestampMS: Int) -> EngineOutput {
        let hipVis = hip.visibility?.floatValue ?? 0
        let kneeVis = knee.visibility?.floatValue ?? 0
        let ankleVis = ankle.visibility?.floatValue ?? 0
        let bodyVisible = min(hipVis, kneeVis, ankleVis) >= 0.4

        let angle = evaluator.calculateAngle(p1: hip, p2: knee, p3: ankle)
        depthProgress = depthProgressFor(currentAngle: angle, minAngle: squatConfig.depthThreshold, maxAngle: squatConfig.lockoutAngle)
        squatRepMinAngle = min(squatRepMinAngle, angle)

        let depthReached = angle <= squatConfig.depthThreshold
        let lockoutAngle = squatConfig.lockoutAngle

        if squatState == "UP" {
            if squatRepStartMS == nil { squatRepStartMS = timestampMS }
            if depthReached { squatState = "DOWN" }
        } else {
            if angle >= lockoutAngle {
                let durationSec = squatRepStartMS.map { Double(timestampMS - $0) / 1000.0 } ?? 0
                let tooFast = durationSec > 0 && durationSec < squatConfig.tempoMinSec
                let shallow = !depthReached
                var repScore = 100
                if shallow { repScore -= 30 }
                if tooFast { repScore -= 20 }
                repScore = max(0, repScore)
                lastRepScore = repScore
                repScores.append(repScore)
                overallScore = repScores.isEmpty ? 0 : Int(Double(repScores.reduce(0, +)) / Double(repScores.count))

                if repScore >= 85 { cleanReps += 1 }
                repCount += 1
                squatState = "UP"
                squatRepMinAngle = 999
                squatRepStartMS = nil

                if repCount >= targetReps {
                    isSessionComplete = true
                    sessionSummary = buildSessionSummary()
                }
            }
        }

        let values: [String: Double] = [
            "depthProgress": depthProgress,
            "tempoFast": (squatRepStartMS != nil && (Double(timestampMS - (squatRepStartMS ?? timestampMS)) / 1000.0) < squatConfig.tempoMinSec) ? 1.0 : 0.0,
            "bodyVisible": bodyVisible ? 1.0 : 0.0,
            "kneeValgus": max(0.0, (Double(ankle.x - knee.x)) / max(0.001, hipWidth)),
            "forwardLean": max(0.0, (Double(shoulder.x - hip.x)) / max(0.001, torsoLength)),
            "shallowDepth": (angle > 100 && angle < 130) ? 1.0 : 0.0
        ]

        let matched = evaluateRules(values: values, postureMode: .front, exerciseTag: "squat", rules: squatConfig.feedbackRules)
        feedbackMessage = messageForRules(matched)
        secondaryHint = secondaryMessageForRules(matched)
        if let primary = matched.sorted(by: { severityRank($0.severity) > severityRank($1.severity) }).first {
            currentRisk = riskLevel(for: primary.severity)
        } else {
            currentRisk = .low
        }
        overlayColors = colorsForRisk(currentRisk, arms: false, legs: true)
        return EngineOutput(
            repCount: repCount,
            cleanReps: cleanReps,
            overallScore: overallScore,
            depthProgress: depthProgress,
            overlayColors: overlayColors,
            feedbackMessage: feedbackMessage,
            secondaryHint: secondaryHint,
            currentRisk: currentRisk,
            lastRepScore: lastRepScore,
            isSessionComplete: isSessionComplete,
            sessionSummary: sessionSummary,
            debugText: debugText,
            speakMessage: nil
        )
    }

    func updatePullUp(shoulder: NormalizedLandmark,
                      elbow: NormalizedLandmark,
                      wrist: NormalizedLandmark,
                      timestampMS: Int) -> EngineOutput {
        let shoulderVis = shoulder.visibility?.floatValue ?? 0
        let elbowVis = elbow.visibility?.floatValue ?? 0
        let wristVis = wrist.visibility?.floatValue ?? 0
        let bodyVisible = min(shoulderVis, elbowVis, wristVis) >= 0.4

        let angle = evaluator.calculateAngle(p1: shoulder, p2: elbow, p3: wrist)
        depthProgress = depthProgressFor(currentAngle: angle, minAngle: pullUpConfig.chinOverBarAngle, maxAngle: pullUpConfig.bottomAngle)
        pullUpRepMinAngle = min(pullUpRepMinAngle, angle)

        let topReached = angle <= pullUpConfig.chinOverBarAngle
        let bottomAngle = pullUpConfig.bottomAngle

        if pullUpState == "DOWN" {
            if pullUpRepStartMS == nil { pullUpRepStartMS = timestampMS }
            if topReached { pullUpState = "UP" }
        } else {
            if angle >= bottomAngle {
                let durationSec = pullUpRepStartMS.map { Double(timestampMS - $0) / 1000.0 } ?? 0
                let tooFast = durationSec > 0 && durationSec < pullUpConfig.tempoMinSec
                let shallow = !topReached
                var repScore = 100
                if shallow { repScore -= 30 }
                if tooFast { repScore -= 20 }
                repScore = max(0, repScore)
                lastRepScore = repScore
                repScores.append(repScore)
                overallScore = repScores.isEmpty ? 0 : Int(Double(repScores.reduce(0, +)) / Double(repScores.count))

                if repScore >= 85 { cleanReps += 1 }
                repCount += 1
                pullUpState = "DOWN"
                pullUpRepMinAngle = 999
                pullUpRepStartMS = nil

                if repCount >= targetReps {
                    isSessionComplete = true
                    sessionSummary = buildSessionSummary()
                }
            }
        }

        let values: [String: Double] = [
            "depthProgress": depthProgress,
            "tempoFast": (pullUpRepStartMS != nil && (Double(timestampMS - (pullUpRepStartMS ?? timestampMS)) / 1000.0) < pullUpConfig.tempoMinSec) ? 1.0 : 0.0,
            "bodyVisible": bodyVisible ? 1.0 : 0.0
        ]

        let matched = evaluateRules(values: values, postureMode: .front, exerciseTag: "pullup", rules: pullUpConfig.feedbackRules)
        feedbackMessage = messageForRules(matched)
        secondaryHint = secondaryMessageForRules(matched)
        if let primary = matched.sorted(by: { severityRank($0.severity) > severityRank($1.severity) }).first {
            currentRisk = riskLevel(for: primary.severity)
        } else {
            currentRisk = .low
        }
        overlayColors = colorsForRisk(currentRisk, arms: true, legs: false)
        return EngineOutput(
            repCount: repCount,
            cleanReps: cleanReps,
            overallScore: overallScore,
            depthProgress: depthProgress,
            overlayColors: overlayColors,
            feedbackMessage: feedbackMessage,
            secondaryHint: secondaryHint,
            currentRisk: currentRisk,
            lastRepScore: lastRepScore,
            isSessionComplete: isSessionComplete,
            sessionSummary: sessionSummary,
            debugText: debugText,
            speakMessage: nil
        )
    }
    
    // MARK: - Internal Logic
    
    private var repCompletedMessage: String?
    
    private func resetRepMetrics() {
        repMinElbowAngle = 999
        repMaxElbowAngle = 0
        repMinBackAngle = 999
        repMaxElbowFlare = 0
        repMaxHipDropRatio = 0
        repMaxHipRiseRatio = 0
        repMaxElbowFlareRatio = 0
        repMaxShoulderAsym = 0
        repMaxHipAsym = 0
        repMaxElbowAngleDiff = 0
        repHipsVisible = true
        repArmsVisible = true
        repStartMS = nil
        repEndMS = nil
        criticalStreak = 0
        currentRepHasError = false
        isArmed = false
        lockoutHoldStartMS = nil
        fsmCounted = false
    }

    private func colorsForRisk(_ risk: RiskLevel, arms: Bool, legs: Bool) -> OverlayColors {
        let color: Color
        switch risk {
        case .critical: color = .red
        case .medium: color = .orange
        case .low: color = .green
        }

        return OverlayColors(
            leftArm: arms ? color : .white.opacity(0.6),
            rightArm: arms ? color : .white.opacity(0.6),
            torso: .white.opacity(0.6),
            leftLeg: legs ? color : .white.opacity(0.6),
            rightLeg: legs ? color : .white.opacity(0.6)
        )
    }
    
    private func emaFilter(previous: Double?, value: Double, dtSeconds: Double, tau: Double) -> Double {
        guard let previous = previous else { return value }
        let alpha = 1.0 - exp(-dtSeconds / tau)
        return (alpha * value) + ((1.0 - alpha) * previous)
    }

    private func smoothPushUpMetrics(metrics: PushUpMetrics,
                                     frontMetrics: FrontViewMetrics,
                                     elbowAngleDiff: Double,
                                     timestampMS: Int) -> (PushUpMetrics, FrontViewMetrics, Double) {
        let dtSeconds: Double
        if let last = lastMetricsTimestampMS {
            dtSeconds = max(0.001, Double(timestampMS - last) / 1000.0)
        } else {
            dtSeconds = 0.033
        }
        lastMetricsTimestampMS = timestampMS

        let tauFast = 0.10
        let tauSlow = 0.18

        smoothedElbowFlexion = emaFilter(previous: smoothedElbowFlexion, value: metrics.elbowFlexion, dtSeconds: dtSeconds, tau: tauFast)
        smoothedBackAngle = emaFilter(previous: smoothedBackAngle, value: metrics.backAngle, dtSeconds: dtSeconds, tau: tauFast)
        smoothedElbowFlare = emaFilter(previous: smoothedElbowFlare, value: metrics.elbowFlare, dtSeconds: dtSeconds, tau: tauFast)
        smoothedElbowFlareRatio = emaFilter(previous: smoothedElbowFlareRatio, value: frontMetrics.elbowFlareRatio, dtSeconds: dtSeconds, tau: tauSlow)
        smoothedShoulderAsym = emaFilter(previous: smoothedShoulderAsym, value: frontMetrics.shoulderAsym, dtSeconds: dtSeconds, tau: tauSlow)
        smoothedHipDropRatio = emaFilter(previous: smoothedHipDropRatio, value: frontMetrics.hipDropRatio, dtSeconds: dtSeconds, tau: tauSlow)
        smoothedHipRiseRatio = emaFilter(previous: smoothedHipRiseRatio, value: frontMetrics.hipRiseRatio, dtSeconds: dtSeconds, tau: tauSlow)
        smoothedHipAsym = emaFilter(previous: smoothedHipAsym, value: frontMetrics.hipAsym, dtSeconds: dtSeconds, tau: tauSlow)
        smoothedElbowAngleDiff = emaFilter(previous: smoothedElbowAngleDiff, value: elbowAngleDiff, dtSeconds: dtSeconds, tau: tauSlow)

        let smoothedMetrics = PushUpMetrics(
            backAngle: smoothedBackAngle ?? metrics.backAngle,
            elbowFlexion: smoothedElbowFlexion ?? metrics.elbowFlexion,
            elbowFlare: smoothedElbowFlare ?? metrics.elbowFlare
        )

        let smoothedFront = FrontViewMetrics(
            hipDropRatio: smoothedHipDropRatio ?? frontMetrics.hipDropRatio,
            hipRiseRatio: smoothedHipRiseRatio ?? frontMetrics.hipRiseRatio,
            elbowFlareRatio: smoothedElbowFlareRatio ?? frontMetrics.elbowFlareRatio,
            shoulderAsym: smoothedShoulderAsym ?? frontMetrics.shoulderAsym,
            hipAsym: smoothedHipAsym ?? frontMetrics.hipAsym,
            hipsVisible: frontMetrics.hipsVisible,
            anklesVisible: frontMetrics.anklesVisible,
            armsVisible: frontMetrics.armsVisible
        )

        return (smoothedMetrics, smoothedFront, smoothedElbowAngleDiff ?? elbowAngleDiff)
    }
    
    private func updateRepMetrics(metrics: PushUpMetrics, frontMetrics: FrontViewMetrics, elbowAngleDiff: Double) {
        repMinElbowAngle = min(repMinElbowAngle, metrics.elbowFlexion)
        repMaxElbowAngle = max(repMaxElbowAngle, metrics.elbowFlexion)
        repMinBackAngle = min(repMinBackAngle, metrics.backAngle)
        repMaxElbowFlare = max(repMaxElbowFlare, metrics.elbowFlare)
        repMaxHipDropRatio = max(repMaxHipDropRatio, frontMetrics.hipDropRatio)
        repMaxHipRiseRatio = max(repMaxHipRiseRatio, frontMetrics.hipRiseRatio)
        repMaxElbowFlareRatio = max(repMaxElbowFlareRatio, frontMetrics.elbowFlareRatio)
        repMaxShoulderAsym = max(repMaxShoulderAsym, frontMetrics.shoulderAsym)
        repMaxHipAsym = max(repMaxHipAsym, frontMetrics.hipAsym)
        repMaxElbowAngleDiff = max(repMaxElbowAngleDiff, elbowAngleDiff)
        if !frontMetrics.hipsVisible { repHipsVisible = false }
        if !frontMetrics.armsVisible { repArmsVisible = false }
    }
    
    private func handlePushUpRep(elbowAngleRaw: Double, timestampMS: Int, postureMode: PushUpPostureMode) {
        if isSessionComplete { return }
        
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
        
        if let fsm = fsmConfig(for: postureMode) {
            handlePushUpFSM(smoothedAngle: smoothedAngle, velocity: v, timestampMS: timestampMS, fsm: fsm, postureMode: postureMode)
            return
        }

        let depthAngle = (postureMode == .front) ? pushUpConfig.depthFrontThreshold : pushUpConfig.depthSideThreshold
        let lockoutAngle = (postureMode == .front) ? pushUpConfig.lockoutFrontThreshold : pushUpConfig.lockoutSideThreshold
        let minDownVelocity = (postureMode == .front) ? pushUpConfig.minDownVelocityFront : pushUpConfig.minDownVelocitySide
        let minUpVelocity = (postureMode == .front) ? pushUpConfig.minUpVelocityFront : pushUpConfig.minUpVelocitySide
        let dwellMS = (postureMode == .front) ? pushUpConfig.dwellFrontMS : pushUpConfig.dwellSideMS
        
        if pushUpState == "UP" {
            if smoothedAngle > lockoutAngle {
                if lockoutHoldStartMS == nil { lockoutHoldStartMS = timestampMS }
                if let start = lockoutHoldStartMS, (timestampMS - start) >= pushUpConfig.lockoutHoldMS {
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

    private func fsmConfig(for postureMode: PushUpPostureMode) -> PushUpFSMConfig? {
        switch postureMode {
        case .front: return pushUpConfig.fsmFront
        case .side: return pushUpConfig.fsmSide
        case .none: return nil
        }
    }

    private func handlePushUpFSM(smoothedAngle: Double,
                                 velocity: Double,
                                 timestampMS: Int,
                                 fsm: PushUpFSMConfig,
                                 postureMode: PushUpPostureMode) {
        if fsmCurrentState == nil {
            fsmCurrentState = fsm.stateOrder.first
            fsmPrevState = fsmCurrentState
        }

        let values: [String: Double] = [
            "angle": smoothedAngle,
            "velocity": velocity
        ]

        var nextState = fsmCurrentState
        for stateName in fsm.stateOrder {
            if let state = fsm.states[stateName],
               evaluateCondition(state.condition, values: values) {
                nextState = stateName
                break
            }
        }

        if nextState != fsmCurrentState {
            fsmPrevState = fsmCurrentState
            fsmCurrentState = nextState
        }

        if fsmCurrentState == "start" && fsmPrevState != "start" {
            fsmCounted = false
            inRep = false
            fsmRepStartMS = nil
        }

        if fsmCurrentState == fsm.counter.from && fsmPrevState != fsm.counter.from {
            resetRepMetrics()
            repStartMS = timestampMS
            fsmRepStartMS = timestampMS
            inRep = true
        }

        if fsmPrevState == fsm.counter.from && fsmCurrentState == fsm.counter.to {
            let durationSec = fsmRepStartMS.map { Double(timestampMS - $0) / 1000.0 } ?? 0
            if durationSec >= fsm.minRepDurationSec && !fsmCounted {
                repCount += 1
                inRep = false
                fsmCounted = true
                finalizeRep(postureMode: postureMode, timestampMS: timestampMS)
            }
        }
    }

    private func evaluateCondition(_ condition: String, values: [String: Double]) -> Bool {
        let parts = condition.split(separator: "&", omittingEmptySubsequences: true)
            .map { $0.replacingOccurrences(of: "&", with: "").trimmingCharacters(in: .whitespaces) }
        for part in parts {
            if part.isEmpty { continue }
            if !evaluateClause(part, values: values) { return false }
        }
        return true
    }

    private func evaluateClause(_ clause: String, values: [String: Double]) -> Bool {
        let ops = [">=", "<=", ">", "<"]
        for op in ops {
            if let range = clause.range(of: op) {
                let left = clause[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let right = clause[range.upperBound...].trimmingCharacters(in: .whitespaces)
                guard let lhs = values[String(left)],
                      let rhs = Double(right) else { return false }
                switch op {
                case ">=": return lhs >= rhs
                case "<=": return lhs <= rhs
                case ">": return lhs > rhs
                case "<": return lhs < rhs
                default: return false
                }
            }
        }
        return false
    }
    
    private func finalizeRep(postureMode: PushUpPostureMode, timestampMS: Int) {
        repEndMS = timestampMS
        let durationMS = (repStartMS != nil && repEndMS != nil) ? max(1, (repEndMS! - repStartMS!)) : 1
        let durationSec = Double(durationMS) / 1000.0

        let depthThreshold = (postureMode == .front) ? pushUpConfig.depthFrontThreshold : pushUpConfig.depthSideThreshold
        let lockoutAngle = (postureMode == .front) ? pushUpConfig.lockoutFrontThreshold : pushUpConfig.lockoutSideThreshold
        let repDepthProgress = depthProgressFor(currentAngle: repMinElbowAngle, minAngle: depthThreshold, maxAngle: lockoutAngle)
        lastRepTooFast = durationSec < 0.6

        let useHipMetrics = repHipsVisible && feedbackFocus == .fullBody && !isPortraitMode
        let repValues: [String: Double] = [
            "hipDropRatio": useHipMetrics ? repMaxHipDropRatio : 0.0,
            "hipRiseRatio": useHipMetrics ? repMaxHipRiseRatio : 0.0,
            "elbowFlareRatio": repMaxElbowFlareRatio,
            "shoulderAsym": repMaxShoulderAsym,
            "hipAsym": useHipMetrics ? repMaxHipAsym : 0.0,
            "elbowAngleDiff": repMaxElbowAngleDiff,
            "depthProgress": repDepthProgress,
            "hipsVisible": repHipsVisible ? 1.0 : 0.0,
            "armsVisible": repArmsVisible ? 1.0 : 0.0,
            "tempoFast": lastRepTooFast ? 1.0 : 0.0,
            "backAngle": repMinBackAngle,
            "elbowFlare": repMaxElbowFlare
        ]

        let ruleMode: PushUpPostureMode = (feedbackFocus == .armsOnly ? .front : postureMode)
        let matchedRules = evaluateRules(values: repValues, postureMode: ruleMode, exerciseTag: "pushup", rules: pushUpConfig.feedbackRules)
        let repScore = scoreForRules(matchedRules)
        if debugEnabled {
            let ids = matchedRules.map { $0.id }.joined(separator: ",")
            print("[PushUpRep] values=\(repValues) matched=[\(ids)] score=\(repScore)")
            if matchedRules.isEmpty {
                print("[PushUpRep] rules.count=\(pushUpConfig.feedbackRules.count) mode=\(ruleMode) focus=\(feedbackFocus)")
                for rule in pushUpConfig.feedbackRules {
                    let appliesRule = applies(rule: rule, postureMode: ruleMode, exerciseTag: "pushup")
                    let value = repValues[rule.metric] ?? -999
                    let threshold = adjustedThreshold(for: rule)
                    print("[RuleCheck] \(rule.id) metric=\(rule.metric) value=\(value) op=\(rule.op) thr=\(threshold) applies=\(appliesRule) tags=\(rule.appliesIn ?? [])")
                }
            }
        }
        repScores.append(repScore)
        lastRepScore = repScore

        if let primary = matchedRules.sorted(by: { severityRank($0.severity) > severityRank($1.severity) }).first {
            issueCounts[primary.message, default: 0] += 1
        }

        if !matchedRules.contains(where: { $0.severity == .critical }) {
            cleanReps += 1
        }

        calculateOverallScore()
        let message = messageForRules(matchedRules)
        let secondary = secondaryMessageForRules(matchedRules)
        let repRisk: RiskLevel = matchedRules.contains(where: { $0.severity == RuleSeverity.critical }) ? .critical :
            (matchedRules.contains(where: { $0.severity == RuleSeverity.important }) ? .medium : .low)
        updateFeedback(message: message, secondary: secondary, risk: repRisk, force: true)

        repCompletedMessage = "Rep \(repCount). \(message)"

        if repCount >= targetReps {
            isSessionComplete = true
            sessionSummary = buildSessionSummary()
        }
        
        if calibrationRepCount < calibrationReps {
            calibrationMinElbow = min(calibrationMinElbow ?? repMinElbowAngle, repMinElbowAngle)
            calibrationMaxElbow = max(calibrationMaxElbow ?? repMaxElbowAngle, repMaxElbowAngle)
            calibrationHipDrop = max(calibrationHipDrop ?? repMaxHipDropRatio, repMaxHipDropRatio)
            calibrationElbowFlareRatio = max(calibrationElbowFlareRatio ?? repMaxElbowFlareRatio, repMaxElbowFlareRatio)
            calibrationShoulderAsym = max(calibrationShoulderAsym ?? repMaxShoulderAsym, repMaxShoulderAsym)
            calibrationElbowAngleDiff = max(calibrationElbowAngleDiff ?? repMaxElbowAngleDiff, repMaxElbowAngleDiff)
            calibrationDepthProgress = max(calibrationDepthProgress ?? repDepthProgress, repDepthProgress)
            calibrationRepCount += 1

            if calibrationRepCount == calibrationReps {
                print(String(format: "[Calibration] elbowMin=%.1f elbowMax=%.1f hip=%.3f flare=%.3f shoulderAsym=%.3f elbowDiff=%.1f depth=%.2f",
                             calibrationMinElbow ?? 0,
                             calibrationMaxElbow ?? 0,
                             calibrationHipDrop ?? 0,
                             calibrationElbowFlareRatio ?? 0,
                             calibrationShoulderAsym ?? 0,
                             calibrationElbowAngleDiff ?? 0,
                             calibrationDepthProgress ?? 0))
            }
        }
    }
    
    private func calculateOverallScore() {
        guard repCount > 0 else { return }
        overallScore = repScores.reduce(0, +) / max(repScores.count, 1)
    }

    private func buildSessionSummary() -> SessionSummary {
        return SessionSummary(
            totalReps: repCount,
            averageScore: overallScore,
            cleanReps: cleanReps,
            bestRep: repScores.max() ?? 0,
            worstRep: repScores.min() ?? 0,
            mostCommonIssueMessage: issueCounts.max(by: { $0.value < $1.value })?.key
        )
    }

    private func scoreForRules(_ rules: [FeedbackRule]) -> Int {
        var score = 100
        for rule in rules {
            switch rule.severity {
            case .critical: score -= 35
            case .important: score -= 15
            case .minor: score -= 5
            }
        }
        return max(0, min(100, score))
    }

    private func messageForRules(_ rules: [FeedbackRule]) -> String {
        if rules.isEmpty { return "GOOD: Form is clean" }
        let sorted = rules.sorted { severityRank($0.severity) > severityRank($1.severity) }
        let unique = dedupeRules(sorted)
        let primary = unique[0]
        return "\(label(for: primary.severity)): \(primary.message)"
    }

    private func secondaryMessageForRules(_ rules: [FeedbackRule]) -> String {
        if rules.count > 1 {
            let sorted = rules.sorted { severityRank($0.severity) > severityRank($1.severity) }
            let unique = dedupeRules(sorted)
            if unique.count > 1 {
                return "Also: \(unique[1].message)"
            }
        }
        return ""
    }

    private func dedupeRules(_ rules: [FeedbackRule]) -> [FeedbackRule] {
        var seen = Set<String>()
        var result: [FeedbackRule] = []
        for rule in rules {
            if seen.contains(rule.message) { continue }
            seen.insert(rule.message)
            result.append(rule)
        }
        return result
    }

    private func updateFeedback(message: String,
                                secondary: String = "",
                                risk: RiskLevel,
                                force: Bool = false) {
        let now = Int64(lastTimestampMS ?? 0)
        if !force && message == lastFeedbackMessage && (now - lastFeedbackUpdateMS) < 800 {
            return
        }
        feedbackMessage = message
        secondaryHint = secondary
        currentRisk = risk
        lastFeedbackMessage = message
        lastFeedbackUpdateMS = now
    }
    

    private func applyRuleBasedFeedback(frontMetrics: FrontViewMetrics,
                                        elbowAngleDiff: Double,
                                        postureMode: PushUpPostureMode) {
        guard !pushUpConfig.feedbackRules.isEmpty else { return }

        let useHipMetrics = frontMetrics.hipsVisible && feedbackFocus == .fullBody && !isPortraitMode
        let values: [String: Double] = [
            "hipDropRatio": useHipMetrics ? frontMetrics.hipDropRatio : 0.0,
            "hipRiseRatio": useHipMetrics ? frontMetrics.hipRiseRatio : 0.0,
            "elbowFlareRatio": frontMetrics.elbowFlareRatio,
            "shoulderAsym": frontMetrics.shoulderAsym,
            "hipAsym": useHipMetrics ? frontMetrics.hipAsym : 0.0,
            "elbowAngleDiff": elbowAngleDiff,
            "depthProgress": depthProgress,
            "hipsVisible": frontMetrics.hipsVisible ? 1.0 : 0.0,
            "armsVisible": frontMetrics.armsVisible ? 1.0 : 0.0,
            "tempoFast": lastRepTooFast ? 1.0 : 0.0,
            "backAngle": repMinBackAngle < 999 ? repMinBackAngle : 180.0,
            "elbowFlare": repMaxElbowFlare
        ]

        let matched = evaluateRules(values: values, postureMode: postureMode, exerciseTag: "pushup", rules: pushUpConfig.feedbackRules)

        if matched.isEmpty {
            if inRep {
                let hint = depthProgress < 0.7 ? "Lower down for full depth" : "Hold steady"
                updateFeedback(message: hint, secondary: "", risk: .low)
            }
            return
        }

        let message = messageForRules(matched)
        let secondary = secondaryMessageForRules(matched)
        if let primary = matched.sorted(by: { severityRank($0.severity) > severityRank($1.severity) }).first {
            updateFeedback(message: message, secondary: secondary, risk: riskLevel(for: primary.severity))
        }
    }

    private func evaluateRules(values: [String: Double],
                               postureMode: PushUpPostureMode,
                               exerciseTag: String,
                               rules: [FeedbackRule]) -> [FeedbackRule] {
        return rules.filter { rule in
            if !applies(rule: rule, postureMode: postureMode, exerciseTag: exerciseTag) { return false }
            guard let value = values[rule.metric] else { return false }
            let threshold = adjustedThreshold(for: rule)
            switch rule.op {
            case "gt": return value > threshold
            case "lt": return value < threshold
            default: return false
            }
        }
    }

    private func applies(rule: FeedbackRule, postureMode: PushUpPostureMode, exerciseTag: String) -> Bool {
        guard let tags = rule.appliesIn, !tags.isEmpty else { return true }
        let modeTag = (postureMode == .side) ? "side" : (postureMode == .front ? "front" : "none")
        let exerciseTags = ["pushup", "squat", "pullup"]
        if tags.contains(where: { exerciseTags.contains($0) }) && !tags.contains(exerciseTag) {
            return false
        }
        if tags.contains(modeTag) == false { return false }
        if tags.contains("portrait") && !isPortraitMode { return false }
        if tags.contains("landscape") && isPortraitMode { return false }
        if tags.contains("fullBody") && feedbackFocus != .fullBody { return false }
        if tags.contains("armsOnly") && feedbackFocus != .armsOnly { return false }
        return true
    }

    private func severityRank(_ severity: RuleSeverity) -> Int {
        switch severity {
        case .critical: return 3
        case .important: return 2
        case .minor: return 1
        }
    }

    private func adjustedThreshold(for rule: FeedbackRule) -> Double {
        guard calibrationRepCount >= calibrationReps else { return rule.threshold }
        let isGreater = rule.op == "gt"
        switch rule.metric {
        case "hipDropRatio":
            if let base = calibrationHipDrop {
                let scaled = base * severityMultiplier(for: rule.severity)
                return isGreater ? max(rule.threshold, scaled) : max(rule.threshold, scaled)
            }
        case "elbowFlareRatio":
            if let base = calibrationElbowFlareRatio {
                let scaled = base * severityMultiplier(for: rule.severity)
                return isGreater ? max(rule.threshold, scaled) : max(rule.threshold, scaled)
            }
        case "shoulderAsym":
            if let base = calibrationShoulderAsym {
                let scaled = base * severityMultiplier(for: rule.severity)
                return isGreater ? max(rule.threshold, scaled) : max(rule.threshold, scaled)
            }
        case "elbowAngleDiff":
            if let base = calibrationElbowAngleDiff {
                let scaled = base * severityMultiplier(for: rule.severity)
                return isGreater ? max(rule.threshold, scaled) : max(rule.threshold, scaled)
            }
        case "depthProgress":
            if let base = calibrationDepthProgress {
                // Depth progress is "higher is better", so relax threshold a bit above baseline.
                return max(rule.threshold, base - 0.1)
            }
        default:
            break
        }
        return rule.threshold
    }

    private func severityMultiplier(for severity: RuleSeverity) -> Double {
        switch severity {
        case .critical: return sensitivity.redMultiplier
        case .important: return sensitivity.yellowMultiplier
        case .minor: return 1.0
        }
    }

    private func label(for severity: RuleSeverity) -> String {
        switch severity {
        case .critical: return "CRITICAL"
        case .important: return "IMPORTANT"
        case .minor: return "MINOR"
        }
    }

    private func riskLevel(for severity: RuleSeverity) -> RiskLevel {
        switch severity {
        case .critical: return .critical
        case .important: return .medium
        case .minor: return .low
        }
    }
    
    
    private func colorsFor(metrics: PushUpMetrics, frontMetrics: FrontViewMetrics, postureMode: PushUpPostureMode) -> OverlayColors {
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
            let hipBase = calibrationHipDrop ?? pushUpConfig.hipBaseDefault
            let flareBase = calibrationElbowFlareRatio ?? pushUpConfig.flareBaseDefault
            let hipYellow = hipBase * sensitivity.yellowMultiplier
            let hipRed = hipBase * sensitivity.redMultiplier
            let flareYellow = flareBase * sensitivity.yellowMultiplier
            let flareRed = flareBase * sensitivity.redMultiplier
            
            if frontMetrics.elbowFlareRatio > flareRed {
                colors.leftArm = .red
                colors.rightArm = .red
            } else if frontMetrics.elbowFlareRatio > flareYellow {
                colors.leftArm = .yellow
                colors.rightArm = .yellow
            } else {
                colors.leftArm = .green
                colors.rightArm = .green
            }
            
            if feedbackFocus == .fullBody && !isPortraitMode {
                if frontMetrics.hipDropRatio > hipRed {
                    colors.torso = .red
                } else if frontMetrics.hipDropRatio > hipYellow {
                    colors.torso = .yellow
                } else {
                    colors.torso = .green
                }
            } else {
                colors.torso = .green
            }
        }
        
        return colors
    }
    
    private func depthProgressFor(currentAngle: Double, minAngle: Double, maxAngle: Double) -> Double {
        if maxAngle <= minAngle { return 0 }
        let progress = (maxAngle - currentAngle) / (maxAngle - minAngle)
        return max(0.0, min(1.0, progress))
    }
}
