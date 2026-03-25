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
    let repMetric: RepMetric?
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
    private var pendingFeedbackMessage: String = ""
    private var pendingFeedbackStartMS: Int64 = 0
    private var liveFeedbackLocked: Bool = false
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
    private var squatRepStartedSideView: Bool = false
    private var squatRepMaxKneeValgus: Double = 0
    private var squatRepMaxForwardLean: Double = 0
    private var squatRepMaxKneeForwardTravel: Double = 0
    private var squatCalibratedMinAngle: Double?
    private var squatCalibrationRepCount = 0
    private var squatCalibrationMinAngleSum: Double = 0
    private var squatAngleWindow: [Double] = []
    private var squatValgusWindow: [Double] = []
    private var squatLeanWindow: [Double] = []
    private var squatKneeTravelWindow: [Double] = []
    private let squatSmoothingWindow = 3
    private var lastSquatLogMS: Int = 0
    private var lastPushUpLogMS: Int = 0
    private var squatCalibratedLeanBaseline: Double?
    private var squatCalibratedKneeFwdBaseline: Double?
    private var squatCalibLeanSum: Double = 0
    private var squatCalibKneeFwdSum: Double = 0
    private var squatRepLeanAtMinAngle: Double = 0
    private var squatRepDownPhasePeakLean: Double = 0

    private var pullUpState: String = "DOWN"
    private var pullUpRepMinAngle: Double = 999
    private var pullUpRepStartMS: Int?
    private var pullUpRepMaxElbowAngle: Double = 0
    private var pullUpRepMaxShoulderAsym: Double = 0
    private var pullUpRepMaxElbowDiff: Double = 0
    private var pullUpRepMaxHipSwing: Double = 0
    private var pullUpRepMinShoulderEarGap: Double = 999
    private var pullUpRepMaxHeadOffset: Double = 0
    private var pullUpRepMaxElbowFlare: Double = 0
    
    private(set) var repCount: Int = 0
    private(set) var cleanReps: Int = 0
    private(set) var overallScore: Int = 0
    private(set) var depthProgress: Double = 0
    private(set) var overlayColors: OverlayColors = .neutral
    private(set) var feedbackMessage: String = "Searching..."
    private(set) var secondaryHint: String = ""
    private(set) var currentRisk: RiskLevel = .low
    private(set) var lastRepScore: Int = 0
    private(set) var lastRepAllMessages: [(message: String, severity: RuleSeverity)] = []
    private(set) var lastRepDurationSec: Double = 0
    private(set) var lastRepRuleIDs: Set<String> = []
    private(set) var lastRepDepthProgress: Double = 0
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
        squatRepStartedSideView = false
        squatRepMaxKneeValgus = 0
        squatRepMaxForwardLean = 0
        squatRepMaxKneeForwardTravel = 0
        squatCalibratedMinAngle = nil
        squatCalibrationRepCount = 0
        squatCalibrationMinAngleSum = 0
        squatCalibratedLeanBaseline = nil
        squatCalibratedKneeFwdBaseline = nil
        squatCalibLeanSum = 0
        squatCalibKneeFwdSum = 0
        squatRepLeanAtMinAngle = 0
        squatRepDownPhasePeakLean = 0
        squatAngleWindow.removeAll()
        squatValgusWindow.removeAll()
        squatLeanWindow.removeAll()
        squatKneeTravelWindow.removeAll()
        lastSquatLogMS = 0
        pullUpState = "DOWN"
        pullUpRepMinAngle = 999
        pullUpRepStartMS = nil
        pullUpRepMaxElbowAngle = 0
        pullUpRepMaxShoulderAsym = 0
        pullUpRepMaxElbowDiff = 0
        pullUpRepMaxHipSwing = 0
        pullUpRepMinShoulderEarGap = 999
        pullUpRepMaxHeadOffset = 0
        pullUpRepMaxElbowFlare = 0
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
                speakMessage: nil,
                repMetric: nil
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
        
        if (timestampMS - lastPushUpLogMS) >= 500 {
            lastPushUpLogMS = timestampMS
            print(String(
                format: "[PushUp:frame] mode=%@ state=%@ elbow=%.1f back=%.1f depth=%.2f flare=%.3f hipDrop=%.3f inRep=%d",
                "\(postureMode)",
                fsmCurrentState ?? "nil",
                smoothedMetrics.elbowFlexion,
                smoothedMetrics.backAngle,
                depthProgress,
                smoothedFront.elbowFlareRatio,
                smoothedFront.hipDropRatio,
                inRep ? 1 : 0
            ))
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
            speakMessage: speakMessage,
            repMetric: nil
        )
    }

    func updateSquat(landmarks: [NormalizedLandmark],
                     timestampMS: Int,
                     enableDebug: Bool,
                     viewMode: SquatViewMode) -> EngineOutput {
        lastTimestampMS = timestampMS
        debugEnabled = enableDebug
        var speakMessage: String?
        var repMetric: RepMetric?
        var matchedForScore: [FeedbackRule] = []
        let leftShoulder = landmarks[11]
        let rightShoulder = landmarks[12]
        let leftHip = landmarks[23]
        let rightHip = landmarks[24]
        let leftKnee = landmarks[25]
        let rightKnee = landmarks[26]
        let leftAnkle = landmarks[27]
        let rightAnkle = landmarks[28]

        let shoulderWidth = max(0.001, abs(Double(leftShoulder.x - rightShoulder.x)))
        let hipWidth = max(0.001, abs(Double(leftHip.x - rightHip.x)))
        let shoulderToHipRatio = shoulderWidth / hipWidth
        let sideView: Bool
        switch viewMode {
        case .auto:
            sideView = shoulderToHipRatio < 0.9
        case .front:
            sideView = false
        case .side:
            sideView = true
        }

        let leftHipVis = leftHip.visibility?.floatValue ?? 0
        let rightHipVis = rightHip.visibility?.floatValue ?? 0
        let leftKneeVis = leftKnee.visibility?.floatValue ?? 0
        let rightKneeVis = rightKnee.visibility?.floatValue ?? 0
        let leftAnkleVis = leftAnkle.visibility?.floatValue ?? 0
        let rightAnkleVis = rightAnkle.visibility?.floatValue ?? 0

        let bodyVisible: Bool
        if sideView {
            let leftVis = min(leftHipVis, leftKneeVis, leftAnkleVis)
            let rightVis = min(rightHipVis, rightKneeVis, rightAnkleVis)
            bodyVisible = max(leftVis, rightVis) >= 0.4
        } else {
            bodyVisible = min(leftHipVis, rightHipVis, leftKneeVis, rightKneeVis, leftAnkleVis, rightAnkleVis) >= 0.4
        }

        let useLeftSide = (leftHipVis + leftKneeVis + leftAnkleVis) >= (rightHipVis + rightKneeVis + rightAnkleVis)
        let sideShoulder = useLeftSide ? leftShoulder : rightShoulder
        let sideHip = useLeftSide ? leftHip : rightHip
        let sideKnee = useLeftSide ? leftKnee : rightKnee
        let sideAnkle = useLeftSide ? leftAnkle : rightAnkle

        let rawAngle = evaluator.calculateAngle(p1: sideHip, p2: sideKnee, p3: sideAnkle)
        let angle = smoothValue(&squatAngleWindow, rawAngle, maxCount: squatSmoothingWindow)
        let effectiveDepthThreshold = sideView ? squatConfig.depthThreshold : (squatConfig.depthThresholdFront ?? 120.0)
        let minAngleForDepth = squatCalibratedMinAngle ?? effectiveDepthThreshold
        depthProgress = depthProgressFor(currentAngle: angle, minAngle: minAngleForDepth, maxAngle: squatConfig.lockoutAngle)
        squatRepMinAngle = min(squatRepMinAngle, angle)

        let depthReached = angle <= effectiveDepthThreshold
        let lockoutAngle = squatConfig.lockoutAngle

        let torsoLength = max(0.001, sqrt(pow(Double(sideShoulder.x - sideHip.x), 2) + pow(Double(sideShoulder.y - sideHip.y), 2)))
        let leftKneeValgusRaw = max(0.0, Double(leftAnkle.x - leftKnee.x)) / max(0.001, hipWidth)
        let rightKneeValgusRaw = max(0.0, Double(rightKnee.x - rightAnkle.x)) / max(0.001, hipWidth)
        let rawKneeValgus = (sideView || hipWidth < 0.05) ? 0.0 : max(leftKneeValgusRaw, rightKneeValgusRaw)
        let rawForwardLean = sideView ? abs(Double(sideShoulder.x - sideHip.x)) / max(0.001, torsoLength) : 0.0
        let shinVertical = max(0.001, abs(Double(sideKnee.y - sideAnkle.y)))
        let shinHorizontal = abs(Double(sideKnee.x - sideAnkle.x))
        let rawKneeForwardTravel = sideView ? shinHorizontal / shinVertical : 0.0
        let kneeValgus = smoothValue(&squatValgusWindow, rawKneeValgus, maxCount: squatSmoothingWindow)
        let forwardLean = smoothValue(&squatLeanWindow, rawForwardLean, maxCount: squatSmoothingWindow)
        let kneeForwardTravel = smoothValue(&squatKneeTravelWindow, rawKneeForwardTravel, maxCount: squatSmoothingWindow)

        if (timestampMS - lastSquatLogMS) >= 500 {
            lastSquatLogMS = timestampMS
            let lKVis = leftKnee.visibility?.floatValue ?? 0
            let rKVis = rightKnee.visibility?.floatValue ?? 0
            let lAVis = leftAnkle.visibility?.floatValue ?? 0
            let rAVis = rightAnkle.visibility?.floatValue ?? 0
            print(String(
                format: "[Squat:frame] view=%@ state=%@ angle=%.1f depth=%.2f valgus=%.3f lean=%.3f kneeFwd=%.3f | lKnee=(%.3f,%.3f,vis=%.2f) rKnee=(%.3f,%.3f,vis=%.2f) | lAnkle=(%.3f,%.3f,vis=%.2f) rAnkle=(%.3f,%.3f,vis=%.2f) | lHip=(%.3f,%.3f) rHip=(%.3f,%.3f) | lShoulder=(%.3f,%.3f) hipW=%.3f",
                sideView ? "side" : "front",
                squatState,
                angle, depthProgress,
                kneeValgus, forwardLean, kneeForwardTravel,
                Double(leftKnee.x), Double(leftKnee.y), Double(lKVis),
                Double(rightKnee.x), Double(rightKnee.y), Double(rKVis),
                Double(leftAnkle.x), Double(leftAnkle.y), Double(lAVis),
                Double(rightAnkle.x), Double(rightAnkle.y), Double(rAVis),
                Double(leftHip.x), Double(leftHip.y),
                Double(rightHip.x), Double(rightHip.y),
                Double(leftShoulder.x), Double(leftShoulder.y),
                hipWidth
            ))
        }

        if squatRepStartMS != nil {
            let kneeVisL = leftKnee.visibility?.floatValue ?? 0
            let ankleVisL = leftAnkle.visibility?.floatValue ?? 0
            let kneeVisR = rightKnee.visibility?.floatValue ?? 0
            let ankleVisR = rightAnkle.visibility?.floatValue ?? 0
            let valgusLandmarksVisible = max(min(kneeVisL, ankleVisL), min(kneeVisR, ankleVisR)) >= 0.5
            if !squatRepStartedSideView && !sideView && hipWidth >= 0.05 && valgusLandmarksVisible && angle <= 120 {
                squatRepMaxKneeValgus = max(squatRepMaxKneeValgus, kneeValgus)
            }
            if squatRepStartedSideView && sideView && angle <= 140 {
                squatRepMaxForwardLean = max(squatRepMaxForwardLean, forwardLean)
            }
            if squatRepStartedSideView && sideView && angle <= 120 && kneeForwardTravel <= 2.5 {
                squatRepMaxKneeForwardTravel = max(squatRepMaxKneeForwardTravel, kneeForwardTravel)
            }
            if squatRepStartedSideView && sideView && angle <= squatRepMinAngle {
                squatRepLeanAtMinAngle = forwardLean
            }
            if squatRepStartedSideView && sideView && angle <= 110 {
                squatRepDownPhasePeakLean = max(squatRepDownPhasePeakLean, forwardLean)
            }
        }

        if squatState == "UP" {
            if squatRepStartMS == nil {
                squatRepStartMS = timestampMS
                switch viewMode {
                case .side:  squatRepStartedSideView = true
                case .front: squatRepStartedSideView = false
                case .auto:  squatRepStartedSideView = sideView
                }
                squatRepMaxKneeValgus = 0
                squatRepMaxForwardLean = 0
                squatRepMaxKneeForwardTravel = 0
            }
            if depthReached { squatState = "DOWN" }
            if shouldUpdateLiveFeedback(message: "Lower down") {
                updateFeedback(message: "Lower down", secondary: "", risk: .low)
            }
        } else {
            if angle >= lockoutAngle {
                let durationSec = squatRepStartMS.map { Double(timestampMS - $0) / 1000.0 } ?? 0
                let repDepthProgress = depthProgressFor(
                    currentAngle: squatRepMinAngle,
                    minAngle: minAngleForDepth,
                    maxAngle: squatConfig.lockoutAngle
                )
                let repDepthThreshold = squatRepStartedSideView ? squatConfig.depthThreshold : (squatConfig.depthThresholdFront ?? 120.0)
                let fullDepthTarget = squatRepStartedSideView ? 80.0 : 105.0
                let depthQuality = min(1.0, max(0.0, (repDepthThreshold - squatRepMinAngle) / max(1.0, repDepthThreshold - fullDepthTarget)))
                let squatPostureMode: PushUpPostureMode = squatRepStartedSideView ? .side : .front
                let pelvicTilt = squatRepMinAngle < 80.0
                    ? max(0.0, squatRepDownPhasePeakLean - squatRepLeanAtMinAngle)
                    : 0.0
                let repValues: [String: Double] = [
                    "depthProgress": repDepthProgress,
                    "depthQuality": depthQuality,
                    "tempoFast": (durationSec > 0 && durationSec < squatConfig.tempoMinSec) ? 1.0 : 0.0,
                    "bodyVisible": bodyVisible ? 1.0 : 0.0,
                    "kneeValgus": squatRepMaxKneeValgus,
                    "forwardLean": squatRepMaxForwardLean,
                    "kneeForwardTravel": squatRepMaxKneeForwardTravel,
                    "pelvicTilt": pelvicTilt
                ]

                matchedForScore = evaluateRules(values: repValues, postureMode: squatPostureMode, exerciseTag: "squat", rules: squatConfig.feedbackRules)
                let repScore = scoreForRules(matchedForScore)
                lastRepScore = repScore
                lastRepAllMessages = dedupeRules(matchedForScore.sorted { severityRank($0.severity) > severityRank($1.severity) }).map { ($0.message, $0.severity) }
                repScores.append(repScore)
                overallScore = repScores.isEmpty ? 0 : Int(Double(repScores.reduce(0, +)) / Double(repScores.count))

                if repScore >= 85 { cleanReps += 1 }
                repCount += 1
                let msg = messageForRules(matchedForScore)
                let sec = secondaryMessageForRules(matchedForScore)
                let repRisk: RiskLevel = matchedForScore.contains(where: { $0.severity == .critical }) ? .critical
                    : (matchedForScore.contains(where: { $0.severity == .important }) ? .medium : .low)
                updateFeedback(message: msg, secondary: sec, risk: repRisk, force: true)
                speakMessage = messageForAudio(matchedForScore)
                repMetric = RepMetric(
                    repIndex: repCount + 1,
                    timestampMS: timestampMS,
                    score: repScore,
                    primaryMessage: msg,
                    risk: repRisk,
                    depthProgress: repDepthProgress,
                    kneeValgus: squatRepMaxKneeValgus,
                    forwardLean: squatRepMaxForwardLean
                )
                let ruleIds = matchedForScore.map { $0.id }.joined(separator: ",")
                print(String(
                    format: "[Squat:rep] #%d view=%@ minAngle=%.1f depthQ=%.2f depthProg=%.2f maxValgus=%.3f maxLean=%.3f maxKneeFwd=%.3f pelvicTilt=%.3f tempo=%.2fs score=%d risk=%@ rules=[%@]",
                    repCount,
                    squatRepStartedSideView ? "side" : "front",
                    squatRepMinAngle,
                    depthQuality,
                    repDepthProgress,
                    squatRepMaxKneeValgus,
                    squatRepMaxForwardLean,
                    squatRepMaxKneeForwardTravel,
                    pelvicTilt,
                    durationSec,
                    repScore,
                    "\(repRisk)",
                    ruleIds.isEmpty ? "none" : ruleIds
                ))
                if debugEnabled {
                    let calibAngle = squatCalibratedMinAngle ?? 0
                    debugText = String(
                        format: "squat view=%@ ratio=%.2f depth=%.2f min=%.1f calib=%.1f valgus=%.2f lean=%.2f score=%d last=%d calibReps=%d/3",
                        viewMode == .auto ? (sideView ? "side" : "front") : viewMode.rawValue.lowercased(),
                        shoulderToHipRatio,
                        repDepthProgress,
                        squatRepMinAngle,
                        calibAngle,
                        squatRepMaxKneeValgus,
                        squatRepMaxForwardLean,
                        overallScore,
                        lastRepScore,
                        squatCalibrationRepCount
                    )
                }

                if squatCalibrationRepCount < 3 {
                    squatCalibrationRepCount += 1
                    squatCalibrationMinAngleSum += squatRepMinAngle
                    squatCalibLeanSum += squatRepMaxForwardLean
                    squatCalibKneeFwdSum += squatRepMaxKneeForwardTravel
                    if squatCalibrationRepCount == 3 {
                        squatCalibratedMinAngle = squatCalibrationMinAngleSum / 3.0
                        squatCalibratedLeanBaseline = squatCalibLeanSum / 3.0
                        squatCalibratedKneeFwdBaseline = squatCalibKneeFwdSum / 3.0
                        print(String(format: "[Squat:calib] leanBaseline=%.3f kneeFwdBaseline=%.3f", squatCalibratedLeanBaseline!, squatCalibratedKneeFwdBaseline!))
                    }
                    lastRepScore = 100
                    repScores[repScores.count - 1] = 100
                    overallScore = repScores.isEmpty ? 0 : Int(Double(repScores.reduce(0, +)) / Double(repScores.count))
                    secondaryHint = "Calibrating: \(squatCalibrationRepCount)/3"
                }
                squatState = "UP"
                squatRepMinAngle = 999
                squatRepStartMS = nil
                squatRepStartedSideView = false
                squatRepMaxKneeValgus = 0
                squatRepMaxForwardLean = 0
                squatRepLeanAtMinAngle = 0
                squatRepDownPhasePeakLean = 0

                if repCount >= targetReps {
                    isSessionComplete = true
                    sessionSummary = buildSessionSummary()
                }
            } else if shouldUpdateLiveFeedback(message: "Drive up") {
                updateFeedback(message: "Drive up", secondary: "", risk: .low)
            }
        }

        if debugEnabled {
            let calibAngle = squatCalibratedMinAngle ?? 0
            debugText = String(
                format: "squat view=%@ ratio=%.2f depth=%.2f min=%.1f calib=%.1f valgus=%.2f lean=%.2f score=%d last=%d",
                viewMode == .auto ? (sideView ? "side" : "front") : viewMode.rawValue.lowercased(),
                shoulderToHipRatio,
                depthProgress,
                squatRepMinAngle,
                calibAngle,
                squatRepMaxKneeValgus,
                squatRepMaxForwardLean,
                overallScore,
                lastRepScore
            )
        }

        overlayColors = colorsForSquat(rules: matchedForScore)
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
            speakMessage: speakMessage,
            repMetric: repMetric
        )
    }

    func updatePullUp(landmarks: [NormalizedLandmark],
                      timestampMS: Int) -> EngineOutput {
        lastTimestampMS = timestampMS
        let leftShoulder = landmarks[11]
        let rightShoulder = landmarks[12]
        let leftElbow = landmarks[13]
        let rightElbow = landmarks[14]
        let leftWrist = landmarks[15]
        let rightWrist = landmarks[16]
        let leftHip = landmarks[23]
        let rightHip = landmarks[24]
        let leftEar = landmarks[7]
        let rightEar = landmarks[8]
        let nose = landmarks[0]

        let leftShoulderVis = leftShoulder.visibility?.floatValue ?? 0
        let rightShoulderVis = rightShoulder.visibility?.floatValue ?? 0
        let leftElbowVis = leftElbow.visibility?.floatValue ?? 0
        let rightElbowVis = rightElbow.visibility?.floatValue ?? 0
        let leftWristVis = leftWrist.visibility?.floatValue ?? 0
        let rightWristVis = rightWrist.visibility?.floatValue ?? 0
        let bodyVisible = min(leftShoulderVis, rightShoulderVis, leftElbowVis, rightElbowVis, leftWristVis, rightWristVis) >= 0.4

        let leftElbowAngle = evaluator.calculateAngle(p1: leftShoulder, p2: leftElbow, p3: leftWrist)
        let rightElbowAngle = evaluator.calculateAngle(p1: rightShoulder, p2: rightElbow, p3: rightWrist)
        let angle = (leftElbowAngle + rightElbowAngle) / 2.0
        depthProgress = depthProgressFor(currentAngle: angle, minAngle: pullUpConfig.chinOverBarAngle, maxAngle: pullUpConfig.bottomAngle)
        pullUpRepMinAngle = min(pullUpRepMinAngle, angle)

        let topReached = angle <= pullUpConfig.chinOverBarAngle
        let bottomAngle = pullUpConfig.bottomAngle

        let shoulderWidth = max(0.001, abs(Double(leftShoulder.x - rightShoulder.x)))
        let shoulderAsym = abs(Double(leftShoulder.y - rightShoulder.y)) / shoulderWidth
        let elbowAngleDiff = abs(leftElbowAngle - rightElbowAngle)

        let shoulderMidX = (Double(leftShoulder.x) + Double(rightShoulder.x)) / 2.0
        let hipMidX = (Double(leftHip.x) + Double(rightHip.x)) / 2.0
        let hipSwing = abs(hipMidX - shoulderMidX) / shoulderWidth

        let maxElbowAngle = max(leftElbowAngle, rightElbowAngle)
        pullUpRepMaxElbowAngle = max(pullUpRepMaxElbowAngle, maxElbowAngle)

        let leftEarVis = leftEar.visibility?.floatValue ?? 0
        let rightEarVis = rightEar.visibility?.floatValue ?? 0
        let earVis = min(leftEarVis, rightEarVis)
        let leftGap = max(0.0, Double(leftShoulder.y - leftEar.y))
        let rightGap = max(0.0, Double(rightShoulder.y - rightEar.y))
        let shoulderEarGap = earVis >= 0.4 ? ((leftGap + rightGap) / 2.0) : 1.0

        let noseVis = nose.visibility?.floatValue ?? 0
        let headOffset = noseVis >= 0.4 ? abs(Double(nose.x) - shoulderMidX) / shoulderWidth : 0.0

        let leftElbowFlare = evaluator.calculateAngle(p1: leftHip, p2: leftShoulder, p3: leftElbow)
        let rightElbowFlare = evaluator.calculateAngle(p1: rightHip, p2: rightShoulder, p3: rightElbow)
        let elbowFlare = max(leftElbowFlare, rightElbowFlare)

        if pullUpRepStartMS != nil {
            pullUpRepMaxShoulderAsym = max(pullUpRepMaxShoulderAsym, shoulderAsym)
            pullUpRepMaxElbowDiff = max(pullUpRepMaxElbowDiff, elbowAngleDiff)
            pullUpRepMaxHipSwing = max(pullUpRepMaxHipSwing, hipSwing)
            pullUpRepMinShoulderEarGap = min(pullUpRepMinShoulderEarGap, shoulderEarGap)
            pullUpRepMaxHeadOffset = max(pullUpRepMaxHeadOffset, headOffset)
            pullUpRepMaxElbowFlare = max(pullUpRepMaxElbowFlare, elbowFlare)
        }

        let wristsBelow = leftWrist.y > leftShoulder.y && rightWrist.y > rightShoulder.y
        if wristsBelow {
            if shouldUpdateLiveFeedback(message: "Get onto the bar") {
                updateFeedback(message: "Get onto the bar", secondary: "", risk: .low)
            }
            overlayColors = colorsForRisk(.low, arms: true, legs: false)
            return EngineOutput(
                repCount: repCount,
                cleanReps: cleanReps,
                overallScore: overallScore,
                depthProgress: 0,
                overlayColors: overlayColors,
                feedbackMessage: feedbackMessage,
                secondaryHint: secondaryHint,
                currentRisk: currentRisk,
                lastRepScore: lastRepScore,
                isSessionComplete: isSessionComplete,
                sessionSummary: sessionSummary,
                debugText: debugText,
                speakMessage: nil,
                repMetric: nil
            )
        }

        if pullUpState == "DOWN" {
            if pullUpRepStartMS == nil {
                pullUpRepStartMS = timestampMS
                pullUpRepMaxElbowAngle = 0
                pullUpRepMaxShoulderAsym = 0
                pullUpRepMaxElbowDiff = 0
                pullUpRepMaxHipSwing = 0
                pullUpRepMinShoulderEarGap = 999
                pullUpRepMaxHeadOffset = 0
                pullUpRepMaxElbowFlare = 0
            }
            if topReached { pullUpState = "UP" }
            if shouldUpdateLiveFeedback(message: "Pull up") {
                updateFeedback(message: "Pull up", secondary: "", risk: .low)
            }
        } else {
            if angle >= bottomAngle {
                let durationSec = pullUpRepStartMS.map { Double(timestampMS - $0) / 1000.0 } ?? 0
                let repDepthProgress = depthProgressFor(
                    currentAngle: pullUpRepMinAngle,
                    minAngle: pullUpConfig.chinOverBarAngle,
                    maxAngle: pullUpConfig.bottomAngle
                )
                let repLockoutIncomplete = pullUpRepMaxElbowAngle < (pullUpConfig.bottomAngle - 10.0) ? 1.0 : 0.0
                let repValues: [String: Double] = [
                    "depthProgress": repDepthProgress,
                    "tempoFast": (durationSec > 0 && durationSec < pullUpConfig.tempoMinSec) ? 1.0 : 0.0,
                    "bodyVisible": bodyVisible ? 1.0 : 0.0,
                    "shoulderAsym": pullUpRepMaxShoulderAsym,
                    "elbowAngleDiff": pullUpRepMaxElbowDiff,
                    "hipSwing": pullUpRepMaxHipSwing,
                    "lockoutIncomplete": repLockoutIncomplete,
                    "shoulderEarGap": pullUpRepMinShoulderEarGap == 999 ? 1.0 : pullUpRepMinShoulderEarGap,
                    "headOffset": pullUpRepMaxHeadOffset,
                    "elbowFlare": pullUpRepMaxElbowFlare
                ]

                let matchedForScore = evaluateRules(values: repValues, postureMode: .front, exerciseTag: "pullup", rules: pullUpConfig.feedbackRules)
                let repScore = scoreForRules(matchedForScore)
                lastRepScore = repScore
                lastRepAllMessages = dedupeRules(matchedForScore.sorted { severityRank($0.severity) > severityRank($1.severity) }).map { ($0.message, $0.severity) }
                repScores.append(repScore)
                overallScore = repScores.isEmpty ? 0 : Int(Double(repScores.reduce(0, +)) / Double(repScores.count))

                if repScore >= 85 { cleanReps += 1 }
                repCount += 1
                let msg = messageForRules(matchedForScore)
                let sec = secondaryMessageForRules(matchedForScore)
                let repRisk: RiskLevel = matchedForScore.contains(where: { $0.severity == .critical }) ? .critical
                    : (matchedForScore.contains(where: { $0.severity == .important }) ? .medium : .low)
                updateFeedback(message: msg, secondary: sec, risk: repRisk, force: true)
                pullUpState = "DOWN"
                pullUpRepMinAngle = 999
                pullUpRepStartMS = nil
                pullUpRepMaxElbowAngle = 0
                pullUpRepMaxShoulderAsym = 0
                pullUpRepMaxElbowDiff = 0
                pullUpRepMaxHipSwing = 0
                pullUpRepMinShoulderEarGap = 999
                pullUpRepMaxHeadOffset = 0
                pullUpRepMaxElbowFlare = 0

                if repCount >= targetReps {
                    isSessionComplete = true
                    sessionSummary = buildSessionSummary()
                }
            } else if shouldUpdateLiveFeedback(message: "Lower under control") {
                updateFeedback(message: "Lower under control", secondary: "", risk: .low)
            }
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
            speakMessage: nil,
            repMetric: nil
        )
    }
    
    // MARK: - Internal Logic
    
    private var repCompletedMessage: String?
    
    private func resetRepMetrics() {
        repMinElbowAngle = 999
        repMaxElbowAngle = 0
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

    private func colorsForSquat(rules: [FeedbackRule]) -> OverlayColors {
        guard !rules.isEmpty else {
            return OverlayColors(
                leftArm: .white.opacity(0.6),
                rightArm: .white.opacity(0.6),
                torso: .white.opacity(0.6),
                leftLeg: .green,
                rightLeg: .green
            )
        }

        let sorted = rules.sorted { severityRank($0.severity) > severityRank($1.severity) }
        let primary = sorted[0]
        let color: Color
        switch primary.severity {
        case .critical: color = .red
        case .important: color = .orange
        case .minor: color = .yellow
        }

        var torso = Color.white.opacity(0.6)
        var legs = Color.white.opacity(0.6)
        switch primary.metric {
        case "forwardLean":
            torso = color
        case "kneeValgus", "shallowDepth", "depthProgress":
            legs = color
        default:
            legs = color
        }

        return OverlayColors(
            leftArm: .white.opacity(0.6),
            rightArm: .white.opacity(0.6),
            torso: torso,
            leftLeg: legs,
            rightLeg: legs
        )
    }
    
    private func emaFilter(previous: Double?, value: Double, dtSeconds: Double, tau: Double) -> Double {
        guard let previous = previous else { return value }
        let alpha = 1.0 - exp(-dtSeconds / tau)
        return (alpha * value) + ((1.0 - alpha) * previous)
    }

    private func smoothValue(_ window: inout [Double], _ value: Double, maxCount: Int) -> Double {
        window.append(value)
        if window.count > maxCount {
            window.removeFirst(window.count - maxCount)
        }
        let sum = window.reduce(0, +)
        return sum / Double(window.count)
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
                        liveFeedbackLocked = false
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
                    liveFeedbackLocked = false
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
            let savedLockout = repMaxElbowAngle
            resetRepMetrics()
            repMaxElbowAngle = savedLockout
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
        liveFeedbackLocked = false
        let durationMS = (repStartMS != nil && repEndMS != nil) ? max(1, (repEndMS! - repStartMS!)) : 1
        let durationSec = Double(durationMS) / 1000.0

        let depthThreshold = (postureMode == .front) ? pushUpConfig.depthFrontThreshold : pushUpConfig.depthSideThreshold
        let lockoutAngle = (postureMode == .front) ? pushUpConfig.lockoutFrontThreshold : pushUpConfig.lockoutSideThreshold
        let repDepthProgress = depthProgressFor(currentAngle: repMinElbowAngle, minAngle: depthThreshold, maxAngle: lockoutAngle)
        lastRepTooFast = durationSec < 0.3

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
        lastRepAllMessages = dedupeRules(matchedRules.sorted { severityRank($0.severity) > severityRank($1.severity) }).map { ($0.message, $0.severity) }
        lastRepDurationSec = durationSec
        lastRepRuleIDs = Set(matchedRules.map { $0.id })
        lastRepDepthProgress = repDepthProgress
        let ids = matchedRules.map { $0.id }.joined(separator: ",")
        print(String(format: "[PushUpRep] mode=%@ focus=%@ backAngle=%.1f elbow=%.1f matched=[%@] score=%d",
                     "\(ruleMode)", "\(feedbackFocus)", repMinBackAngle, repMinElbowAngle, ids, repScore))
        if debugEnabled {
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

        let audioMessage = messageForAudio(matchedRules)
        repCompletedMessage = "Rep \(repCount). \(audioMessage)"

        repMinBackAngle = 999

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

    private func messageForAudio(_ rules: [FeedbackRule]) -> String {
        guard !rules.isEmpty else { return "GOOD: Form is clean" }
        let sorted = rules.sorted { severityRank($0.severity) > severityRank($1.severity) }
        if let critical = sorted.first(where: { $0.severity == .critical }) {
            return "\(label(for: critical.severity)): \(critical.message)"
        }
        if let important = sorted.first(where: { $0.severity == .important }) {
            return "\(label(for: important.severity)): \(important.message)"
        }
        if let minor = sorted.first(where: { $0.severity == .minor }) {
            return "\(label(for: minor.severity)): \(minor.message)"
        }
        return "GOOD: Form is clean"
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

    private func shouldUpdateLiveFeedback(message: String) -> Bool {
        let now = Int64(lastTimestampMS ?? 0)
        if message == lastFeedbackMessage {
            pendingFeedbackMessage = ""
            pendingFeedbackStartMS = 0
            return true
        }
        if message == pendingFeedbackMessage {
            if (now - pendingFeedbackStartMS) >= 450 {
                pendingFeedbackMessage = ""
                pendingFeedbackStartMS = 0
                return true
            }
            return false
        }
        pendingFeedbackMessage = message
        pendingFeedbackStartMS = now
        return false
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
                if !liveFeedbackLocked && shouldUpdateLiveFeedback(message: hint) {
                    updateFeedback(message: hint, secondary: "", risk: .low)
                    liveFeedbackLocked = true
                }
            }
            return
        }

        let message = messageForRules(matched)
        let secondary = secondaryMessageForRules(matched)
        if let primary = matched.sorted(by: { severityRank($0.severity) > severityRank($1.severity) }).first {
            if inRep && primary.severity != .critical {
                if liveFeedbackLocked { return }
            }
            if shouldUpdateLiveFeedback(message: message) {
                updateFeedback(message: message, secondary: secondary, risk: riskLevel(for: primary.severity))
                if inRep && primary.severity != .critical {
                    liveFeedbackLocked = true
                }
            }
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
        let viewTags = ["front", "side"]
        let ruleHasViewTag = tags.contains(where: { viewTags.contains($0) })
        if ruleHasViewTag && !tags.contains(modeTag) {
            return false
        }
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
        switch rule.metric {
        case "forwardLean":
            if let base = squatCalibratedLeanBaseline {
                let mult: Double = (rule.severity == .critical) ? 1.3 : 1.1
                return max(rule.threshold, base * mult)
            }
            return rule.threshold
        case "kneeForwardTravel":
            if let base = squatCalibratedKneeFwdBaseline {
                let mult: Double = (rule.severity == .critical) ? 1.3 : 1.1
                return max(rule.threshold, base * mult)
            }
            return rule.threshold
        default:
            break
        }
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
                colors.hasCritical = true
            } else if metrics.backAngle < 165 {
                colors.torso = .yellow
            } else {
                colors.torso = .green
            }
            
            if metrics.elbowFlare > 75 {
                colors.leftArm = .red
                colors.rightArm = .red
                colors.hasCritical = true
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
                colors.hasCritical = true
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
                    colors.hasCritical = true
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
