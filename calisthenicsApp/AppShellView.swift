import SwiftUI

//  root view for the app, defining the main navifations
struct AppShellView: View {

    //  these are the overall seeting for all views
    @StateObject private var settings = AppSettings()
    @StateObject private var historyStore = WorkoutHistoryStore()
    
    var body: some View {
        let palette = Theme.palette(choice: settings.themeChoice, darkMode: settings.darkMode)

        TabView {

            NavigationStack {
                
                MainMenuView()
            }

            .tabItem {
                Image(systemName: "figure.strengthtraining.traditional")
                    Text("Workouts")
            }
            

            NavigationStack {
                AnalyseView()
            }

            .tabItem {
                Image(systemName: "waveform.path.ecg")
                Text("Analyse")
            }
            

            NavigationStack {
                HistoryView()
            }

            .tabItem {
                Image(systemName: "clock.arrow.circlepath")
                Text ("History")
            }
            
            NavigationStack {
                SettingsView()
            }
            .tabItem {
               
                Image(systemName: "gearshape")
                Text("Settings")
            }
        }


        .environmentObject(settings)
        .environmentObject(historyStore)
        .accentColor(palette.accent)
        .preferredColorScheme(settings.darkMode ?.dark :  .light)
    }
}
