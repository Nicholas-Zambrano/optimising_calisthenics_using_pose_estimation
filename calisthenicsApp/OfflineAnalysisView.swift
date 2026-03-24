import SwiftUI
import PhotosUI
import AVKit
import Charts

struct OfflineAnalysisView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var historyStore: WorkoutHistoryStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = OfflineAnalysisManager()
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedURL: URL?
    @AppStorage("offlineAnalysisExercise") private var selectedExercise: String = "Squat"
    @State private var showSavedAlert = false
    @State private var savedMessage = ""
    @State private var savedHistory = false
    @State private var mirrorOverlay = false
    @State private var selectedRepID: UUID?
    @State private var repPlayer: AVPlayer?
    
    var body: some View {
        let palette = Theme.palette(choice: settings.themeChoice, darkMode: settings.darkMode)
        NavigationStack {
            ZStack {
                palette.gradient.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Offline Analysis")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundColor(palette.textPrimary)
                        
                        Text("Upload a workout video and get rep-by-rep feedback. For best results, record side-on for pull-ups and push-ups, or side-on / front-facing for squats.")
                            .foregroundColor(palette.textSecondary)
                            .font(.subheadline)
                        
                        Picker("Exercise", selection: $selectedExercise) {
                            Text("Push-Up").tag("Push-Up")
                            Text("Squat").tag("Squat")
                            Text("Pull-Up").tag("Pull-Up")
                        }
                        .pickerStyle(.segmented)

                        cameraGuideCard(for: selectedExercise, palette: palette)

                        Toggle("Mirror Overlay (front camera)", isOn: $mirrorOverlay)
                            .tint(palette.accent)
                            .foregroundColor(palette.textSecondary)
                            .onChange(of: mirrorOverlay) { value in
                                manager.mirrorOverlay = value
                            }
                        
                        PhotosPicker(selection: $selectedItem, matching: .videos) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text(selectedURL == nil ? "Choose Video" : "Video Selected")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(white: 0.12))
                            .foregroundColor(palette.textPrimary)
                            .cornerRadius(12)
                        }
                        .onChange(of: selectedItem) { newItem in
                            Task {
                                guard let item = newItem else { return }
                                selectedRepID = nil
                                repPlayer = nil
                                savedHistory = false
                                if let data = try? await item.loadTransferable(type: Data.self) {
                                    let tempURL = FileManager.default.temporaryDirectory
                                        .appendingPathComponent("offline-\(UUID().uuidString).mov")
                                    do {
                                        try data.write(to: tempURL, options: [.atomic])
                                        selectedURL = tempURL
                                        manager.status = "Video loaded"
                                    } catch {
                                        manager.status = "Failed to load video"
                                    }
                                } else {
                                    manager.status = "Failed to read video"
                                }
                            }
                        }
                        
                        Button {
                            guard let url = selectedURL else { return }
                            manager.analyzeVideo(url: url, exercise: selectedExercise, settings: settings)
                        } label: {
                            Text(manager.isRunning ? "Analyzing..." : "Start Analysis")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(selectedURL == nil ? Color.gray : palette.accent)
                                .foregroundColor(.black)
                                .cornerRadius(12)
                        }
                        .disabled(selectedURL == nil || manager.isRunning)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text(manager.status)
                                .foregroundColor(palette.textSecondary)
                            ProgressView(value: manager.progress)
                                .tint(Color(red: 0.94, green: 0.76, blue: 0.25))
                        }
                        .padding(.top, 8)

                    if let summary = manager.sessionSummary {
                        VStack(spacing: 10) {
                            summaryRow(label: "Total Reps", value: "\(summary.totalReps)")
                            summaryRow(label: "Avg Quality", value: "\(summary.averageScore)%")
                            summaryRow(label: "Clean Reps", value: "\(summary.cleanReps)")
                            summaryRow(label: "Best Rep", value: "\(summary.bestRep)%")
                            summaryRow(label: "Worst Rep", value: "\(summary.worstRep)%")
                            if let issue = summary.mostCommonIssueMessage {
                                summaryRow(label: "Most Common", value: issue)
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(16)
                        .padding(.top, 8)
                    }
                    
                    if manager.bestSnapshot != nil || manager.worstSnapshot != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Snapshots")
                                .font(.headline)
                                .foregroundColor(palette.textPrimary)
                            
                            HStack(spacing: 12) {
                                if let best = manager.bestSnapshot {
                                    VStack(spacing: 6) {
                                        Image(uiImage: best)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 140, height: 90)
                                            .clipped()
                                            .cornerRadius(10)
                                        Text("Best Rep")
                                            .font(.caption2)
                                            .foregroundColor(palette.textSecondary)
                                    }
                                }
                                if let worst = manager.worstSnapshot {
                                    VStack(spacing: 6) {
                                        Image(uiImage: worst)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 140, height: 90)
                                            .clipped()
                                            .cornerRadius(10)
                                        Text("Worst Rep")
                                            .font(.caption2)
                                            .foregroundColor(palette.textSecondary)
                                    }
                                }
                            }
                            
                            Button {
                                saveSnapshots()
                            } label: {
                                Text("Save Snapshots to Photos")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.white)
                                    .foregroundColor(.black)
                                    .cornerRadius(12)
                            }
                        }
                        .padding(.top, 8)
                    }

                    if !manager.repSummaries.isEmpty {
                            let bestID = manager.repSummaries.max(by: { $0.score < $1.score })?.id
                            let worstID = manager.repSummaries.count > 1 ? manager.repSummaries.min(by: { $0.score < $1.score })?.id : nil
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Rep Timeline — tap to review")
                                    .font(.headline)
                                    .foregroundColor(palette.textPrimary)
                                
                                ForEach(manager.repSummaries) { rep in
                                    Button {
                                        selectedRepID = rep.id
                                    } label: {
                                        HStack(spacing: 8) {
                                            Text("#\(rep.repIndex)")
                                                .font(.caption.bold())
                                                .frame(width: 28, alignment: .leading)
                                            Group {
                                                if rep.id == bestID {
                                                    Text("★ Best").foregroundColor(.yellow)
                                                } else if rep.id == worstID {
                                                    Text("▼ Worst").foregroundColor(.red)
                                                } else {
                                                    Text("").foregroundColor(.clear)
                                                }
                                            }
                                            .font(.caption2.bold())
                                            .frame(width: 46, alignment: .leading)
                                            Text("\(rep.score)%")
                                                .font(.caption.bold())
                                                .frame(width: 36, alignment: .leading)
                                            Text(rep.riskLabel)
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(rep.risk == .critical ? Color.red.opacity(0.25) : (rep.risk == .medium ? Color.orange.opacity(0.25) : Color.green.opacity(0.25)))
                                                .foregroundColor(rep.risk == .critical ? .red : (rep.risk == .medium ? .orange : .green))
                                                .cornerRadius(5)
                                            Text(rep.primaryMessage)
                                                .font(.caption)
                                                .foregroundColor(palette.textSecondary)
                                                .lineLimit(1)
                                            Spacer()
                                            Image(systemName: "play.circle.fill")
                                                .font(.caption)
                                                .foregroundColor(palette.textSecondary)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(selectedRepID == rep.id ? palette.cardAlt.opacity(0.85) : palette.card.opacity(0.8))
                                        .cornerRadius(10)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 8)
                        }

                    if let selected = manager.repSummaries.first(where: { $0.id == selectedRepID }) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Rep \(selected.repIndex) — \(selected.riskLabel)")
                                        .font(.caption.bold())
                                        .foregroundColor(palette.textPrimary)
                                    Spacer()
                                    Text("Score: \(selected.score)%")
                                        .font(.caption.bold())
                                        .foregroundColor(selected.score >= 85 ? .green : (selected.score >= 55 ? .orange : .red))
                                }
                                if let player = repPlayer {
                                    VideoPlayer(player: player)
                                        .frame(height: 240)
                                        .cornerRadius(12)
                                } else if let snap = selected.snapshot {
                                    Image(uiImage: snap)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 240)
                                        .clipped()
                                        .cornerRadius(12)
                                }
                                Text("Peak at \(selected.timestampLabel)")
                                    .font(.caption2)
                                    .foregroundColor(palette.textSecondary.opacity(0.7))
                                if selected.allMessages.isEmpty {
                                    Text("✓ Form looks clean for this rep")
                                        .font(.caption.bold())
                                        .foregroundColor(.green)
                                } else {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("Issues found:")
                                            .font(.caption2.bold())
                                            .foregroundColor(palette.textSecondary)
                                        ForEach(0..<selected.allMessages.count, id: \.self) { i in
                                            let item = selected.allMessages[i]
                                            HStack(alignment: .top, spacing: 6) {
                                                Text(item.severity == .critical ? "CRITICAL" : (item.severity == .important ? "IMPORTANT" : "MINOR"))
                                                    .font(.system(size: 9, weight: .heavy))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .background(item.severity == .critical ? Color.red.opacity(0.2) : (item.severity == .important ? Color.orange.opacity(0.2) : Color.yellow.opacity(0.2)))
                                                    .foregroundColor(item.severity == .critical ? .red : (item.severity == .important ? .orange : .yellow))
                                                    .cornerRadius(4)
                                                Text(item.message)
                                                    .font(.caption)
                                                    .foregroundColor(palette.textPrimary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                    }
                                }
                                if !selected.angleSamples.isEmpty {
                                    let angleLabel = selectedExercise.lowercased().contains("squat") ? "Knee Angle" : "Elbow Angle"
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(angleLabel)
                                                .font(.caption2.bold())
                                                .foregroundColor(palette.textSecondary)
                                            Spacer()
                                            Text("— green line = 90° target depth")
                                                .font(.system(size: 9))
                                                .foregroundColor(.green.opacity(0.8))
                                        }
                                        Chart {
                                            ForEach(0..<selected.angleSamples.count, id: \.self) { i in
                                                LineMark(
                                                    x: .value("Frame", i),
                                                    y: .value("°", selected.angleSamples[i])
                                                )
                                                .foregroundStyle(Color.yellow)
                                                .interpolationMethod(.catmullRom)
                                                .lineStyle(StrokeStyle(lineWidth: 2))
                                            }
                                            RuleMark(y: .value("Target depth", 90.0))
                                                .foregroundStyle(Color.green.opacity(0.8))
                                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                                        }
                                        .frame(height: 110)
                                        .chartYScale(domain: 40.0...180.0)
                                        .chartXAxis(.hidden)
                                        .chartYAxis {
                                            AxisMarks(values: [60.0, 90.0, 120.0, 150.0]) { v in
                                                AxisValueLabel {
                                                    if let val = v.as(Double.self) {
                                                        Text("\(Int(val))°")
                                                            .font(.system(size: 9))
                                                            .foregroundColor(palette.textSecondary)
                                                    }
                                                }
                                                AxisGridLine()
                                            }
                                        }
                                        .background(Color.white.opacity(0.05))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                            .padding(.top, 6)
                    }
                    
                        Spacer()
                    }
                    .padding()
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert(savedMessage, isPresented: $showSavedAlert) {
                Button("OK", role: .cancel) { }
            }
            .onChange(of: manager.status) { newStatus in
                guard newStatus == "Complete",
                      let summary = manager.sessionSummary,
                      savedHistory == false else { return }
                historyStore.addSession(
                    exercise: selectedExercise,
                    summary: summary,
                    source: "Offline"
                )
                savedHistory = true
            }
            .onChange(of: selectedRepID) { newID in
                guard let id = newID,
                      let rep = manager.repSummaries.first(where: { $0.id == id }),
                      let url = selectedURL else {
                    repPlayer = nil
                    return
                }
                let player = AVPlayer(url: url)
                let peakTime = CMTime(value: CMTimeValue(rep.peakTimestampMS), timescale: 1000)
                player.seek(to: peakTime,
                            toleranceBefore: CMTime(seconds: 0.5, preferredTimescale: 600),
                            toleranceAfter: CMTime(seconds: 0.5, preferredTimescale: 600))
                repPlayer = player
            }
        }
    }
    
    private func cameraGuideData(for exercise: String) -> (angle: String, height: String, tip: String) {
        let ex = exercise.lowercased()
        if ex.contains("pull") {
            return (
                "Side-on (arm plane facing camera)",
                "Chest height, 2–3 m away",
                "Side view gives the most accurate elbow angle and chin-over-bar detection."
            )
        } else if ex.contains("push") {
            return (
                "Side-on (body parallel to camera)",
                "Floor level or low tripod, 1.5–2 m away",
                "Side view captures elbow flexion and body alignment clearly."
            )
        } else {
            return (
                "Side-on or directly front-facing",
                "Hip height, 1.5–2 m away",
                "Side view measures lean and knee travel; front view measures knee valgus. Both are supported."
            )
        }
    }

    private func cameraGuideCard(for exercise: String, palette: ThemePalette) -> some View {
        let data = cameraGuideData(for: exercise)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "camera.fill")
                .foregroundColor(.blue)
                .font(.caption)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text("Camera Setup")
                    .font(.caption.bold())
                    .foregroundColor(palette.textPrimary)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.turn.up.right.circle")
                        .font(.system(size: 9))
                    Text("Angle: \(data.angle)")
                        .font(.system(size: 11))
                }
                .foregroundColor(palette.textSecondary)
                HStack(spacing: 4) {
                    Image(systemName: "ruler")
                        .font(.system(size: 9))
                    Text("Position: \(data.height)")
                        .font(.system(size: 11))
                }
                .foregroundColor(palette.textSecondary)
                Text(data.tip)
                    .font(.system(size: 10))
                    .foregroundColor(palette.textSecondary.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.blue.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.25), lineWidth: 1))
        .cornerRadius(10)
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundColor(Theme.palette(choice: settings.themeChoice, darkMode: settings.darkMode).textSecondary)
            Spacer()
            Text(value).foregroundColor(Theme.palette(choice: settings.themeChoice, darkMode: settings.darkMode).textPrimary)
        }
    }

    private func saveSnapshots() {
        var saved = 0
        if let best = manager.bestSnapshot {
            UIImageWriteToSavedPhotosAlbum(best, nil, nil, nil)
            saved += 1
        }
        if let worst = manager.worstSnapshot {
            UIImageWriteToSavedPhotosAlbum(worst, nil, nil, nil)
            saved += 1
        }
        savedMessage = saved > 0 ? "Saved \(saved) snapshot(s) to Photos" : "No snapshots to save"
        showSavedAlert = true
    }
}
