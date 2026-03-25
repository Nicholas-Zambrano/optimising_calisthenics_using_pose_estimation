import Foundation
import AVFoundation
import MediaPipeTasksVision
import UIKit
import Combine
import SwiftUI

final class OfflineAnalysisManager: ObservableObject {
    struct RepSummary: Identifiable {
        let id = UUID()
        let repIndex: Int
        let timestampMS: Int
        let peakTimestampMS: Int
        let score: Int
        let primaryMessage: String
        let allMessages: [(message: String, severity: RuleSeverity)]
        let risk: RiskLevel
        let snapshot: UIImage?
        let angleSamples: [Double]
        let worstFormTimestampMS: Int
        
        var timestampLabel: String {
            let totalSec = max(0, timestampMS / 1000)
            let minutes = totalSec / 60
            let seconds = totalSec % 60
            return String(format: "%d:%02d", minutes, seconds)
        }
        
        var riskLabel: String {
            switch risk {
            case .critical: return "Critical"
            case .medium: return "Important"
            case .low: return allMessages.isEmpty ? "Clean" : "Minor"
            }
        }
    }
    @Published var progress: Double = 0
    @Published var status: String = "Idle"
    @Published var isRunning: Bool = false
    @Published var isExporting: Bool = false
    @Published var sessionSummary: SessionSummary?
    @Published var bestSnapshot: UIImage?
    @Published var worstSnapshot: UIImage?
    @Published var logLines: [String] = []
    @Published var mirrorOverlay: Bool = false
    @Published var repSummaries: [RepSummary] = []

    private let ciContext = CIContext()
    
    private var isCancelled = false
    private var bestScore: Int = -1
    private var worstScore: Int = 101
    private var worstRisk: RiskLevel = .low
    private var loggedFirstSnapshot = false
    
    func cancel() {
        isCancelled = true
    }
    
    func analyseVideo(url: URL, exercise: String, settings: AppSettings) {
        isCancelled = false
        progress = 0
        sessionSummary = nil
        bestSnapshot = nil
        worstSnapshot = nil
        bestScore = -1
        worstScore = 101
        worstRisk = .low
        loggedFirstSnapshot = false
        repSummaries = []
        status = "Preparing video..."
        logLines = []
        isRunning = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVAsset(url: url)
            guard let track = asset.tracks(withMediaType: .video).first else {
                DispatchQueue.main.async {
                    self.status = "No video track found"
                    self.isRunning = false
                }
                return
            }
            
            let durationSec = CMTimeGetSeconds(asset.duration)
            let naturalSize = track.naturalSize
            let preferredTransform = track.preferredTransform
            let videoSize = self.transformedSize(naturalSize, preferredTransform)
            let isPortrait = videoSize.height >= videoSize.width
            
            let reader: AVAssetReader
            do {
                reader = try AVAssetReader(asset: asset)
            } catch {
                DispatchQueue.main.async {
                    self.status = "Failed to read video"
                    self.isRunning = false
                }
                return
            }
            
            let outputSettings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            let composition = AVMutableVideoComposition()
            composition.renderSize = videoSize
            composition.frameDuration = CMTime(value: 1, timescale: 30)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            layerInstruction.setTransform(track.preferredTransform, at: .zero)
            instruction.layerInstructions = [layerInstruction]
            composition.instructions = [instruction]
            let output = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: outputSettings)
            output.videoComposition = composition
            output.alwaysCopiesSampleData = false
            if reader.canAdd(output) { reader.add(output) }
            
            let poseOptions = PoseLandmarkerOptions()
            if let modelPath = Bundle.main.path(forResource: "pose_landmarker_lite", ofType: "task") {
                poseOptions.baseOptions.modelAssetPath = modelPath
            }
            poseOptions.runningMode = .video
            let poseLandmarker: PoseLandmarker
            do {
                poseLandmarker = try PoseLandmarker(options: poseOptions)
            } catch {
                DispatchQueue.main.async {
                    self.status = "Failed to init pose model"
                    self.isRunning = false
                }
                return
            }
            
