//
//  ContentView.swift
//  calisthenicsApp
//
//  Created by Nicholas Zambrano on 22/01/2026.
//


import SwiftUI
import AVFoundation

struct ExerciseSessionView: View {
    let selectedExercise: String
    let targetReps: Int
    let sensitivity: FeedbackSensitivity
    let focus: FeedbackFocus
    let audioEnabled: Bool
    let useFrontCamera: Bool
    let squatViewMode: SquatViewMode
    var participantID: String = ""
    var studyCondition: String = "feedback"
    var studyConditionOrder: Int = 1
    var baselineMode: Bool = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyStore: WorkoutHistoryStore
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var poseManager = PoseDetectionManager()
    @State private var countdown = 10
    @State private var isCountingDown = true
    @State private var showShareSheet = false
    @State private var exportURL: URL?

    var body: some View {

        
        let palette = Theme.palette(choice: settings.themeChoice, darkMode: settings.darkMode)
        GeometryReader { geo in
            ZStack {

                CameraView(session: poseManager.session, isMirrored: poseManager.isFrontCamera).ignoresSafeArea()
            
            if !isCountingDown, !poseManager.isSessionComplete, let currentLandmarks = poseManager.latestLandmarks {
                LandmarkOverlayView(

                    landmarks: currentLandmarks,
                    overlayColors: baselineMode ? .neutral : poseManager.overlayColors,
                    mirrorX: poseManager.isFrontCamera
                ).ignoresSafeArea()

                if !baselineMode {

                    InstructionOverlayView
                    (
                        landmarks:  currentLandmarks,
                        primary: poseManager.feedbackMessage,
                        secondary: poseManager.secondaryHint,
                        mirrorX: poseManager.isFrontCamera
                    )

                    .ignoresSafeArea()
                }
            }
            
            VStack {

                HStack {
                    Button(action: 
                    { poseManager.toggleCamera() }) {
                        Image(systemName: "camera.rotate.fill")
                            .font(.system(size: 22, weight: .bold))
                            .padding()
                            .background(palette.cardAlt.opacity(0.9))
                            .foregroundColor(palette.textPrimary)
                            .clipShape(Circle())
                    }

                    .disabled(!isCountingDown)

                    .opacity(isCountingDown ? 1.0 : 0.4)
                    Text(poseManager.isFrontCamera ? "Front Camera" : "Back Camera")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(palette.cardAlt.opacity(0.9))
                        .foregroundColor(palette.textPrimary)
                        .clipShape(Capsule())
                    Spacer()
                    Button(action: {
                        poseManager.stopSession()
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 22, weight: .bold))
                            .padding()
                            .background(palette.cardAlt.opacity(0.9))
                            .foregroundColor(palette.textPrimary)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 25)
                .padding(.top, 50)
                
                if !isCountingDown {
                    HStack(spacing: 16) {
                        statCard(title: "REPS", value: "\(poseManager.repCount)", palette: palette)
                        if !baselineMode {
                            VStack {
                                Text("\(poseManager.overallScore)%")
                                    .font(.system(size: 30, weight: .black))
                                    .foregroundColor(scoreColor)
                                Text("QUALITY").font(.caption).bold().foregroundColor(palette.textPrimary)
                                Text("Last: \(poseManager.lastRepScore)%")
                                    .font(.caption2)
                                    .foregroundColor(palette.textSecondary)
                            }
                            .frame(width: 120, height: 90)
                            .background(palette.card.opacity(0.9))
                            .cornerRadius(16)
                        }
                    }
                    .padding(.top, 20)



                    if !baselineMode {
                        VStack(spacing: 6) {
                            Text("DEPTH")
                                .font(.caption).bold()
                                .foregroundColor(palette.textPrimary)
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
                }

                Spacer()
                
                if !isCountingDown && !baselineMode {
                    VStack(spacing: 6) {
                        Text(poseManager.feedbackMessage)
                            .font(.headline)
                        if !poseManager.secondaryHint.isEmpty {
                            Text(poseManager.secondaryHint)
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    }
                    .padding()
                    .background(feedbackColor.opacity(0.9))
                    .foregroundColor(palette.textPrimary)
                    .cornerRadius(12)
                    .padding(.bottom, 40)
                }
            }
            
            if settings.debugEnabled && !isCountingDown && !poseManager.isSessionComplete && !poseManager.debugText.isEmpty {
                VStack {
                    HStack {
                        Text(poseManager.debugText)
                            .font(.caption2)
                            .foregroundColor(palette.textSecondary)
                            .padding(6)
                        .background(palette.cardAlt.opacity(0.9))
                        .cornerRadius(8)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.top, 100)
                .padding(.horizontal, 16)
            }

            if settings.debugEnabled && selectedExercise == "Squat" && !poseManager.repMetrics.isEmpty && !isCountingDown {
                VStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Rep Timeline")
                            .font(.caption.bold())
                            .foregroundColor(palette.textPrimary)
                        ForEach(poseManager.repMetrics) { rep in
                            HStack(spacing: 8) {
                                Text("#\(rep.repIndex)")
                                    .font(.caption2.bold())
                                    .frame(width: 28, alignment: .leading)
                                Text("\(rep.score)%")
                                    .font(.caption2)
                                    .frame(width: 40, alignment: .leading)
                                if let valgus = rep.kneeValgus {
                                    Text(String(format: "valgus %.2f", valgus))
                                        .font(.caption2)
                                }
                                if let lean = rep.forwardLean {
                                    Text(String(format: "lean %.2f", lean))
                                        .font(.caption2)
                                }
                                Spacer()
                                Text(rep.primaryMessage)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .foregroundColor(palette.textSecondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(palette.cardAlt.opacity(0.9))
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }

            if poseManager.isSessionComplete, let summary = poseManager.sessionSummary {
                Color.black.opacity(0.6).ignoresSafeArea()
                VStack(spacing: 16) {

                    Text("Session Summary")
                        .font(.title2).bold()
                        .foregroundColor(palette.textPrimary)
                    
                    VStack(spacing: 10) {
                        summaryRow(label: "Total Reps", value: "\(summary.totalReps)", palette: palette)
                        summaryRow(label: "Avg Quality", value: "\(summary.averageScore)%", palette: palette)
                        summaryRow(label: "Clean Reps", value: "\(summary.cleanReps)", palette: palette)
                        summaryRow(label: "Best Rep", value: "\(summary.bestRep)%", palette: palette)
                        summaryRow(label: "Worst Rep", value: "\(summary.worstRep)%", palette: palette)
                        if let issue = summary.mostCommonIssueMessage {
                            summaryRow(label: "Most Common", value: issue, palette: palette)
                        }
                    }
                    .padding()
                    .background(palette.card.opacity(0.95))
                    .cornerRadius(16)
                    
                    if settings.userStudyMode {
                        Button {
                            if let url = StudyLogger.shared.exportURL(participantID: participantID, condition: studyCondition) {
                                exportURL = url
                                showShareSheet = true
                            }
                        } label: {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.green)
                                .foregroundColor(.black)
                                .cornerRadius(12)
                        }
                    }

                    NavigationLink(destination: MainMenuView()) {
                        Text("Back to Home")
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(palette.accent)
                            .foregroundColor(.black)
                            .cornerRadius(12)
                    }
                }
                .padding()
                .sheet(isPresented: $showShareSheet) {
                    if let url = exportURL {
                        ShareSheet(items: [url])
                    }
                }
                .onAppear {
                    historyStore.addSession(
                        exercise: selectedExercise,
                        summary: summary,
                        source: "Live"
                    )
                }
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

            poseManager.cameraPosition = useFrontCamera ? .front : .back
            poseManager.isFrontCamera = useFrontCamera
            poseManager.isPortraitMode = geo.size.height >= geo.size.width
            poseManager.isCoachingActive = audioEnabled
            poseManager.debugEnabled = settings.debugEnabled
            if selectedExercise == "Squat" {
                poseManager.squatViewMode = squatViewMode
            }
             else {
                poseManager.squatViewMode = .auto
            }
            startSequence()
        }
            .onChange(of: geo.size) { newSize in
                poseManager.isPortraitMode = newSize.height >= newSize.width

            }
            .onChange(of: settings.debugEnabled) { value in
                poseManager.debugEnabled = value
            }
        }
        .onDisappear {
            poseManager.stopSession()
        }
    }

    private var scoreColor: Color {
        if poseManager.overallScore > 80 { return .green }
        if poseManager.overallScore > 50 { return .orange }
        return .red
    }
    
    private var feedbackColor: Color {

        if poseManager.feedbackMessage.hasPrefix("CRITICAL") {
             return .red }
        if poseManager.feedbackMessage.hasPrefix("IMPORTANT") { 
            return .orange }
        if poseManager.feedbackMessage.hasPrefix("MINOR") { 
            return .blue }
        if poseManager.feedbackMessage.hasPrefix("GOOD") { 
            return .green }
        return .black.opacity(0.7)
    }
    
    private var depthColor: Color
    {
        if poseManager.depthProgress > 0.9 { 
            return .green
             }
        if poseManager.depthProgress > 0.7 { return .yellow }
        return .red
    }

    private func statCard(title: String, value: String, palette: ThemePalette) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 40, weight: .black))
                .foregroundColor(palette.textPrimary)
            Text(title)
                .font(.caption).bold()
                .foregroundColor(palette.textSecondary)
        }
        .frame(width: 100, height: 90)
        .background(palette.cardAlt.opacity(0.9))
        .cornerRadius(16)
    }

    private func summaryRow(label: String, value: String, palette: ThemePalette) -> some View {
        HStack {
            Text(label).foregroundColor(palette.textSecondary)
            Spacer()
            Text(value).foregroundColor(palette.textPrimary).bold()
        }
        .font(.subheadline)
    }

    func startSequence() {

        
        poseManager.activeExercise = selectedExercise
        poseManager.isCoachingActive = false
        poseManager.resetForNewSession(targetReps: targetReps, sensitivity: sensitivity)
        poseManager.feedbackFocus = focus
        poseManager.isDetectionPaused = true
        poseManager.studyParticipantID = participantID
        poseManager.studyCondition = studyCondition
        poseManager.studyConditionOrder = studyConditionOrder
        poseManager.isStudyModeActive = settings.userStudyMode
        if settings.userStudyMode { StudyLogger.shared.clear() }
        poseManager.checkPermissionAndStart()

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            DispatchQueue.main.async {
                if countdown > 1 {
                    countdown -= 1
                } else {
                    timer.invalidate()
                    isCountingDown = false
                    poseManager.isDetectionPaused = false
                    if !self.baselineMode {
                        poseManager.isCoachingActive = audioEnabled
                        poseManager.speakFeedback("Starting \(selectedExercise) analysis")
                    }
                }
            }
        }
    }
}
