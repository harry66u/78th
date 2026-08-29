import SwiftUI
import ScheduleEngine

/// The app's visual vocabulary, shared with the widget so a course looks the
/// same on the home screen as it does in the app.
public enum Theme {

    /// Course colours. Deliberately muted: this is a school utility that an
    /// adult may pick up, not a toy.
    public static let coursePalette: [Color] = [
        Color(red: 0.32, green: 0.45, blue: 0.72),   // slate blue
        Color(red: 0.26, green: 0.55, blue: 0.47),   // pine
        Color(red: 0.71, green: 0.44, blue: 0.24),   // clay
        Color(red: 0.48, green: 0.36, blue: 0.62),   // plum
        Color(red: 0.26, green: 0.50, blue: 0.60),   // teal
        Color(red: 0.66, green: 0.34, blue: 0.40),   // brick
        Color(red: 0.40, green: 0.48, blue: 0.28),   // olive
        Color(red: 0.45, green: 0.45, blue: 0.50)    // graphite
    ]

    public static func courseColor(_ tag: Int) -> Color {
        guard !coursePalette.isEmpty else { return .accentColor }
        let index = ((tag % coursePalette.count) + coursePalette.count) % coursePalette.count
        return coursePalette[index]
    }

    public static func courseColor(for period: ResolvedPeriod) -> Color {
        period.course == nil ? Color.secondary : courseColor(period.colorTag)
    }

    /// The countdown numeral. Rounded, heavy, and tight, because the success
    /// test for the widget is reading it from arm's length in a hallway.
    public static func countdownFont(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}
