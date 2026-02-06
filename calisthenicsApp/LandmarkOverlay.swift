//
//  LandmarkOverlay.swift
//  calisthenicsApp
//
//  Created by Nicholas Zambrano on 22/01/2026.
//

import SwiftUI
import MediaPipeTasksVision



struct LandmarkOverlayView: View {
    var landmarks: [NormalizedLandmark]
    
    private let connections = [
        (11, 12), (11, 13), (13, 15), // Right Arm
        (12, 14), (14, 16),           // Left Arm
        (11, 23), (12, 24), (23, 24), // Torso
        (23, 25), (25, 27),           // Right Leg
        (24, 26), (26, 28)            // Left Leg
    ]
    
    var body: some View {
        Canvas { context, size in
            for connection in connections {
                let start = landmarks[connection.0]
                let end = landmarks[connection.1]
                
                var path = Path()
                path.move(to: CGPoint(x: CGFloat(start.x) * size.width, y: CGFloat(start.y) * size.height))
                path.addLine(to: CGPoint(x: CGFloat(end.x) * size.width, y: CGFloat(end.y) * size.height))
                
                context.stroke(path, with: .color(.white.opacity(0.6)), lineWidth: 3)
            }
            
            for landmark in landmarks {
                let x = CGFloat(landmark.x) * size.width
                let y = CGFloat(landmark.y) * size.height
                let rect = CGRect(x: x - 4, y: y - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: rect), with: .color(.green))
            }
        }
        .drawingGroup()
    }
}