            let processor = PoseDetectionManager()
            processor.activeExercise = exercise
            processor.isPortraitMode = isPortrait
            processor.sensitivity = settings.sensitivity
            processor.feedbackFocus = settings.focus
            processor.isCoachingActive = false
            processor.resetForNewSession(targetReps: settings.targetReps, sensitivity: settings.sensitivity)
            
            if !reader.startReading() {
                DispatchQueue.main.async {
                    self.status = "Failed to start reader"
                    self.isRunning = false
                }
                return
            }
            
            DispatchQueue.main.async {
                self.logLines.append("Offline analysis using video composition transform")
                self.logLines.append("naturalSize=\(naturalSize.width)x\(naturalSize.height) videoSize=\(videoSize.width)x\(videoSize.height)")
                self.logLines.append("transform=\(preferredTransform)")
            }
            
            var lastProcessedMS: Int = 0
            let frameIntervalMS = 100
            var lastRepCount = 0
            var currentRepMaxDepth: Double = 0.0
            var currentRepSnapshot: UIImage?
            var currentRepWorstRiskFrame: UIImage?
            var currentRepWorstRiskTimestampMS: Int = 0
            var currentRepPeakTimestampMS: Int = 0
            var currentRepAngleSamples: [Double] = []
            var lastLogMS: Int = 0
            var lastRepCompletionMS: Int = -1000
            
            DispatchQueue.main.async {
                self.status = "Analysing..."
                self.logLines.append("Analysis started")
            }
            
