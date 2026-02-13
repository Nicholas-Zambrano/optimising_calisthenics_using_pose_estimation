//
//  MainMenuView.swift
//  calisthenicsApp
//
//  Created by Nicholas Zambrano on 29/01/2026.
//



import SwiftUI

struct MainMenuView: View {
    let exerciseData = [
        ("Push-Up", "push_up", "Target: Core & Chest"),
        ("Squat", "squat", "Target: Quads & Glutes"),
        ("Pull-Up", "pull_up", "Target: Back & Biceps")
    ]
    
    @State private var showRepPicker = false
    @State private var navigateToSession = false
    @State private var selectedExercise: String = ""
    @State private var selectedReps: Int = 10
    @State private var selectedSensitivity: FeedbackSensitivity = .normal
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Time to master your calisthenics")
                        .font(.largeTitle)
                        .bold()
                        .foregroundColor(.white) // Dark theme look for elite athletes
                    Text("Select your exercise")
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                ForEach(exerciseData, id: \.0) { name, assetName, detail in
                    Button {
                        selectedExercise = name
                        selectedReps = 10
                        selectedSensitivity = .normal
                        showRepPicker = true
                    } label: {
                        ExerciseCard(name: name, imageName: assetName, detail: detail)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.top)
        }
        .navigationTitle("")
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showRepPicker) {
            repPickerSheet
        }
        .background(
            NavigationLink(
                destination: ExerciseSessionView(
                    selectedExercise: selectedExercise,
                    targetReps: selectedReps,
                    sensitivity: selectedSensitivity
                ),
                isActive: $navigateToSession
            ) { EmptyView() }
        )
    }
    
    private var repPickerSheet: some View {
        VStack(spacing: 20) {
            Text("Set Your Target")
                .font(.title2).bold()
            
            Text(selectedExercise)
                .font(.headline)
                .foregroundColor(.secondary)
            
            Stepper(value: $selectedReps, in: 5...50, step: 1) {
                Text("\(selectedReps) reps")
                    .font(.title)
                    .bold()
            }
            .padding(.horizontal)
            
            Picker("Sensitivity", selection: $selectedSensitivity) {
                ForEach(FeedbackSensitivity.allCases, id: \.self) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            Button {
                showRepPicker = false
                navigateToSession = true
            } label: {
                Text("Start Session")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.black)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            
            Button {
                showRepPicker = false
            } label: {
                Text("Cancel")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .presentationDetents([.medium])
    }
}

struct ExerciseCard: View {
    let name: String
    let imageName: String
    let detail: String
    
    var body: some View {
        HStack(spacing: 15) {
            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 80, height: 80)
                .cornerRadius(12)
                .clipped()
            
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding()
        .background(Color(white: 0.12)) 
        .cornerRadius(15)
        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
    }
}
