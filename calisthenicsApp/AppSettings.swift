import SwiftUI
import Combine

final class AppSettings: ObservableObject {
    @Published var audioEnabled: Bool {
        didSet { UserDefaults.standard.set(audioEnabled, forKey: "audioEnabled") }
    }
    @Published var sensitivity: FeedbackSensitivity {
        didSet { UserDefaults.standard.set(sensitivity.rawValue, forKey: "sensitivity") }
    }
    @Published var focus: FeedbackFocus {
        didSet { UserDefaults.standard.set(focus.rawValue, forKey: "focus") }
    }
    @Published var targetReps: Int {
        didSet { UserDefaults.standard.set(targetReps, forKey: "targetReps") }
    }
    @Published var themeChoice: ThemeChoice {
        didSet { UserDefaults.standard.set(themeChoice.rawValue, forKey: "themeChoice") }
    }
    @Published var darkMode: Bool {
        didSet { UserDefaults.standard.set(darkMode, forKey: "darkMode") }
    }
    @Published var debugEnabled: Bool {
        didSet { UserDefaults.standard.set(debugEnabled, forKey: "debugEnabled") }
    }
    @Published var userStudyMode: Bool {
        didSet { UserDefaults.standard.set(userStudyMode, forKey: "userStudyMode") }
    }
    
    init() {
        if UserDefaults.standard.object(forKey: "audioEnabled") == nil {
            self.audioEnabled = true
        } else {
            self.audioEnabled = UserDefaults.standard.bool(forKey: "audioEnabled")
        }
        let sensRaw = UserDefaults.standard.string(forKey: "sensitivity") ?? FeedbackSensitivity.normal.rawValue
        self.sensitivity = FeedbackSensitivity(rawValue: sensRaw) ?? .normal
        let focusRaw = UserDefaults.standard.string(forKey: "focus") ?? FeedbackFocus.armsOnly.rawValue
        self.focus = FeedbackFocus(rawValue: focusRaw) ?? .armsOnly
        let reps = UserDefaults.standard.integer(forKey: "targetReps")
        self.targetReps = reps == 0 ? 10 : reps
        let themeRaw = UserDefaults.standard.string(forKey: "themeChoice") ?? ThemeChoice.gold.rawValue
        self.themeChoice = ThemeChoice(rawValue: themeRaw) ?? .gold
        if UserDefaults.standard.object(forKey: "darkMode") == nil {
            self.darkMode = true
        } else {
            self.darkMode = UserDefaults.standard.bool(forKey: "darkMode")
        }
        if UserDefaults.standard.object(forKey: "debugEnabled") == nil {
            self.debugEnabled = false
        } else {
            self.debugEnabled = UserDefaults.standard.bool(forKey: "debugEnabled")
        }
        self.userStudyMode = UserDefaults.standard.bool(forKey: "userStudyMode")
    }
}
