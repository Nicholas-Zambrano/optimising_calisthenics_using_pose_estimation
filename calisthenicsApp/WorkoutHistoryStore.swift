import Foundation
import Combine

struct SessionRecord: Identifiable, Codable {
    let id: UUID
    let date: Date
    let exercise: String
    let totalReps: Int
    let averageScore: Int
    let cleanReps: Int
    let bestRep: Int
    let worstRep: Int
    let mostCommonIssue: String?
    let source: String
}

final class WorkoutHistoryStore: ObservableObject {
    @Published private(set) var sessions: [SessionRecord] = []
    private let fileURL: URL
    
    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("workout_history.json")
        load()
    }
    
    func addSession(exercise: String, summary: SessionSummary, source: String) {
        let record = SessionRecord(
            id: UUID(),
            date: Date(),
            exercise: exercise,
            totalReps: summary.totalReps,
            averageScore: summary.averageScore,
            cleanReps: summary.cleanReps,
            bestRep: summary.bestRep,
            worstRep: summary.worstRep,
            mostCommonIssue: summary.mostCommonIssueMessage,
            source: source
        )
        sessions.insert(record, at: 0)
        save()
    }
    
    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([SessionRecord].self, from: data) {
            sessions = decoded
        }
    }
    
    private func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
