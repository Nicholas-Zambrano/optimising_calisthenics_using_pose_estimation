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
    @Published var isDetectionPaused: Bool = true
    @Published var isCoachingActive: Bool = false
    var isProcessingFrame = false
    
    let evaluator = BiometricEvaluator()
    
    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpokenMessage = ""
    private var riskBuffer: [RiskLevel] = []
    
    private var angleBuffer : [Double] = []
    private let maxBufferSize = 10 // we are smoothing accross 0.3 secs of video
    
    override init() {
        super.init()
        setupLandmarker()
    }
    
    private func getSmoothedAngle(newAngle: Double) -> Double {
            angleBuffer.append(newAngle)
            if angleBuffer.count > maxBufferSize { angleBuffer.removeFirst() }
            let average = angleBuffer.reduce(0, +) / Double(angleBuffer.count)
            return average
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
                    if self.cameraPosition == .front {
                        connection.isVideoMirrored = true
                    }
                }
            }
            
            self.session.commitConfiguration()
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }


    func speakFeedback(_ message: String) {
        guard message != lastSpokenMessage, !synthesizer.isSpeaking else { return }
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
            
            // Hierarchy Lock: Safety-Critical errors take precedence
            if self.currentRisk == .critical && stableRisk != .low { return }
            
            DispatchQueue.main.async {
                if self.feedbackMessage != newMessage {
                    self.feedbackMessage = newMessage
                    self.currentRisk = stableRisk
                    self.speakFeedback(newMessage)
                }
            }
        }
    
    private func mostFrequentRisk(in buffer: [RiskLevel]) -> RiskLevel {
        let counts = buffer.reduce(into: [:]) { $0[$1, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key ?? .low
    }
    

    func poseLandmarker(_ poseLandmarker: PoseLandmarker, didFinishDetection result: PoseLandmarkerResult?, timestampInMilliseconds: Int, error: Error?) {
        
        guard let result = result, let landmarks = result.landmarks.first else {
            DispatchQueue.main.async {
                self.latestLandmarks = nil
                self.feedbackMessage = "Searching..."
                self.isProcessingFrame = false
            }
            return
        }

        var rawRisk: RiskLevel = .low
        var displayMessage: String = ""

        switch self.activeExercise {
        case "Push-Up":
            let rawAngle = self.evaluator.calculateAngle(p1: landmarks[12], p2: landmarks[24], p3: landmarks[28])
            let smoothed = self.getSmoothedAngle(newAngle: rawAngle)
            rawRisk = self.evaluator.checkPushUpForm(angle: smoothed)
            displayMessage = self.getPushUpFeedback(risk: rawRisk)
        
        case "Squat":
            let rawAngle = self.evaluator.calculateAngle(p1: landmarks[24], p2: landmarks[26], p3: landmarks[28])
            let smoothed = self.getSmoothedAngle(newAngle: rawAngle)
            rawRisk = self.evaluator.checkSquatForm(angle: smoothed)
            displayMessage = self.getSquatFeedback(risk: rawRisk)
            
        default: break
        }

        DispatchQueue.main.async {
            self.latestLandmarks = landmarks
            self.processPriorityFeedback(newRisk: rawRisk, newMessage: displayMessage)
            self.isProcessingFrame = false
        }
    }
    
    private func getPushUpFeedback(risk: RiskLevel) -> String {
        switch risk {
        case .critical: return "CRITICAL: FIX HIP SAG"
        case .medium: return "Keep core tighter"
        case .low: return "Form is Good"
        }
    }
    
    private func getSquatFeedback(risk: RiskLevel) -> String {
        switch risk {
        case .critical: return "CRITICAL: KNEE VALGUS"
        case .medium: return "Go deeper for full rep"
        case .low: return "Perfect Depth"
        }
    }

    private func getPullUpFeedback(risk: RiskLevel) -> String {
        switch risk {
        case .critical: return "CRITICAL: ASYMMETRY"
        case .medium: return "Pull chin higher"
        case .low: return "Great Pull"
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
}


extension PoseDetectionManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        Task { @MainActor in
            guard !isProcessingFrame else { return }
            
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let timestampInMS = Int(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1000)
            
            if let image = try? MPImage(pixelBuffer: pixelBuffer, orientation: .up) {
                isProcessingFrame = true
                
                do {
                    try self.poseLandmarker?.detectAsync(image: image, timestampInMilliseconds: timestampInMS)
                } catch {
                    print("Detection failed to start: \(error)")
                    isProcessingFrame = false
                }
            }
        }
    }
}
