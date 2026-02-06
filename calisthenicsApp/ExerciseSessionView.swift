//
//  ContentView.swift
//  calisthenicsApp
//
//  Created by Nicholas Zambrano on 22/01/2026.
//


import SwiftUI

struct ExerciseSessionView: View {
    let selectedExercise: String
    @StateObject private var poseManager = PoseDetectionManager()
    @State private var countdown = 10
    @State private var isCountingDown = true

    var body: some View {
        ZStack {
            CameraView(session: poseManager.session).ignoresSafeArea()
            
            if !isCountingDown, let currentLandmarks = poseManager.latestLandmarks {
                LandmarkOverlayView(landmarks: currentLandmarks).ignoresSafeArea()
            }
            
            VStack {
                HStack {
                    Button(action: {
                        poseManager.toggleCamera()
                    }) {
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
                
                Spacer()
                
                if !isCountingDown {
                    Text(poseManager.feedbackMessage)
                        .font(.headline)
                        .padding()
                        .background(poseManager.currentRisk == .critical ? Color.red : Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding(.bottom, 40)
                }
            }
            
            if isCountingDown {
                Color.black.opacity(0.5).ignoresSafeArea()
                VStack(spacing: 20) {
                    Text("Get into Position")
                        .font(.title2).bold().foregroundColor(.white)
                    Text("\(countdown)")
                        .font(.system(size: 120, weight: .black))
                        .foregroundColor(.white)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            startSequence()
        }
    }

    func startSequence() {
        poseManager.activeExercise = selectedExercise
        poseManager.isCoachingActive = false
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
