//
//  MainMenuView.swift
//  calisthenicsApp
//
//  Created by Nicholas Zambrano on 29/01/2026.
//



import SwiftUI
import AVFoundation

struct MainMenuView: View {
    @EnvironmentObject private var settings: AppSettings
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
    @State private var selectedFocus: FeedbackFocus = .armsOnly
    @State private var useFrontCamera: Bool = false
    
    var body: some View {
        let palette = Theme.palette(choice: settings.themeChoice, darkMode: settings.darkMode)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Calisthenics Coach")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundColor(palette.textPrimary)
                    Text("Train smarter with live feedback")
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)
                }
                .padding(.horizontal)
                HStack(spacing: 12) {
                    statChip(title: "Target", value: "\(settings.targetReps) reps", palette: palette)
                    statChip(title: "Sensitivity", value: settings.sensitivity.rawValue, palette: palette)
                    statChip(title: "Focus", value: settings.focus.rawValue, palette: palette)
                }
                .padding(.horizontal)

                ForEach(exerciseData, id: \.0) { name, assetName, detail in
                    Button {
                        selectedExercise = name
                        selectedReps = settings.targetReps
                        selectedSensitivity = settings.sensitivity
                        selectedFocus = settings.focus
                        showRepPicker = true
                    } label: {
                        ExerciseCard(name: name, imageName: assetName, detail: detail, palette: palette)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.top)
        }
        .navigationTitle("")
        .background(palette.gradient.ignoresSafeArea())
        .sheet(isPresented: $showRepPicker) {
            repPickerSheet
        }
        .background(
            NavigationLink(
                destination: ExerciseSessionView(
                    selectedExercise: selectedExercise,
                    targetReps: selectedReps,
                    sensitivity: selectedSensitivity,
                    focus: selectedFocus,
                    audioEnabled: settings.audioEnabled,
                    useFrontCamera: useFrontCamera
                ),
                isActive: $navigateToSession
            ) { EmptyView() }
        )
    }
    
    private var repPickerSheet: some View {
        let palette = Theme.palette(choice: settings.themeChoice, darkMode: settings.darkMode)
        return VStack(spacing: 20) {
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
            
            Picker("Focus", selection: $selectedFocus) {
                ForEach(FeedbackFocus.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Picker("Camera", selection: $useFrontCamera) {
                Text("Back").tag(false)
                Text("Front").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            Button {
                showRepPicker = false
                settings.targetReps = selectedReps
                settings.sensitivity = selectedSensitivity
                settings.focus = selectedFocus
                navigateToSession = true
            } label: {
                Text("Start Session")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(palette.accent)
                    .foregroundColor(.black)
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

    private func statChip(title: String, value: String, palette: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(palette.textSecondary)
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundColor(palette.textPrimary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(palette.cardAlt)
        .cornerRadius(10)
    }
}

struct ExerciseCard: View {
    let name: String
    let imageName: String
    let detail: String
    let palette: ThemePalette
    
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
                    .font(.headline.weight(.bold))
                    .foregroundColor(palette.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundColor(palette.textSecondary)
        }
        .padding()
        .background(palette.card)
        .cornerRadius(15)
        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
    }
}
