import SwiftUI

struct AnalyseView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showOffline = false


    var body: some View {
        let palette = Theme.palette(choice: settings.themeChoice, darkMode: settings.darkMode)
        ZStack {
            palette.gradient.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {

                VStack(alignment: .leading, spacing: 6) {


                    Text("Video Analysis")
                         .font(.system(size:  30, weight: .heavy, design: .rounded))

                         .foregroundColor( palette.textPrimary)
                    Text("Upload a recording to get a full rep-by-rep breakdown with form feedback and snapshots.")
                        .font(.subheadline)

                        .foregroundColor(palette.textSecondary)
                }

                Button {

                    showOffline = true
                } label: {

                    analyseCard(
                            title: "Analyse a Recording",
                            
                            subtitle: "Rep timeline · Snapshots · Score",
                            icon:  "film",
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
    }
    
    
    private func analyseCard(title: String, subtitle: String, icon: String, palette: ThemePalette) -> some View {
        
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
