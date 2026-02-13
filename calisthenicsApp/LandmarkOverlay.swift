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
    var overlayColors: OverlayColors
    
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
                
                let color = colorForConnection(connection)
                context.stroke(path, with: .color(color), lineWidth: 3)
            }
            
            for landmark in landmarks {
                let x = CGFloat(landmark.x) * size.width
                let y = CGFloat(landmark.y) * size.height
                let rect = CGRect(x: x - 4, y: y - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: rect), with: .color(.white))
            }
        }
        .drawingGroup()
    }
    
    private func colorForConnection(_ connection: (Int, Int)) -> Color {
        switch connection {
        case (11, 13), (13, 15):
            return overlayColors.leftArm
        case (12, 14), (14, 16):
            return overlayColors.rightArm
        case (11, 12), (11, 23), (12, 24), (23, 24):
            return overlayColors.torso
        case (23, 25), (25, 27):
            return overlayColors.leftLeg
        case (24, 26), (26, 28):
            return overlayColors.rightLeg
        default:
            return .white.opacity(0.6)
        }
    }
}

struct InstructionOverlayView: View {
    let landmarks: [NormalizedLandmark]
    let primary: String
    let secondary: String

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                let shoulderL = point(landmarks[11], size)
                let shoulderR = point(landmarks[12], size)
                let wristL = point(landmarks[15], size)
                let wristR = point(landmarks[16], size)
                let hipL = point(landmarks[23], size)
                let hipR = point(landmarks[24], size)
                
                let shoulderMid = mid(shoulderL, shoulderR)
                let hipMid = mid(hipL, hipR)
                
                if primary.contains("Tuck elbows") || secondary.contains("Tuck elbows") {
                    drawArrow(context: &context, from: wristL, to: CGPoint(x: wristL.x + 30, y: wristL.y), color: .yellow)
                    drawArrow(context: &context, from: wristR, to: CGPoint(x: wristR.x - 30, y: wristR.y), color: .yellow)
                }
                
                if primary.contains("Keep hips") || secondary.contains("Keep hips") || primary.contains("Lift hips") || secondary.contains("Lift hips") {
                    drawArrow(context: &context, from: hipMid, to: CGPoint(x: hipMid.x, y: hipMid.y - 40), color: .red)
                }
                
                if primary.contains("Go deeper") || secondary.contains("Go deeper") {
                    drawArrow(context: &context, from: shoulderMid, to: CGPoint(x: shoulderMid.x, y: shoulderMid.y + 50), color: .orange)
                }
            }
        }
    }

    private func point(_ lm: NormalizedLandmark, _ size: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(lm.x) * size.width, y: CGFloat(lm.y) * size.height)
    }

    private func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    private func drawArrow(context: inout GraphicsContext, from: CGPoint, to: CGPoint, color: Color) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(path, with: .color(color), lineWidth: 3)
        
        let angle = atan2(to.y - from.y, to.x - from.x)
        let headLength: CGFloat = 10
        let left = CGPoint(
            x: to.x - headLength * cos(angle - .pi / 6),
            y: to.y - headLength * sin(angle - .pi / 6)
        )
        let right = CGPoint(
            x: to.x - headLength * cos(angle + .pi / 6),
            y: to.y - headLength * sin(angle + .pi / 6)
        )
        var head = Path()
        head.move(to: to)
        head.addLine(to: left)
        head.move(to: to)
        head.addLine(to: right)
        context.stroke(head, with: .color(color), lineWidth: 3)
    }
}
