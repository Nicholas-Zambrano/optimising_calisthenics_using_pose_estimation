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
        let score: Int
        let primaryMessage: String
        let risk: RiskLevel
        let snapshot: UIImage?
        
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
            case .low: return "Minor"
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
    private var loggedFirstSnapshot = false
    
    func cancel() {
        isCancelled = true
    }
    
    func analyzeVideo(url: URL, exercise: String, settings: AppSettings) {
        isCancelled = false
        progress = 0
        sessionSummary = nil
        bestSnapshot = nil
        worstSnapshot = nil
        bestScore = -1
        worstScore = 101
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
            let frameIntervalMS = 150
            var lastRepCount = 0
            var currentRepMaxDepth: Double = 0.0
            var currentRepSnapshot: UIImage?
            var lastLogMS: Int = 0
            
            DispatchQueue.main.async {
                self.status = "Analyzing..."
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
                            currentRepSnapshot = self.renderAnnotatedFrame(
                                pixelBuffer: pixelBuffer,
                                landmarks: landmarks,
                                overlayColors: processed.overlayColors
                            )
                        }

                        if processed.repCount > lastRepCount {
                            lastRepCount = processed.repCount
                            let frame = currentRepSnapshot ?? self.renderAnnotatedFrame(
                                pixelBuffer: pixelBuffer,
                                landmarks: landmarks,
                                overlayColors: processed.overlayColors
                            )
                            let summary = RepSummary(
                                repIndex: processed.repCount,
                                timestampMS: tsMS,
                                score: processed.lastRepScore,
                                primaryMessage: processed.feedbackMessage,
                                risk: processed.risk,
                                snapshot: frame
                            )
                            DispatchQueue.main.async {
                                self.repSummaries.append(summary)
                            }
                            if let frame = frame {
                                let score = processed.lastRepScore
                                DispatchQueue.main.async {
                                    if score >= self.bestScore {
                                        self.bestScore = score
                                        self.bestSnapshot = frame
                                    }
                                    if score <= self.worstScore {
                                        self.worstScore = score
                                        self.worstSnapshot = frame
                                    }
                                }
                            }
                            currentRepMaxDepth = 0.0
                            currentRepSnapshot = nil
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
                                message: "Resting",
                                score: 0,
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
                                                     overlayColors: OverlayColors) {
        if Thread.isMainThread {
            processor.processLandmarks(landmarks, timestampMS: timestampMS)
            sessionSummary = processor.sessionSummary
            return (processor.depthProgress,
                    processor.repCount,
                    processor.lastRepScore,
                    processor.feedbackMessage,
                    processor.currentRisk,
                    processor.overlayColors)
        }
        
        var result: (Double, Int, Int, String, RiskLevel, OverlayColors) = (0.0, 0, 0, "", .low, .neutral)
        DispatchQueue.main.sync {
            processor.processLandmarks(landmarks, timestampMS: timestampMS)
            sessionSummary = processor.sessionSummary
            result = (processor.depthProgress,
                      processor.repCount,
                      processor.lastRepScore,
                      processor.feedbackMessage,
                      processor.currentRisk,
                      processor.overlayColors)
        }
        return (result.0, result.1, result.2, result.3, result.4, result.5)
    }
    
    private func isEngagedForExercise(exercise: String, landmarks: [NormalizedLandmark]) -> Bool {
        let normalized = exercise.lowercased()
        if normalized.contains("pull") {
            let leftWrist = landmarks[15]
            let rightWrist = landmarks[16]
            let leftShoulder = landmarks[11]
            let rightShoulder = landmarks[12]
            let wristsBelow = leftWrist.y > leftShoulder.y && rightWrist.y > rightShoulder.y
            return !wristsBelow
        }
        return true
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
