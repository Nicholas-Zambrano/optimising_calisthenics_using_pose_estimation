import SwiftUI

struct AnalyzeView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showOffline = false
    @State private var showExercisePicker = false
    @State private var selectedExercise: String = "Push-Up"
    
    var body: some View {
        let palette = Theme.palette(choice: settings.themeChoice, darkMode: settings.darkMode)
        ZStack {
            palette.gradient.ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Analyze Sessions")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(palette.textPrimary)
                
                Text("Choose live coaching or offline analysis")
                    .foregroundColor(palette.textSecondary)
                
                Button {
                    showExercisePicker = true
                } label: {
                    analyzeCard(
                        title: "Live Coaching",
                        subtitle: "Real-time guidance & reps",
                        icon: "camera.viewfinder",
                        palette: palette
                    )
                }
                .buttonStyle(.plain)
                
                Button {
                    showOffline = true
                } label: {
                    analyzeCard(
                        title: "Offline Analysis",
                        subtitle: "Upload video & get summary",
                        icon: "film",
                        palette: palette
                    )
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            .padding()
        }
        .sheet(isPresented: $showOffline) {
            OfflineAnalysisView()
        }
        .sheet(isPresented: $showExercisePicker) {
            exercisePickerSheet
        }
    }
    
    private var exercisePickerSheet: some View {
        VStack(spacing: 16) {
            Text("Start Live Session")
                .font(.title2).bold()
            
            Picker("Exercise", selection: $selectedExercise) {
                Text("Push-Up").tag("Push-Up")
                Text("Squat").tag("Squat")
                Text("Pull-Up").tag("Pull-Up")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            NavigationLink(destination: ExerciseSessionView(
                selectedExercise: selectedExercise,
                targetReps: settings.targetReps,
                sensitivity: settings.sensitivity,
                focus: settings.focus,
                audioEnabled: settings.audioEnabled
            )) {
                Text("Start")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.black)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            
            Button("Cancel") { showExercisePicker = false }
                .foregroundColor(.secondary)
        }
        .padding()
        .presentationDetents([.medium])
    }
    
    private func analyzeCard(title: String, subtitle: String, icon: String, palette: ThemePalette) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 48, height: 48)
                .background(palette.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(palette.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }
            
            Spacer()
        }
        .padding()
        .background(palette.card)
        .cornerRadius(16)
    }
}
