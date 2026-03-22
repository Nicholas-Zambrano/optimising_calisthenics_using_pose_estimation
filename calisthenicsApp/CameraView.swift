 //
//  CameraView.swift
//  calisthenicsApp
//
//  Created by Nicholas Zambrano on 22/01/2026.
//

import SwiftUI
import AVFoundation

struct CameraView: UIViewRepresentable {
    let session: AVCaptureSession
    let isMirrored: Bool

    class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    class Coordinator: NSObject {
        var isMirrored: Bool
        var observation: NSKeyValueObservation?
        weak var previewView: PreviewView?

        init(isMirrored: Bool) { self.isMirrored = isMirrored }

        func configureConnection() {
            guard let connection = previewView?.previewLayer.connection else { return }
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            } else if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = isMirrored
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(isMirrored: isMirrored) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill

        let coordinator = context.coordinator
        coordinator.previewView = view
        coordinator.configureConnection()

        coordinator.observation = session.observe(\.isRunning, options: [.new]) { [weak coordinator] _, change in
            if change.newValue == true {
                DispatchQueue.main.async { coordinator?.configureConnection() }
            }
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.isMirrored = isMirrored
        context.coordinator.configureConnection()
    }
}
