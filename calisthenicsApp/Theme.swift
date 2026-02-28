import SwiftUI

enum ThemeChoice: String, CaseIterable {
    case gold = "Gold"
    case electric = "Electric"
    case mint = "Mint"
    case crimson = "Crimson"
}

struct ThemePalette {
    let accent: Color
    let accentAlt: Color
    let bgTop: Color
    let bgBottom: Color
    let card: Color
    let cardAlt: Color
    let textPrimary: Color
    let textSecondary: Color
    
    var gradient: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum Theme {
    static func palette(choice: ThemeChoice, darkMode: Bool) -> ThemePalette {
        switch choice {
        case .gold:
            return ThemePalette(
                accent: Color(red: 0.94, green: 0.76, blue: 0.25),
                accentAlt: Color(red: 0.32, green: 0.86, blue: 0.62),
                bgTop: darkMode ? Color(red: 0.05, green: 0.06, blue: 0.10) : Color(red: 0.92, green: 0.95, blue: 0.98),
                bgBottom: darkMode ? Color(red: 0.02, green: 0.03, blue: 0.05) : Color(red: 0.80, green: 0.88, blue: 0.97),
                card: darkMode ? Color(white: 0.12) : Color.white.opacity(0.85),
                cardAlt: darkMode ? Color(white: 0.16) : Color.white.opacity(0.95),
                textPrimary: darkMode ? .white : Color(red: 0.06, green: 0.08, blue: 0.10),
                textSecondary: darkMode ? Color.white.opacity(0.7) : Color(red: 0.25, green: 0.30, blue: 0.35)
            )
        case .electric:
            return ThemePalette(
                accent: Color(red: 0.35, green: 0.65, blue: 1.00),
                accentAlt: Color(red: 0.55, green: 0.95, blue: 1.00),
                bgTop: darkMode ? Color(red: 0.04, green: 0.06, blue: 0.12) : Color(red: 0.90, green: 0.95, blue: 1.00),
                bgBottom: darkMode ? Color(red: 0.02, green: 0.03, blue: 0.08) : Color(red: 0.78, green: 0.86, blue: 1.00),
                card: darkMode ? Color(white: 0.12) : Color.white.opacity(0.9),
                cardAlt: darkMode ? Color(white: 0.16) : Color.white,
                textPrimary: darkMode ? .white : Color(red: 0.05, green: 0.08, blue: 0.12),
                textSecondary: darkMode ? Color.white.opacity(0.7) : Color(red: 0.22, green: 0.28, blue: 0.36)
            )
        case .mint:
            return ThemePalette(
                accent: Color(red: 0.25, green: 0.92, blue: 0.70),
                accentAlt: Color(red: 0.10, green: 0.75, blue: 0.55),
                bgTop: darkMode ? Color(red: 0.04, green: 0.08, blue: 0.08) : Color(red: 0.90, green: 0.98, blue: 0.96),
                bgBottom: darkMode ? Color(red: 0.02, green: 0.04, blue: 0.05) : Color(red: 0.78, green: 0.94, blue: 0.90),
                card: darkMode ? Color(white: 0.12) : Color.white.opacity(0.9),
                cardAlt: darkMode ? Color(white: 0.16) : Color.white,
                textPrimary: darkMode ? .white : Color(red: 0.06, green: 0.10, blue: 0.10),
                textSecondary: darkMode ? Color.white.opacity(0.7) : Color(red: 0.24, green: 0.32, blue: 0.30)
            )
        case .crimson:
            return ThemePalette(
                accent: Color(red: 0.95, green: 0.35, blue: 0.35),
                accentAlt: Color(red: 1.00, green: 0.55, blue: 0.55),
                bgTop: darkMode ? Color(red: 0.08, green: 0.04, blue: 0.06) : Color(red: 0.98, green: 0.92, blue: 0.92),
                bgBottom: darkMode ? Color(red: 0.04, green: 0.02, blue: 0.03) : Color(red: 0.92, green: 0.80, blue: 0.82),
                card: darkMode ? Color(white: 0.12) : Color.white.opacity(0.9),
                cardAlt: darkMode ? Color(white: 0.16) : Color.white,
                textPrimary: darkMode ? .white : Color(red: 0.10, green: 0.06, blue: 0.08),
                textSecondary: darkMode ? Color.white.opacity(0.7) : Color(red: 0.36, green: 0.22, blue: 0.26)
            )
        }
    }
}
