import MediaPipeTasksVision
import AVFoundation
import SwiftUI
import Combine

class PoseDetectionManager: NSObject, PoseLandmarkerLiveStreamDelegate, ObservableObject {
    nonisolated(unsafe) var poseLandmarker: PoseLandmarker?
    
    @Published var session = AVCaptureSession()
    @Published var latestLandmarks: [NormalizedLandmark]?
    @Published var currentRisk: RiskLevel = .low
    @Published var feedbackMessage: String = "Searching..."
    @Published var activeExercise: String = "Push-Up"
    @Published var cameraPosition: AVCaptureDevice.Position = .front
    @Published var isFrontCamera: Bool = true
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
    @Published var isPortraitMode: Bool = true
    @Published var feedbackFocus: FeedbackFocus = .armsOnly
    
    var isProcessingFrame = false
    
    let evaluator = BiometricEvaluator()
    private let pushUpConfig = ExerciseDefinitionStore.shared.pushUp
    private let squatConfig = ExerciseDefinitionStore.shared.squat
    private let pullUpConfig = ExerciseDefinitionStore.shared.pullUp
    private lazy var engine = ExerciseEngine(
        evaluator: evaluator,
        pushUpConfig: pushUpConfig,
        squatConfig: squatConfig,
        pullUpConfig: pullUpConfig
    )
    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpokenMessage = ""

    private let enablePoseDebugLogs = true
    private var lastPoseMode: PushUpPostureMode = .none
    private var lastPoseModeTimestampMS: Int?

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
        feedbackMessage = "Get into push-up position"
        currentRisk = .low
        isSessionComplete = false
        sessionSummary = nil
        depthProgress = 0
        overlayColors = .neutral
        isDetectionPaused = false
        secondaryHint = ""
        engine.reset(targetReps: targetReps, sensitivity: sensitivity, focus: feedbackFocus, isPortraitMode: isPortraitMode)
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

    func stopSession() {
        isCoachingActive = false
        isDetectionPaused = true
        DispatchQueue.global(qos: .userInitiated).async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        lastSpokenMessage = ""
    }

    func processLandmarks(_ landmarks: [NormalizedLandmark], timestampMS: Int) {
        self.latestLandmarks = landmarks

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
                lastPoseModeTimestampMS = timestampMS
            } else if let lastTS = lastPoseModeTimestampMS,
                      (timestampMS - lastTS) <= 800 {
                effectivePostureMode = lastPoseMode
            } else {
                effectivePostureMode = .none
            }
            
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
            let leftHipVis = leftHip.visibility?.floatValue ?? 0
            let rightHipVis = rightHip.visibility?.floatValue ?? 0
            let leftAnkle = landmarks[27]
            let rightAnkle = landmarks[28]
            let leftAnkleVis = leftAnkle.visibility?.floatValue ?? 0
            let rightAnkleVis = rightAnkle.visibility?.floatValue ?? 0
            let anklesVisible = min(leftAnkleVis, rightAnkleVis) >= 0.4
            let hipsVisible = min(leftHipVis, rightHipVis) >= 0.5 && anklesVisible
            let leftWristVis = landmarks[15].visibility?.floatValue ?? 0
            let rightWristVis = landmarks[16].visibility?.floatValue ?? 0
            let leftElbowVis = landmarks[13].visibility?.floatValue ?? 0
            let rightElbowVis = landmarks[14].visibility?.floatValue ?? 0
            let armsVisible = [leftWristVis, rightWristVis, leftElbowVis, rightElbowVis].min() ?? 0 >= 0.5
            
            let shoulderWidth = max(0.001, abs(Double(leftShoulder.x - rightShoulder.x)))
            let torsoLength = max(0.001, sqrt(pow(Double(shoulderMid.x - hipMid.x), 2) + pow(Double(shoulderMid.y - hipMid.y), 2)))
            let hipDropRatio = max(0.0, (Double(hipMid.y - shoulderMid.y)) / torsoLength)
            let hipRiseRatio = max(0.0, (Double(shoulderMid.y - hipMid.y)) / torsoLength)
            let elbowFlareRatio = min(1.0, abs(Double(wrist.x - shoulder.x)) / shoulderWidth)
            let shoulderAsym = abs(Double(leftShoulder.y - rightShoulder.y)) / torsoLength
            let hipAsym = abs(Double(leftHip.y - rightHip.y)) / torsoLength
            let frontMetrics = FrontViewMetrics(
                hipDropRatio: hipDropRatio,
                hipRiseRatio: hipRiseRatio,
                elbowFlareRatio: elbowFlareRatio,
                shoulderAsym: shoulderAsym,
                hipAsym: hipAsym,
                hipsVisible: hipsVisible,
                anklesVisible: anklesVisible,
                armsVisible: armsVisible
            )
            if enablePoseDebugLogs {
                if !armsVisible {
                    self.debugText = "Arms not visible — move closer"
                }
            }
            
