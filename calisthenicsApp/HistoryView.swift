import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var historyStore: WorkoutHistoryStore
    @EnvironmentObject private var settings: AppSettings
    
    var body: some View {
        let palette = Theme.palette(choice: settings.themeChoice, darkMode: settings.darkMode)
        ZStack {
            palette.gradient.ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Workout History")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundColor(palette.textPrimary)
                
                if historyStore.sessions.isEmpty {
                    Text("History will appear here after you complete sessions.")
                        .foregroundColor(palette.textSecondary)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(historyStore.sessions) { session in
                                historyCard(session, palette: palette)
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
        }
    }
    
    private func historyCard(_ session: SessionRecord, palette: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.exercise)
                    .font(.headline)
                    .foregroundColor(palette.textPrimary)
                Spacer()
                Text(session.source)
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }
            
            Text(session.date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundColor(palette.textSecondary)
            
            HStack {
                metric("Reps", "\(session.totalReps)")
                metric("Avg", "\(session.averageScore)%")
                metric("Clean", "\(session.cleanReps)")
            }
            
            if let issue = session.mostCommonIssue {
                Text("Most common: \(issue)")
                    .font(.caption2)
                    .foregroundColor(palette.textSecondary)
            }
        }
        .padding()
        .background(palette.card)
        .cornerRadius(16)
    }
    
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(Theme.palette(choice: settings.themeChoice, darkMode: settings.darkMode).textSecondary)
            Text(value)
                .font(.headline)
                .foregroundColor(Theme.palette(choice: settings.themeChoice, darkMode: settings.darkMode).textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