            let startWall = Date()
            while reader.status == .reading, !self.isCancelled {
                guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
                autoreleasepool {
                    if Date().timeIntervalSince(startWall) > max(30.0, durationSec * 3.0) {
                        reader.cancelReading()
                        return
                    }
                    let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    let tsMS = Int(CMTimeGetSeconds(ts) * 1000)
                    if tsMS - lastProcessedMS < frameIntervalMS { return }
                    lastProcessedMS = tsMS
                    
                    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
                    guard let image = try? MPImage(pixelBuffer: pixelBuffer, orientation: .up) else { return }
                    if let result = try? poseLandmarker.detect(videoFrame: image, timestampInMilliseconds: tsMS),
                       let landmarks = result.landmarks.first {
                        if !self.isEngagedForExercise(exercise: exercise, landmarks: landmarks) {
                            return
                        }
                        if tsMS - lastLogMS >= 1000 {
                            lastLogMS = tsMS
                            let w = CVPixelBufferGetWidth(pixelBuffer)
                            let h = CVPixelBufferGetHeight(pixelBuffer)
                            DispatchQueue.main.async {
                                self.logLines.append("t=\(tsMS)ms buffer=\(w)x\(h) reps=\(processor.repCount)")
                            }
                        }
                        let processed = self.processOnMain(processor: processor, landmarks: landmarks, timestampMS: tsMS)
                        if processed.depthProgress >= currentRepMaxDepth && processed.depthProgress > 0.5 {
                            currentRepMaxDepth = processed.depthProgress
                            currentRepPeakTimestampMS = tsMS
                            currentRepSnapshot = self.renderAnnotatedFrame(
                                pixelBuffer: pixelBuffer,
                                landmarks: landmarks,
                                overlayColors: processed.overlayColors
                            )
                        }
                        if processed.overlayColors.hasCritical
                            && processed.depthProgress > 0.08
                            && currentRepWorstRiskFrame == nil
                            && (tsMS - lastRepCompletionMS) > 600 {
                            currentRepWorstRiskFrame = self.renderAnnotatedFrame(
                                pixelBuffer: pixelBuffer,
                                landmarks: landmarks,
                                overlayColors: processed.overlayColors
                            )
                            currentRepWorstRiskTimestampMS = tsMS
                        }
                        if let angle = self.primaryAngle(exercise: exercise, landmarks: landmarks),
                           processed.depthProgress > 0.05 || (!currentRepAngleSamples.isEmpty) {
                            currentRepAngleSamples.append(angle)
                        }

                        if processed.repCount > lastRepCount {
                            lastRepCount = processed.repCount
                            let allMsgs = processed.allMessages
                            var repScore = 100
                            for msg in allMsgs {
                                switch msg.severity {
                                case .critical: repScore -= 35
                                case .important: repScore -= 15
                                case .minor: repScore -= 5
                                }
                            }
                            repScore = max(0, min(100, repScore))
                            if repScore >= 10 {
                                let hasCritical = allMsgs.contains(where: { $0.severity == .critical })
                            let frame = (hasCritical ? currentRepWorstRiskFrame : nil)
                                ?? currentRepSnapshot
                                ?? self.renderAnnotatedFrame(
                                    pixelBuffer: pixelBuffer,
                                    landmarks: landmarks,
                                    overlayColors: processed.overlayColors
                                )
                                let worstTS = hasCritical && currentRepWorstRiskTimestampMS > 0 ? currentRepWorstRiskTimestampMS : (currentRepPeakTimestampMS > 0 ? currentRepPeakTimestampMS : tsMS)
                                let summary = RepSummary(
                                    repIndex: processed.repCount,
                                    timestampMS: tsMS,
                                    peakTimestampMS: currentRepPeakTimestampMS > 0 ? currentRepPeakTimestampMS : tsMS,
                                    score: repScore,
                                    primaryMessage: processed.feedbackMessage,
                                    allMessages: processed.allMessages,
                                    risk: processed.risk,
                                    snapshot: frame,
                                    angleSamples: currentRepAngleSamples,
                                    worstFormTimestampMS: worstTS
                                )
                                DispatchQueue.main.async {
                                    self.repSummaries.append(summary)
                                }
                                if let frame = frame {
                                    DispatchQueue.main.async {
                                        if repScore >= self.bestScore {
                                            self.bestScore = repScore
                                            self.bestSnapshot = frame
                                        }
                                        let riskRank = { (r: RiskLevel) -> Int in r == .critical ? 2 : (r == .medium ? 1 : 0) }
                                        let newRank = riskRank(processed.risk)
                                        let curRank = riskRank(self.worstRisk)
                                        if repScore < self.worstScore || (repScore == self.worstScore && newRank > curRank) {
                                            self.worstScore = repScore
                                            self.worstRisk = processed.risk
                                            self.worstSnapshot = frame
                                        }
                                    }
                                }
                            }
                            lastRepCompletionMS = tsMS
                            currentRepMaxDepth = 0.0
                            currentRepSnapshot = nil
                            currentRepWorstRiskFrame = nil
                            currentRepWorstRiskTimestampMS = 0
                            currentRepPeakTimestampMS = 0
                            currentRepAngleSamples = []
                        }
                        
                        if !self.loggedFirstSnapshot, let frame = currentRepSnapshot ?? self.bestSnapshot ?? self.worstSnapshot {
                            self.loggedFirstSnapshot = true
                            DispatchQueue.main.async {
                                self.logLines.append("snapshot size=\(Int(frame.size.width))x\(Int(frame.size.height)) mirror=\(self.mirrorOverlay)")
                            }
                        }
                    }
                    
                    let currentSec = CMTimeGetSeconds(ts)
                    let p = durationSec > 0 ? min(1.0, currentSec / durationSec) : 0
                    DispatchQueue.main.async {
                        self.progress = p
                    }
                }
            }
            