            let leftElbowAngle = self.evaluator.calculateAngle(p1: leftShoulder, p2: landmarks[13], p3: landmarks[15])
            let rightElbowAngle = self.evaluator.calculateAngle(p1: rightShoulder, p2: landmarks[14], p3: landmarks[16])
            let elbowAngleDiff = abs(leftElbowAngle - rightElbowAngle)

            let output = engine.updatePushUp(
                metrics: metrics,
                frontMetrics: frontMetrics,
                elbowAngleDiff: elbowAngleDiff,
                postureMode: effectivePostureMode,
                timestampMS: timestampMS,
                isPortraitMode: self.isPortraitMode,
                sensitivity: self.sensitivity,
                feedbackFocus: self.feedbackFocus,
                enableDebug: enablePoseDebugLogs
            )
            
            repCount = output.repCount
            cleanReps = output.cleanReps
            overallScore = output.overallScore
            depthProgress = output.depthProgress
            overlayColors = output.overlayColors
            feedbackMessage = output.feedbackMessage
            secondaryHint = output.secondaryHint
            currentRisk = output.currentRisk
            lastRepScore = output.lastRepScore
            isSessionComplete = output.isSessionComplete
            sessionSummary = output.sessionSummary
            debugText = output.debugText
            
            if let speak = output.speakMessage, isCoachingActive {
                speakFeedback(speak, force: true)
            }
            
            if isSessionComplete {
                endSession()
            }

        case "Squat":
            let leftHip = landmarks[23]
            let rightHip = landmarks[24]
            let leftShoulder = landmarks[11]
            let rightShoulder = landmarks[12]
            let hipWidth = max(0.001, abs(Double(leftHip.x - rightHip.x)))
            let torsoLength = max(0.001, sqrt(pow(Double(rightShoulder.x - rightHip.x), 2) + pow(Double(rightShoulder.y - rightHip.y), 2)))
            let output = engine.updateSquat(
                shoulder: rightShoulder,
                hip: rightHip,
                knee: landmarks[26],
                ankle: landmarks[28],
                hipWidth: hipWidth,
                torsoLength: torsoLength,
                timestampMS: timestampMS
            )
            repCount = output.repCount
            cleanReps = output.cleanReps
            overallScore = output.overallScore
            depthProgress = output.depthProgress
            overlayColors = output.overlayColors
            feedbackMessage = output.feedbackMessage
            secondaryHint = output.secondaryHint
            currentRisk = output.currentRisk
            lastRepScore = output.lastRepScore
            isSessionComplete = output.isSessionComplete
            sessionSummary = output.sessionSummary
            debugText = output.debugText

        case "Pull-Up":
            let output = engine.updatePullUp(
                shoulder: landmarks[12],
                elbow: landmarks[14],
                wrist: landmarks[16],
                timestampMS: timestampMS
            )
            repCount = output.repCount
            cleanReps = output.cleanReps
            overallScore = output.overallScore
            depthProgress = output.depthProgress
            overlayColors = output.overlayColors
            feedbackMessage = output.feedbackMessage
            secondaryHint = output.secondaryHint
            currentRisk = output.currentRisk
            lastRepScore = output.lastRepScore
            isSessionComplete = output.isSessionComplete
            sessionSummary = output.sessionSummary
            debugText = output.debugText
        default: break
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

            self.processLandmarks(landmarks, timestampMS: timestampInMilliseconds)
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
        isFrontCamera = (cameraPosition == .front)
        isDetectionPaused = true
        latestLandmarks = nil
        repCount = 0
        cleanReps = 0
        overallScore = 0
        lastRepScore = 0
        depthProgress = 0
        overlayColors = .neutral
        secondaryHint = ""
        feedbackMessage = "Get into push-up position"
        currentRisk = .low
        engine.reset(targetReps: targetReps, sensitivity: sensitivity, focus: feedbackFocus, isPortraitMode: isPortraitMode)
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.stopRunning()
            self.startCamera()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isDetectionPaused = false
            }
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
            self.isFrontCamera = (self.cameraPosition == .front)
            
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
            
            if self.session.canAddOutput(videoOutput) {
                self.session.addOutput(videoOutput)
                if let connection = videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                    if connection.isVideoMirroringSupported { connection.isVideoMirrored = false }
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
