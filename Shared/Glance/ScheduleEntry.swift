import Foundation
import WidgetKit
import ScheduleEngine

/// One rendered moment of the schedule.
///
/// Shared by the iOS widget extension and the watch complication extension. The
/// two read their configuration from different places — a SwiftData store on the
/// phone, a synced mirror on the watch — but from here down they are the same
/// code, which is what keeps the wrist and the home screen from ever showing two
/// different answers.
public struct ScheduleEntry: TimelineEntry {

    public let date: Date
    public let snapshot: ScheduleSnapshot?
    /// False when there is no schedule to read yet, which is the one case where
    /// a glance surface asks the student to go and set one up.
    public let isConfigured: Bool
    public let timeZone: TimeZone

    public init(date: Date, snapshot: ScheduleSnapshot?, isConfigured: Bool, timeZone: TimeZone) {
        self.date = date
        self.snapshot = snapshot
        self.isConfigured = isConfigured
        self.timeZone = timeZone
    }

    public static func unconfigured(at date: Date = Date()) -> ScheduleEntry {
        ScheduleEntry(date: date, snapshot: nil, isConfigured: false, timeZone: .current)
    }

    /// The gallery placeholder, so a widget or complication being picked out of
    /// a list is never an empty rectangle.
    public static func preview() -> ScheduleEntry {
        ScheduleEntry(
            date: PreviewSchedule.midPeriodTwo(),
            snapshot: PreviewSchedule.snapshot(),
            isConfigured: true,
            timeZone: PreviewSchedule.timeZone
        )
    }
}

/// Turns an engine into a `WidgetKit` timeline.
///
/// Both extensions call this and nothing else, so the reload policy, the entry
/// spacing, and the not-configured fallback are decided in one place.
public enum GlanceTimeline {

    /// How far past the last precomputed entry to wait before asking for a
    /// reload, so the next day's timeline is built before it is needed.
    public static let reloadGrace: TimeInterval = 60

    /// Nothing to show yet. Try again in an hour in case the student sets up in
    /// the meantime; the app also reloads timelines directly when they do.
    public static let unconfiguredRetry: TimeInterval = 60 * 60

    public static func entry(for engine: ScheduleEngine?, at now: Date = Date()) -> ScheduleEntry {
        guard let engine, !engine.configuration.isEmpty else {
            return .unconfigured(at: now)
        }
        return ScheduleEntry(
            date: now,
            snapshot: engine.snapshot(at: now),
            isConfigured: true,
            timeZone: engine.configuration.timeZone
        )
    }

    public static func timeline(
        for engine: ScheduleEngine?,
        from now: Date = Date(),
        limit: Int = 120
    ) -> Timeline<ScheduleEntry> {
        guard let engine, !engine.configuration.isEmpty else {
            return Timeline(
                entries: [ScheduleEntry.unconfigured(at: now)],
                policy: .after(now.addingTimeInterval(unconfiguredRetry))
            )
        }

        let timeZone = engine.configuration.timeZone
        let dates = engine.timelineEntryDates(from: now, limit: limit)
        let entries = dates.map { date in
            ScheduleEntry(
                date: date,
                snapshot: engine.snapshot(at: date),
                isConfigured: true,
                timeZone: timeZone
            )
        }

        let reloadAfter = (dates.last ?? now).addingTimeInterval(reloadGrace)
        return Timeline(entries: entries, policy: .after(reloadAfter))
    }
}
