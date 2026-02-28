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
    
    var body: some View {
        let palette = Theme.palette(choice: settings.themeChoice, darkMode: settings.darkMode)
        NavigationStack {
            ZStack {
                palette.gradient.ignoresSafeArea()
                
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
                                    Image(uiImage: best)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 140, height: 90)
                                        .clipped()
                                        .cornerRadius(10)
                                }
                                if let worst = manager.worstSnapshot {
                                    Image(uiImage: worst)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 140, height: 90)
                                        .clipped()
                                        .cornerRadius(10)
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
