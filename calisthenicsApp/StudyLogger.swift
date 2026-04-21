import Foundation
import UIKit

struct StudyRepRow {
    let participantID: String
    let exercise: String
    let condition: String
    let conditionOrder: Int
    let repNumber: Int
    let repScore: Int
    let riskLevel: String
    let criticalErrors: Int
    let importantErrors: Int
    let backAngleCritical: Int
    let elbowFlareCritical: Int
    let shoulderAsymCritical: Int
    let shallowDepth: Int
    let tempoFast: Int
    let depthProgress: Double
    let repDurationSec: Double
    let timestampMS: Int
}

final class StudyLogger {
    static let shared = StudyLogger()
    private var rows: [StudyRepRow] = []

    var isEmpty: Bool { rows.isEmpty }
    var count: Int { rows.count }

    func logRep(_ row: StudyRepRow) {
        rows.append(row)
        print("[StudyLogger] rep=\(row.repNumber) participant=\(row.participantID) condition=\(row.condition) score=\(row.repScore) risk=\(row.riskLevel)")
    }

    func clear() {
        rows = []
    }

    func buildCSV() -> String {
        let header = "participant_id,exercise,condition,condition_order,rep_number,rep_score,risk_level,critical_errors,important_errors,back_angle_critical,elbow_flare_critical,shoulder_asym_critical,shallow_depth,tempo_fast,depth_progress,rep_duration_sec,timestamp_ms"
        let dataRows = rows.map { r -> String in
            [r.participantID,
             r.exercise,
             r.condition,
             "\(r.conditionOrder)",
             "\(r.repNumber)",
             "\(r.repScore)",
             r.riskLevel,
             "\(r.criticalErrors)",
             "\(r.importantErrors)",
             "\(r.backAngleCritical)",
             "\(r.elbowFlareCritical)",
             "\(r.shoulderAsymCritical)",
             "\(r.shallowDepth)",
             "\(r.tempoFast)",
             String(format: "%.2f", r.depthProgress),
             String(format: "%.2f", r.repDurationSec),
             "\(r.timestampMS)"
            ].joined(separator: ",")
        }
        return ([header] + dataRows).joined(separator: "\n")
    }

    func exportURL(participantID: String, condition: String) -> URL? {
        let csv = buildCSV()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let safeID = participantID.isEmpty ? "unknown" : participantID.replacingOccurrences(of: " ", with: "_")
        let safeCond = condition.replacingOccurrences(of: " ", with: "_")
        let safeExercise = (rows.first?.exercise ?? "unknown").replacingOccurrences(of: " ", with: "_").lowercased()
        let filename = "study_\(safeID)_\(safeExercise)_\(safeCond)_\(formatter.string(from: Date())).csv"
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent(filename)
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            print("[StudyLogger] Exported \(rows.count) rows to \(filename)")
            return url
        } catch {
            print("[StudyLogger] Export failed: \(error)")
            return nil
        }
    }
}
