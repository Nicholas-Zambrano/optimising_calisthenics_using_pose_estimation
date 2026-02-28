import Foundation
import AVFoundation
import MediaPipeTasksVision
import UIKit
import Combine

final class OfflineAnalysisManager: ObservableObject {
    @Published var progress: Double = 0
    @Published var status: String = "Idle"
    @Published var isRunning: Bool = false
    @Published var isExporting: Bool = false
    @Published var sessionSummary: SessionSummary?
    @Published var bestSnapshot: UIImage?
    @Published var worstSnapshot: UIImage?
    @Published var logLines: [String] = []
    @Published var mirrorOverlay: Bool = true
    
    private var isCancelled = false
    private var bestScore: Int = -1
    private var worstScore: Int = 101
    
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
            let isPortrait = naturalSize.height >= naturalSize.width
            
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
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
            output.alwaysCopiesSampleData = false
            if reader.canAdd(output) {
                reader.add(output)
            }
            
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
            
            var lastProcessedMS: Int = 0
            let frameIntervalMS = 100
            var lastRepCount = 0
            
            DispatchQueue.main.async {
                self.status = "Analyzing..."
                self.logLines.append("Analysis started")
            }
            
            while reader.status == .reading, !self.isCancelled {
                guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
                let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                let tsMS = Int(CMTimeGetSeconds(ts) * 1000)
                if tsMS - lastProcessedMS < frameIntervalMS { continue }
                lastProcessedMS = tsMS
                
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
                guard let image = try? MPImage(pixelBuffer: pixelBuffer, orientation: .up) else { continue }
                if let result = try? poseLandmarker.detect(videoFrame: image, timestampInMilliseconds: tsMS),
                   let landmarks = result.landmarks.first {
                    DispatchQueue.main.async {
                        processor.processLandmarks(landmarks, timestampMS: tsMS)
                        self.sessionSummary = processor.sessionSummary
                    }
                    
                    if processor.repCount > lastRepCount {
                        lastRepCount = processor.repCount
                        if let frame = self.renderAnnotatedFrame(pixelBuffer: pixelBuffer, landmarks: landmarks) {
                            let score = processor.lastRepScore
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
                    }
                }
                
                let currentSec = CMTimeGetSeconds(ts)
                let p = durationSec > 0 ? min(1.0, currentSec / durationSec) : 0
                DispatchQueue.main.async {
                    self.progress = p
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
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
            output.alwaysCopiesSampleData = false
            if reader.canAdd(output) { reader.add(output) }
            
            let naturalSize = track.naturalSize
            let width = Int(naturalSize.width)
            let height = Int(naturalSize.height)
            
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
            processor.isPortraitMode = naturalSize.height >= naturalSize.width
            processor.sensitivity = settings.sensitivity
            processor.feedbackFocus = settings.focus
            processor.isCoachingActive = false
            processor.resetForNewSession(targetReps: settings.targetReps, sensitivity: settings.sensitivity)
            
            if !reader.startReading() {
                DispatchQueue.main.async {
                    self.status = "Failed to start reader"
                    self.isExporting = false
                    completion(nil)
                }
                return
            }
            
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)
            
            let frameIntervalMS = 100
            var lastProcessedMS = 0
            
            while reader.status == .reading && writerInput.isReadyForMoreMediaData && !self.isCancelled {
                guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
                let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                let tsMS = Int(CMTimeGetSeconds(ts) * 1000)
                if tsMS - lastProcessedMS < frameIntervalMS { continue }
                lastProcessedMS = tsMS
                
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
                guard let image = try? MPImage(pixelBuffer: pixelBuffer, orientation: .up) else { continue }
                guard let result = try? poseLandmarker.detect(videoFrame: image, timestampInMilliseconds: tsMS),
                      let landmarks = result.landmarks.first else { continue }
                
                processor.processLandmarks(landmarks, timestampMS: tsMS)
                if let annotated = self.renderAnnotatedFrame(pixelBuffer: pixelBuffer, landmarks: landmarks),
                   let outBuffer = self.makePixelBuffer(from: annotated, pool: adaptor.pixelBufferPool) {
                    adaptor.append(outBuffer, withPresentationTime: ts)
                }
            }
            
            writerInput.markAsFinished()
            writer.finishWriting {
                DispatchQueue.main.async {
                    self.isExporting = false
                    self.status = "Export complete"
                    self.logLines.append("Export complete")
                    completion(tempURL)
                }
            }
        }
    }
    
    private func renderAnnotatedFrame(pixelBuffer: CVPixelBuffer, landmarks: [NormalizedLandmark]) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        
        UIGraphicsBeginImageContextWithOptions(imageSize, true, 1.0)
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: imageSize))
        ctx.setStrokeColor(UIColor.systemGreen.cgColor)
        ctx.setLineWidth(3.0)
        
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
        for (a, b) in connections {
            guard a < points.count, b < points.count else { continue }
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
        
        CVPixelBufferLockBaseAddress(buffer, [])
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(image.size.width),
            height: Int(image.size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )
        if let cgImage = image.cgImage {
            context?.draw(cgImage, in: CGRect(origin: .zero, size: image.size))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
}
