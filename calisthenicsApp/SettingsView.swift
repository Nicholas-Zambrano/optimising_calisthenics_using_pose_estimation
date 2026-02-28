import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    
    var body: some View {
        let palette = Theme.palette(choice: settings.themeChoice, darkMode: settings.darkMode)
        ZStack {
            palette.gradient.ignoresSafeArea()
            
            Form {
                Section(header: Text("Appearance")) {
                    Toggle("Dark Theme", isOn: $settings.darkMode)
                    Picker("Theme", selection: $settings.themeChoice) {
                        ForEach(ThemeChoice.allCases, id: \.self) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                }
                
                Section(header: Text("Coaching")) {
                    Toggle("Audio Feedback", isOn: $settings.audioEnabled)
                }
                
                Section(header: Text("Targets")) {
                    Stepper(value: $settings.targetReps, in: 5...50, step: 1) {
                        Text("Target Reps: \(settings.targetReps)")
                    }
                }
                
                Section(header: Text("Feedback")) {
                    Picker("Sensitivity", selection: $settings.sensitivity) {
                        ForEach(FeedbackSensitivity.allCases, id: \.self) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    Picker("Focus", selection: $settings.focus) {
                        ForEach(FeedbackFocus.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .navigationTitle("Settings")
    }
}
