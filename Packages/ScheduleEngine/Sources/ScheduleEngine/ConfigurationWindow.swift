import Foundation

/// Narrowing a configuration to the part of it that a given moment can reach.
///
/// The dated overrides are the only part of a configuration that grows without
/// bound: a full school year is several hundred `CalendarDay` values, and by
/// May most of them describe days that have already happened. That is fine in a
/// local store and not fine in a transfer with a size limit, so this exists —
/// in the engine rather than in the transport, because *how far ahead an answer
/// can depend on the rotation* is a fact about the engine.
public extension ScheduleConfiguration {

    /// A copy holding only the dated overrides inside a window around `date`.
    ///
    /// The defaults are the widest window any answer can depend on: yesterday,
    /// because a time zone west of the schedule's own can still be on it, and
    /// `ScheduleEngine.forwardSearchLimitDays` ahead, because that is exactly
    /// how far the engine will look for the next school day before giving up.
    /// Templates, courses, and the weekday rotation are untouched — they are
    /// small and every one of them can apply on any date.
    func trimmingCalendarDays(
        around date: Date,
        daysBefore: Int = 1,
        daysAfter: Int = ScheduleEngine.forwardSearchLimitDays
    ) -> ScheduleConfiguration {
        let calendar = self.calendar
        let today = YearMonthDay(date: date, calendar: calendar)
        let earliest = today.adding(days: -max(0, daysBefore), in: calendar)
        let latest = today.adding(days: max(0, daysAfter), in: calendar)

        var trimmed = self
        trimmed.calendarDays = calendarDays.filter { $0.date >= earliest && $0.date <= latest }
        return trimmed
    }
}
