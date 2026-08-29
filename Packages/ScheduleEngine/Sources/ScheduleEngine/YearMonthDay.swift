import Foundation

/// A calendar date with no time and no time zone, used as the key for the
/// rotation. Comparing `Date` values for "same day" is a common source of
/// off-by-one-day bugs, so the engine never does it.
public struct YearMonthDay: Hashable, Codable, Comparable, Sendable, Identifiable, CustomStringConvertible {

    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = components.year ?? 1
        self.month = components.month ?? 1
        self.day = components.day ?? 1
    }

    /// Parses `"2026-09-08"`.
    public init?(iso8601: String) {
        let parts = iso8601.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// The ISO string doubles as the identity, which is also how a date is keyed
    /// in the store.
    public var id: String { description }

    /// Midnight at the start of this day in the engine's time zone.
    public func startOfDay(in calendar: Calendar) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 0
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    /// The instant at `time` on this day, resolved as a wall-clock time so that a
    /// daylight-saving transition does not slide the whole bell schedule.
    public func date(at time: TimeOfDay, in calendar: Calendar) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        if let date = calendar.date(from: components) {
            return date
        }
        // Only reachable for a wall-clock time that does not exist on this day
        // (spring forward). Fall back to counting minutes from midnight.
        return startOfDay(in: calendar).addingTimeInterval(TimeInterval(time.minutes * 60))
    }

    public func adding(days: Int, in calendar: Calendar) -> YearMonthDay {
        let shifted = calendar.date(byAdding: .day, value: days, to: startOfDay(in: calendar))
        return YearMonthDay(date: shifted ?? startOfDay(in: calendar), calendar: calendar)
    }

    /// 1 = Sunday ... 7 = Saturday, matching `Calendar.component(.weekday:)`.
    public func weekday(in calendar: Calendar) -> Int {
        calendar.component(.weekday, from: startOfDay(in: calendar))
    }

    public static func < (lhs: YearMonthDay, rhs: YearMonthDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
