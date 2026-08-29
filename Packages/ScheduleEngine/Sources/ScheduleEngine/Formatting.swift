import Foundation

/// Countdown and time formatting shared by the app and the widget, so that the
/// number on the home screen and the number in the app are always the same
/// string.
public enum ScheduleFormatting {

    /// The glance format: "23 min", "1:05", "now".
    ///
    /// Under an hour it reads in whole minutes, because seconds ticking on a
    /// home screen widget are both wrong (the widget cannot update that often)
    /// and unreadable at arm's length.
    public static func countdown(seconds: Int) -> String {
        guard seconds > 0 else { return "now" }
        let minutes = Int((Double(seconds) / 60).rounded(.up))
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        return String(format: "%d:%02d", hours, remainder)
    }

    /// The dominant element on the small widget: a bare number, with its unit
    /// rendered separately and smaller.
    public static func countdownValue(seconds: Int) -> String {
        guard seconds > 0 else { return "0" }
        let minutes = Int((Double(seconds) / 60).rounded(.up))
        if minutes < 60 { return "\(minutes)" }
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    public static func countdownUnit(seconds: Int) -> String {
        let minutes = Int((Double(seconds) / 60).rounded(.up))
        return minutes < 60 ? "min" : "hrs"
    }

    /// "8:15" or "8:15 AM" depending on the device's clock setting.
    public static func clock(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    public static func range(_ period: ResolvedPeriod, timeZone: TimeZone) -> String {
        "\(clock(period.start, timeZone: timeZone))\u{2009}\u{2013}\u{2009}\(clock(period.end, timeZone: timeZone))"
    }

    /// "Mon, Sep 8"
    public static func mediumDay(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter.string(from: date)
    }

    /// "2 min ago", "just now". Used for ping freshness.
    public static func relativePast(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }

    /// One line summarising a snapshot, used by the lock screen rectangular
    /// widget and by accessibility labels everywhere else.
    public static func glanceLine(for snapshot: ScheduleSnapshot, timeZone: TimeZone) -> String {
        switch snapshot.status {
        case .noSchool(let reason):
            return reason
        case .beforeSchool(let next):
            let seconds = snapshot.secondsRemaining ?? 0
            return "\(next.title) in \(countdown(seconds: seconds))"
        case .inPeriod(let current, _):
            let seconds = snapshot.secondsRemaining ?? 0
            if let room = current.room {
                return "\(current.title) \u{00B7} \(room) \u{00B7} \(countdown(seconds: seconds))"
            }
            return "\(current.title) \u{00B7} \(countdown(seconds: seconds))"
        case .passing(_, let next):
            let seconds = snapshot.secondsRemaining ?? 0
            if let room = next.room {
                return "\(next.title) \u{00B7} \(room) \u{00B7} in \(countdown(seconds: seconds))"
            }
            return "\(next.title) in \(countdown(seconds: seconds))"
        case .dayComplete(let nextDay):
            guard let nextDay else { return "Done for today" }
            return "Tomorrow: \(nextDay.title) at \(clock(nextDay.start, timeZone: timeZone))"
        }
    }
}