            DispatchQueue.main.async {
                if self.isCancelled {
                    self.status = "Cancelled"
                    self.logLines.append("Analysis cancelled")
                } else {
                    self.status = "Complete"
                    self.logLines.append("Analysis complete")
                }
                if self.sessionSummary == nil && !self.repSummaries.isEmpty {
                    let scores = self.repSummaries.map { $0.score }
                    let total = self.repSummaries.count
                    let avg = scores.reduce(0, +) / max(1, total)
                    let clean = self.repSummaries.filter { $0.allMessages.isEmpty }.count
                    let problemReps = self.repSummaries.filter { !$0.allMessages.isEmpty }
                    let severityRank: (RiskLevel) -> Int = { r in r == .critical ? 2 : (r == .medium ? 1 : 0) }
                    let common: String? = {
                        guard !problemReps.isEmpty else { return nil }
                        let msgs = problemReps.map { $0.primaryMessage }.filter { !$0.isEmpty }
                        guard !msgs.isEmpty else { return nil }
                        let grouped = Dictionary(grouping: msgs, by: { $0 })
                        let topMsg = grouped.max(by: { a, b in
                            if a.value.count != b.value.count { return a.value.count < b.value.count }
                            let rankA = problemReps.first(where: { $0.primaryMessage == a.key }).map { severityRank($0.risk) } ?? 0
                            let rankB = problemReps.first(where: { $0.primaryMessage == b.key }).map { severityRank($0.risk) } ?? 0
                            return rankA < rankB
                        })?.key
                        return topMsg
                    }()
                    self.sessionSummary = SessionSummary(
                        totalReps: total,
                        averageScore: avg,
                        cleanReps: clean,
                        bestRep: scores.max() ?? 0,
                        worstRep: scores.min() ?? 0,
                        mostCommonIssueMessage: common
                    )
                }
                self.isRunning = false
            }
        }
    }

    func exportAnnotatedVideo(url: URL, exercise: String, settings: AppSettings, completion: @escaping (URL?) -> Void) {
        isCancelled = false
        isExporting = true
        status = "Exporting annotated video..."
        logLines.append("Export started")
        
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVAsset(url: url)
            guard let track = asset.tracks(withMediaType: .video).first else {
                DispatchQueue.main.async {
                    self.status = "No video track found"
                    self.isExporting = false
                    completion(nil)
                }
                return
            }
            
            let reader: AVAssetReader
            do {
                reader = try AVAssetReader(asset: asset)
            } catch {
                DispatchQueue.main.async {
                    self.status = "Failed to read video"
                    self.isExporting = false
                    completion(nil)
                }
                return
            }
            
            let outputSettings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            let preferredTransform = track.preferredTransform
            let videoSize = self.transformedSize(track.naturalSize, preferredTransform)
            let width = Int(videoSize.width)
            let height = Int(videoSize.height)
            let composition = AVMutableVideoComposition()
            composition.renderSize = videoSize
            composition.frameDuration = CMTime(value: 1, timescale: 30)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            layerInstruction.setTransform(track.preferredTransform, at: .zero)
            instruction.layerInstructions = [layerInstruction]
            composition.instructions = [instruction]
            let output = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: outputSettings)
            output.videoComposition = composition
            output.alwaysCopiesSampleData = false
            if reader.canAdd(output) { reader.add(output) }
            
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("annotated_\(UUID().uuidString).mp4")
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try? FileManager.default.removeItem(at: tempURL)
            }
            
            let writer: AVAssetWriter
            do {
                writer = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)
            } catch {
                DispatchQueue.main.async {
                    self.status = "Failed to create writer"
                    self.isExporting = false
                    completion(nil)
                }
                return
            }
            
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
            let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            writerInput.expectsMediaDataInRealTime = false
            
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: writerInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height
                ]
            )
            
            if writer.canAdd(writerInput) { writer.add(writerInput) }
            
            let poseOptions = PoseLandmarkerOptions()
            if let modelPath = Bundle.main.path(forResource: "pose_landmarker_lite", ofType: "task") {
                poseOptions.baseOptions.modelAssetPath = modelPath
            }
            poseOptions.runningMode = .video
            let poseLandmarker: PoseLandmarker
            do {
                poseLandmarker = try PoseLandmarker(options: poseOptions)
            } catch {
                DispatchQueue.main.async {
                    self.status = "Failed to init pose model"
                    self.isExporting = false
                    completion(nil)
                }
                return
            }
            
            let processor = PoseDetectionManager()
            processor.activeExercise = exercise
            processor.isPortraitMode = videoSize.height >= videoSize.width
            processor.sensitivity = settings.sensitivity
            processor.feedbackFocus = settings.focus
            processor.isCoachingActive = false
            processor.resetForNewSession(targetReps: settings.targetReps, sensitivity: settings.sensitivity)
            DispatchQueue.main.async {
                self.repSummaries = []
            }
            
            if !reader.startReading() {
                DispatchQueue.main.async {
                    self.status = "Failed to start reader"
                    self.isExporting = false
                    completion(nil)
                }
                return
            }
            
            DispatchQueue.main.async {
                self.logLines.append("Export using video composition transform")
            }
            
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)
            
            let frameIntervalMS = 150
            var lastProcessedMS = 0
            
            let startWall = Date()
            while reader.status == .reading && !self.isCancelled {
                if !writerInput.isReadyForMoreMediaData {
                    usleep(2_000)
                    continue
                }
                guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
                autoreleasepool {
                    if Date().timeIntervalSince(startWall) > max(30.0, CMTimeGetSeconds(asset.duration) * 3.0) {
                        reader.cancelReading()
                        return
                    }
                    let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    let tsMS = Int(CMTimeGetSeconds(ts) * 1000)
                    if tsMS - lastProcessedMS < frameIntervalMS { return }
                    lastProcessedMS = tsMS
                    
                    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
                    guard let image = try? MPImage(pixelBuffer: pixelBuffer, orientation: .up) else { return }
                    guard let result = try? poseLandmarker.detect(videoFrame: image, timestampInMilliseconds: tsMS),
                          let landmarks = result.landmarks.first else { return }

                    let engaged = self.isEngagedForExercise(exercise: exercise, landmarks: landmarks)
                    let processed = engaged ? self.processOnMain(processor: processor, landmarks: landmarks, timestampMS: tsMS) : nil
                    guard let pool = adaptor.pixelBufferPool else { return }
                    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                    if let outBuffer = self.makePixelBuffer(from: ciImage, pool: pool) {
                        if let processed = processed {
                            self.drawOverlay(
                                on: outBuffer,
                                landmarks: landmarks,
                                overlayColors: processed.overlayColors,
                                message: processed.feedbackMessage,
                                score: processed.lastRepScore,
                                risk: processed.risk
                            )
                        } else {
                            self.drawOverlay(
                                on: outBuffer,
                                landmarks: landmarks,
                                overlayColors: .neutral,
                                message: "",
                                score: -1,
                                risk: .low
                            )
                        }
                        adaptor.append(outBuffer, withPresentationTime: ts)
                    }
                }
            }
            
            writerInput.markAsFinished()
            writer.finishWriting {
                DispatchQueue.main.async {
                    if reader.status == .failed {
                        self.status = "Export failed: reader error"
                        self.logLines.append("Export failed: reader error")
                    } else if writer.status == .failed {
                        self.status = "Export failed: writer error"
                        self.logLines.append("Export failed: writer error")
                    }
                    self.isExporting = false
                    self.status = "Export complete"
                    self.logLines.append("Export complete")
                    completion(tempURL)
                }
            }
        }
    }

    
    private func renderAnnotatedFrame(pixelBuffer: CVPixelBuffer,
                                      landmarks: [NormalizedLandmark],
                                      overlayColors: OverlayColors) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ciImage.extent.integral
        guard let cgImage = ciContext.createCGImage(ciImage, from: extent) else { return nil }
        
        let videoImage = UIImage(cgImage: cgImage)
        let imageSize = videoImage.size
        
        UIGraphicsBeginImageContextWithOptions(imageSize, true, 1.0)
        
        videoImage.draw(in: CGRect(origin: .zero, size: imageSize))
        
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
        ctx.setLineWidth(5.0)
        
        let points = landmarks.map { landmark -> CGPoint in
            let x = CGFloat(landmark.x) * imageSize.width
            let y = CGFloat(landmark.y) * imageSize.height
            if mirrorOverlay {
                return CGPoint(x: imageSize.width - x, y: y)
            }
            return CGPoint(x: x, y: y)
        }
        
        let connections: [(Int, Int)] = [
            (11, 13), (13, 15), (12, 14), (14, 16),
            (11, 12), (11, 23), (12, 24), (23, 24),
            (23, 25), (25, 27), (24, 26), (26, 28)
        ]
        for (a, b) in connections {
            guard a < points.count, b < points.count else { continue }
            ctx.setStrokeColor(colorFor(connection: (a, b), overlayColors: overlayColors).cgColor)
            ctx.move(to: points[a])
            ctx.addLine(to: points[b])
            ctx.strokePath()
        }
        
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result
    }

    private func makePixelBuffer(from image: UIImage, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        guard let pool = pool else { return nil }
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard let buffer = pixelBuffer else { return nil }
        
        guard let ciImage = CIImage(image: image) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        ciContext.render(ciImage, to: buffer, bounds: rect, colorSpace: CGColorSpaceCreateDeviceRGB())
        return buffer
    }

    private func makePixelBuffer(from ciImage: CIImage, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        guard let pool = pool else { return nil }
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard let buffer = pixelBuffer else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        ciContext.render(ciImage, to: buffer, bounds: rect, colorSpace: CGColorSpaceCreateDeviceRGB())
        return buffer
    }
    
