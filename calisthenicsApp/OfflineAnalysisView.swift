import SwiftUI
import PhotosUI

struct OfflineAnalysisView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var historyStore: WorkoutHistoryStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = OfflineAnalysisManager()
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedURL: URL?
    @State private var selectedExercise: String = "Push-Up"
    @State private var showSavedAlert = false
    @State private var savedMessage = ""
    @State private var savedHistory = false
    @State private var exportURL: URL?
    @State private var mirrorOverlay = true
    @State private var selectedRepID: UUID?
    
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
                        
                        Text("Upload a workout video and get feedback.")
                            .foregroundColor(palette.textSecondary)
                        
                        Picker("Exercise", selection: $selectedExercise) {
                            Text("Push-Up").tag("Push-Up")
                            Text("Squat").tag("Squat")
                            Text("Pull-Up").tag("Pull-Up")
                        }
                        .pickerStyle(.segmented)

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

                    Button {
                        guard let url = selectedURL else { return }
                        manager.exportAnnotatedVideo(url: url, exercise: selectedExercise, settings: settings) { output in
                            exportURL = output
                            if let output = output {
                                UISaveVideoAtPathToSavedPhotosAlbum(output.path, nil, nil, nil)
                                savedMessage = "Annotated video saved to Photos"
                                showSavedAlert = true
                            }
                        }
                    } label: {
                        Text(manager.isExporting ? "Exporting..." : "Export Annotated Video")
                            .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedURL == nil ? Color.gray : palette.cardAlt)
                        .foregroundColor(palette.textPrimary)
                        .cornerRadius(12)
                    }
                    .disabled(selectedURL == nil || manager.isExporting)

                    if manager.isExporting {
                        Button("Cancel Export") {
                            manager.cancel()
                            manager.isExporting = false
                            manager.status = "Export cancelled"
                            manager.logLines.append("Export cancelled")
                        }
                        .foregroundColor(palette.textSecondary)
                    }
                    
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
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Rep Timeline")
                                    .font(.headline)
                                    .foregroundColor(palette.textPrimary)
                                
                                ForEach(manager.repSummaries) { rep in
                                    Button {
                                        selectedRepID = rep.id
                                    } label: {
                                        HStack(spacing: 10) {
                                            Text("#\(rep.repIndex)")
                                                .font(.caption.bold())
                                                .frame(width: 36, alignment: .leading)
                                            Text(rep.timestampLabel)
                                                .font(.caption)
                                                .foregroundColor(palette.textSecondary)
                                                .frame(width: 50, alignment: .leading)
                                            Text("\(rep.score)%")
                                                .font(.caption.bold())
                                                .frame(width: 50, alignment: .leading)
                                            Text(rep.riskLabel)
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(palette.cardAlt.opacity(0.9))
                                                .cornerRadius(6)
                                            Text(rep.primaryMessage)
                                                .font(.caption)
                                                .foregroundColor(palette.textSecondary)
                                                .lineLimit(1)
                                            Spacer()
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

                        if let selected = manager.repSummaries.first(where: { $0.id == selectedRepID }),
                           let snap = selected.snapshot {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Selected Rep \(selected.repIndex)")
                                    .font(.caption).bold()
                                    .foregroundColor(palette.textSecondary)
                                Image(uiImage: snap)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 160)
                                    .clipped()
                                    .cornerRadius(12)
                                Text("\(selected.riskLabel): \(selected.primaryMessage)")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }
                            .padding(.top, 6)
                        }

                    if !manager.logLines.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Processing Log")
                                .font(.headline)
                                .foregroundColor(palette.textPrimary)
                            ForEach(Array(manager.logLines.enumerated()), id: \.offset) { _, line in
                                Text("• \(line)")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }
                        }
                        .padding(.top, 8)
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
        }
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
