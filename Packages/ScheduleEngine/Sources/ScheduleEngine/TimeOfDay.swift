import Foundation

/// A wall-clock time of day, stored as minutes from midnight.
///
/// The whole schedule engine works in minutes-from-midnight rather than `Date`
/// so that a bell schedule is independent of any particular calendar day.
public struct TimeOfDay: Hashable, Codable, Comparable, Sendable, CustomStringConvertible {

    /// Minutes elapsed since midnight. Values beyond 24h are allowed so that a
    /// period may legally end at `24:00`.
    public var minutes: Int

    public init(minutes: Int) {
        self.minutes = minutes
    }

    public init(hour: Int, minute: Int) {
        self.minutes = hour * 60 + minute
    }

    /// Parses `"08:15"`. Tolerates `"8:15"`, `"08:15:00"`, and `"8:15 AM"` /
    /// `"3:40 PM"`, because pasted and photographed schedules are inconsistent.
    public init?(_ text: String) {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        var meridiem: String?
        for marker in ["A.M.", "P.M.", "AM", "PM"] where value.hasSuffix(marker) {
            meridiem = marker.hasPrefix("A") ? "AM" : "PM"
            value = String(value.dropLast(marker.count)).trimmingCharacters(in: .whitespaces)
            break
        }

        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              let rawHour = Int(parts[0]), let minute = Int(parts[1]),
              (0...59).contains(minute)
        else { return nil }

        var hour = rawHour
        switch meridiem {
        case "AM":
            guard (1...12).contains(hour) else { return nil }
            if hour == 12 { hour = 0 }
        case "PM":
            guard (1...12).contains(hour) else { return nil }
            if hour != 12 { hour += 12 }
        default:
            guard (0...24).contains(hour) else { return nil }
        }

        self.minutes = hour * 60 + minute
    }

    public var hour: Int { minutes / 60 }
    public var minute: Int { minutes % 60 }

    /// Zero-padded 24-hour representation, the same shape the import contract uses.
    public var description: String {
        String(format: "%02d:%02d", hour, minute)
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutes < rhs.minutes
    }
}