//    private func drawOverlay(on pixelBuffer: CVPixelBuffer,
//                             landmarks: [NormalizedLandmark],
//                             overlayColors: OverlayColors,
//                             message: String,
//                             score: Int,
//                             risk: RiskLevel) {
//        CVPixelBufferLockBaseAddress(pixelBuffer, [])
//        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
//
//        let width = CVPixelBufferGetWidth(pixelBuffer)
//        let height = CVPixelBufferGetHeight(pixelBuffer)
//        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
//
//        let colorSpace = CGColorSpaceCreateDeviceRGB()
//        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
//        guard let ctx = CGContext(
//            data: baseAddress,
//            width: width,
//            height: height,
//            bitsPerComponent: 8,
//            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
//            space: colorSpace,
//            bitmapInfo: bitmapInfo
//        ) else { return }
//
//        ctx.translateBy(x: 0, y: CGFloat(height))
//        ctx.scaleBy(x: 1.0, y: -1.0)
//        ctx.setLineWidth(3.0)
//
//        let imageSize = CGSize(width: width, height: height)
//        let points = landmarks.map { landmark -> CGPoint in
//            let x = CGFloat(landmark.x) * imageSize.width
//            let y = CGFloat(landmark.y) * imageSize.height
//            if mirrorOverlay {
//                return CGPoint(x: imageSize.width - x, y: y)
//            }
//            return CGPoint(x: x, y: y)
//        }
//        let connections: [(Int, Int)] = [
//            (11, 13), (13, 15),
//            (12, 14), (14, 16),
//            (11, 12), (11, 23), (12, 24),
//            (23, 24),
//            (23, 25), (25, 27),
//            (24, 26), (26, 28)
//        ]
//        for (a, b) in connections {
//            guard a < points.count, b < points.count else { continue }
//            ctx.setStrokeColor(colorFor(connection: (a, b), overlayColors: overlayColors).cgColor)
//            ctx.move(to: points[a])
//            ctx.addLine(to: points[b])
//            ctx.strokePath()
//        }
//
//        ctx.scaleBy(x: 1.0, y: -1.0)
//        ctx.translateBy(x: 0, y: -CGFloat(height))
//        UIGraphicsPushContext(ctx)
//        let color: UIColor = (risk == .critical) ? .systemRed : (risk == .medium ? .systemOrange : .systemGreen)
//        let text = "Score \(score)%  •  \(message)"
//        let attrs: [NSAttributedString.Key: Any] = [
//            .font: UIFont.systemFont(ofSize: 20, weight: .bold),
//            .foregroundColor: UIColor.white,
//            .backgroundColor: color.withAlphaComponent(0.7)
//        ]
//        (text as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: attrs)
//        UIGraphicsPopContext()
//    }
    
    private func drawOverlay(on pixelBuffer: CVPixelBuffer,
                             landmarks: [NormalizedLandmark],
                             overlayColors: OverlayColors,
                             message: String,
                             score: Int,
                             risk: RiskLevel) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return }

        // 1. Flip to Top-Left for MediaPipe skeleton
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1.0, y: -1.0)
        ctx.setLineWidth(5.0) // Thicker for better video visibility

        let imageSize = CGSize(width: width, height: height)
        let points = landmarks.map { landmark -> CGPoint in
            let x = CGFloat(landmark.x) * imageSize.width
            let y = CGFloat(landmark.y) * imageSize.height
            if mirrorOverlay {
                return CGPoint(x: imageSize.width - x, y: y)
            }
            return CGPoint(x: x, y: y)
        }
        
        let connections: [(Int, Int)] = [
            (11, 13), (13, 15),
            (12, 14), (14, 16),
            (11, 12), (11, 23), (12, 24),
            (23, 24),
            (23, 25), (25, 27),
            (24, 26), (26, 28)
        ]
        
        // Draw the skeleton
        for (a, b) in connections {
            guard a < points.count, b < points.count else { continue }
            ctx.setStrokeColor(colorFor(connection: (a, b), overlayColors: overlayColors).cgColor)
            ctx.move(to: points[a])
            ctx.addLine(to: points[b])
            ctx.strokePath()
        }

        // 2. Create a transparent UIImage containing our Text
        guard score >= 0 && !message.isEmpty else { return }
        UIGraphicsBeginImageContextWithOptions(imageSize, false, 1.0)
        let color: UIColor = (risk == .critical) ? .systemRed : (risk == .medium ? .systemOrange : .systemGreen)
        
        let text = " Score \(score)%  •  \(message) "
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 42, weight: .heavy),
            .foregroundColor: UIColor.white,
            .backgroundColor: color.withAlphaComponent(0.85)
        ]
        
        // Draw text near the top-left of the screen
        (text as NSString).draw(at: CGPoint(x: 40, y: 80), withAttributes: attrs)
        let textOverlayImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        // 3. Revert the CGContext back to Bottom-Left
        ctx.scaleBy(x: 1.0, y: -1.0)
        ctx.translateBy(x: 0, y: -CGFloat(height))
        
        // 4. Stamp the text image onto the video
        // (Drawing a top-left image into a bottom-left context naturally flips it upright!)
        if let cgImage = textOverlayImage?.cgImage {
            ctx.draw(cgImage, in: CGRect(origin: .zero, size: imageSize))
        }
    }
    private func transformedSize(_ size: CGSize, _ transform: CGAffineTransform) -> CGSize {
        let s = size.applying(transform)
        return CGSize(width: abs(s.width), height: abs(s.height))
    }

    private func processOnMain(processor: PoseDetectionManager,
                               landmarks: [NormalizedLandmark],
                               timestampMS: Int) -> (depthProgress: Double,
                                                     repCount: Int,
                                                     lastRepScore: Int,
                                                     feedbackMessage: String,
                                                     risk: RiskLevel,
                                                     overlayColors: OverlayColors,
                                                     allMessages: [(message: String, severity: RuleSeverity)]) {
        if Thread.isMainThread {
            processor.processLandmarks(landmarks, timestampMS: timestampMS)
            sessionSummary = processor.sessionSummary
            return (processor.depthProgress,
                    processor.repCount,
                    processor.lastRepScore,
                    processor.feedbackMessage,
                    processor.currentRisk,
                    processor.overlayColors,
                    processor.lastRepAllMessages)
        }
        
        var result: (Double, Int, Int, String, RiskLevel, OverlayColors, [(message: String, severity: RuleSeverity)]) = (0.0, 0, 0, "", .low, .neutral, [])
        DispatchQueue.main.sync {
            processor.processLandmarks(landmarks, timestampMS: timestampMS)
            sessionSummary = processor.sessionSummary
            result = (processor.depthProgress,
                      processor.repCount,
                      processor.lastRepScore,
                      processor.feedbackMessage,
                      processor.currentRisk,
                      processor.overlayColors,
                      processor.lastRepAllMessages)
        }
        return (result.0, result.1, result.2, result.3, result.4, result.5, result.6)
    }
    
    private func isEngagedForExercise(exercise: String, landmarks: [NormalizedLandmark]) -> Bool {
        guard landmarks.count > 28 else { return false }
        let normalized = exercise.lowercased()
        func vis(_ i: Int) -> Float { landmarks[i].visibility?.floatValue ?? 0 }
        if normalized.contains("squat") {
            // Require at least one full leg chain (hip-knee-ankle) to be visible.
            // This handles side-on video where the far-side limb may be occluded.
            let leftChain  = min(vis(23), vis(25), vis(27))
            let rightChain = min(vis(24), vis(26), vis(28))
            return max(leftChain, rightChain) >= 0.45
        } else if normalized.contains("push") {
            let leftChain  = min(vis(11), vis(13), vis(15))
            let rightChain = min(vis(12), vis(14), vis(16))
            return max(leftChain, rightChain) >= 0.45
        } else if normalized.contains("pull") {
            let leftWrist    = landmarks[15]
            let rightWrist   = landmarks[16]
            let leftShoulder = landmarks[11]
            let rightShoulder = landmarks[12]
            let wristsBelow  = leftWrist.y > leftShoulder.y && rightWrist.y > rightShoulder.y
            let leftChain    = min(vis(11), vis(13), vis(15))
            let rightChain   = min(vis(12), vis(14), vis(16))
            return !wristsBelow && max(leftChain, rightChain) >= 0.40
        }
        return true
    }
    
    private func angle3(_ a: (Double, Double), _ b: (Double, Double), _ c: (Double, Double)) -> Double {
        let abx = a.0 - b.0, aby = a.1 - b.1
        let cbx = c.0 - b.0, cby = c.1 - b.1
        let dot = abx * cbx + aby * cby
        let mag = sqrt(abx * abx + aby * aby) * sqrt(cbx * cbx + cby * cby)
        guard mag > 0 else { return 180 }
        return acos(max(-1.0, min(1.0, dot / mag))) * 180 / .pi
    }

    private func primaryAngle(exercise: String, landmarks: [NormalizedLandmark]) -> Double? {
        guard landmarks.count > 28 else { return nil }
        let ex = exercise.lowercased()
        func pt(_ i: Int) -> (Double, Double) { (Double(landmarks[i].x), Double(landmarks[i].y)) }
        if ex.contains("squat") {
            let left  = angle3(pt(23), pt(25), pt(27))
            let right = angle3(pt(24), pt(26), pt(28))
            return (left + right) / 2.0
        } else {
            let left  = angle3(pt(11), pt(13), pt(15))
            let right = angle3(pt(12), pt(14), pt(16))
            return (left + right) / 2.0
        }
    }

    private func colorFor(connection: (Int, Int), overlayColors: OverlayColors) -> UIColor {
        switch connection {
        case (11, 13), (13, 15):
            return UIColor(overlayColors.leftArm)
        case (12, 14), (14, 16):
            return UIColor(overlayColors.rightArm)
        case (11, 12), (11, 23), (12, 24), (23, 24):
            return UIColor(overlayColors.torso)
        case (23, 25), (25, 27):
            return UIColor(overlayColors.leftLeg)
        case (24, 26), (26, 28):
            return UIColor(overlayColors.rightLeg)
        default:
            return UIColor.white.withAlphaComponent(0.6)
        }
    }
}
