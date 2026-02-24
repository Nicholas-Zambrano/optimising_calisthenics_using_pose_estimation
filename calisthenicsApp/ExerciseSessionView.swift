//
//  ContentView.swift
//  calisthenicsApp
//
//  Created by Nicholas Zambrano on 22/01/2026.
//


import SwiftUI

struct ExerciseSessionView: View {
    let selectedExercise: String
    let targetReps: Int
    let sensitivity: FeedbackSensitivity
    let focus: FeedbackFocus
    @StateObject private var poseManager = PoseDetectionManager()
    @State private var countdown = 10
    @State private var isCountingDown = true

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CameraView(session: poseManager.session).ignoresSafeArea()
            
            if !isCountingDown, !poseManager.isSessionComplete, let currentLandmarks = poseManager.latestLandmarks {
                LandmarkOverlayView(
                    landmarks: currentLandmarks,
                    overlayColors: poseManager.overlayColors
                ).ignoresSafeArea()
                
                InstructionOverlayView(
                    landmarks: currentLandmarks,
                    primary: poseManager.feedbackMessage,
                    secondary: poseManager.secondaryHint
                )
                .ignoresSafeArea()
            }
            
            VStack {
                HStack {
                    Button(action: { poseManager.toggleCamera() }) {
                        Image(systemName: "camera.rotate.fill")
                            .font(.system(size: 22, weight: .bold))
                            .padding()
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                    Spacer()
                    NavigationLink(destination: MainMenuView()) {
                        Image(systemName: "xmark")
                            .font(.system(size: 22, weight: .bold))
                            .padding()
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 25)
                .padding(.top, 50)
                
                if !isCountingDown {
                    HStack(spacing: 20) {
                        VStack {
                            Text("\(poseManager.repCount)")
                                .font(.system(size: 40, weight: .black))
                            Text("REPS").font(.caption).bold()
                        }
                        .frame(width: 80, height: 80)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(15)
                        
                        VStack {
                            Text("\(poseManager.overallScore)%")
                                .font(.system(size: 30, weight: .black))
                                .foregroundColor(scoreColor)
                            Text("QUALITY").font(.caption).bold().foregroundColor(.white)
                            Text("Last: \(poseManager.lastRepScore)%")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .frame(width: 100, height: 80)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(15)
                    }
                    .padding(.top, 20)
                    
                    VStack(spacing: 6) {
                        Text("DEPTH")
                            .font(.caption).bold()
                            .foregroundColor(.white)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.2))
                                Capsule()
                                    .fill(depthColor)
                                    .frame(width: max(8, geo.size.width * poseManager.depthProgress))
                            }
                        }
                        .frame(height: 10)
                        .frame(width: 180)
                    }
                    .padding(.top, 8)
                }

                Spacer()
                
                if !isCountingDown {
                    VStack(spacing: 6) {
                        Text(poseManager.feedbackMessage)
                            .font(.headline)
                        if !poseManager.secondaryHint.isEmpty {
                            Text(poseManager.secondaryHint)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding()
                    .background(feedbackColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .padding(.bottom, 40)
                }
            }
            
            if !isCountingDown && !poseManager.isSessionComplete && !poseManager.debugText.isEmpty {
                VStack {
                    HStack {
                        Text(poseManager.debugText)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                            .padding(6)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(8)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.top, 100)
                .padding(.horizontal, 16)
            }

            if poseManager.isSessionComplete, let summary = poseManager.sessionSummary {
                Color.black.opacity(0.6).ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("Session Summary")
                        .font(.title2).bold()
                        .foregroundColor(.white)
                    
                    VStack(spacing: 10) {
                        summaryRow(label: "Total Reps", value: "\(summary.totalReps)")
                        summaryRow(label: "Avg Quality", value: "\(summary.averageScore)%")
                        summaryRow(label: "Clean Reps", value: "\(summary.cleanReps)")
                        summaryRow(label: "Best Rep", value: "\(summary.bestRep)%")
                        summaryRow(label: "Worst Rep", value: "\(summary.worstRep)%")
                        if let issue = summary.mostCommonIssue {
                            summaryRow(label: "Most Common", value: issue.message)
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(16)
                    
                    NavigationLink(destination: MainMenuView()) {
                        Text("Back to Home")
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(12)
                    }
                }
                .padding()
            }
            
            if isCountingDown {
                Color.black.opacity(0.5).ignoresSafeArea()
                VStack(spacing: 20) {
                    Text("Get into Position").font(.title2).bold().foregroundColor(.white)
                    Text("\(countdown)").font(.system(size: 120, weight: .black)).foregroundColor(.white)
                }
            }
            }
            .navigationBarBackButtonHidden(true)
            .onAppear {
                poseManager.isPortraitMode = geo.size.height >= geo.size.width
                startSequence()
            }
            .onChange(of: geo.size) { newSize in
                poseManager.isPortraitMode = newSize.height >= newSize.width
            }
        }
    }

    private var scoreColor: Color {
        if poseManager.overallScore > 80 { return .green }
        if poseManager.overallScore > 50 { return .orange }
        return .red
    }
    
    private var feedbackColor: Color {
        if poseManager.feedbackMessage.hasPrefix("CRITICAL") { return .red }
        if poseManager.feedbackMessage.hasPrefix("IMPORTANT") { return .orange }
        if poseManager.feedbackMessage.hasPrefix("MINOR") { return .blue }
        if poseManager.feedbackMessage.hasPrefix("GOOD") { return .green }
        return .black.opacity(0.7)
    }
    
    private var depthColor: Color {
        if poseManager.depthProgress > 0.9 { return .green }
        if poseManager.depthProgress > 0.7 { return .yellow }
        return .red
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.white.opacity(0.8))
            Spacer()
            Text(value).foregroundColor(.white).bold()
        }
        .font(.subheadline)
    }

    func startSequence() {
        poseManager.activeExercise = selectedExercise
        poseManager.isCoachingActive = false
        poseManager.resetForNewSession(targetReps: targetReps, sensitivity: sensitivity)
        poseManager.feedbackFocus = focus
        poseManager.checkPermissionAndStart()
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            DispatchQueue.main.async {
                if countdown > 1 {
                    countdown -= 1
                } else {
                    timer.invalidate()
                    isCountingDown = false
                    poseManager.isCoachingActive = true
                    poseManager.speakFeedback("Starting \(selectedExercise) analysis")
                }
            }
        }
    }
}
