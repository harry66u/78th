import Foundation
import SwiftData
import WidgetKit
import ScheduleEngine

/// One rendered moment of the schedule.
struct ScheduleEntry: TimelineEntry {
    let date: Date
    let snapshot: ScheduleSnapshot?
    /// False when the shared store has no schedule in it yet, which is the one
    /// case where the widget asks the student to open the app.
    let isConfigured: Bool
    let timeZone: TimeZone

    static func unconfigured(at date: Date = Date()) -> ScheduleEntry {
        ScheduleEntry(date: date, snapshot: nil, isConfigured: false, timeZone: .current)
    }
}

/// Builds the whole day's timeline in one pass.
///
/// Two rules from the build spec are enforced here: the widget never makes a
/// network call, and it never wakes the app. It reads the shared SwiftData
/// container and precomputes an entry for every moment the display changes.
struct ScheduleProvider: TimelineProvider {

    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(
            date: Date(),
            snapshot: PreviewSchedule.snapshot(),
            isConfigured: true,
            timeZone: PreviewSchedule.timeZone
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        guard let engine = loadEngine(), !engine.configuration.isEmpty else {
            // Nothing to show. Try again in an hour in case the student sets up
            // in the meantime; opening the app also reloads timelines directly.
            completion(Timeline(
                entries: [ScheduleEntry.unconfigured()],
                policy: .after(Date().addingTimeInterval(60 * 60))
            ))
            return
        }

        let now = Date()
        let timeZone = engine.configuration.timeZone
        let dates = engine.timelineEntryDates(from: now, limit: 120)
        let entries = dates.map { date in
            ScheduleEntry(
                date: date,
                snapshot: engine.snapshot(at: date),
                isConfigured: true,
                timeZone: timeZone
            )
        }

        // Reload shortly after the last precomputed entry so the next day's
        // timeline is built before it is needed.
        let reloadAfter = (dates.last ?? now).addingTimeInterval(60)
        completion(Timeline(entries: entries, policy: .after(reloadAfter)))
    }

    private func currentEntry() -> ScheduleEntry {
        guard let engine = loadEngine(), !engine.configuration.isEmpty else {
            return .unconfigured()
        }
        let now = Date()
        return ScheduleEntry(
            date: now,
            snapshot: engine.snapshot(at: now),
            isConfigured: true,
            timeZone: engine.configuration.timeZone
        )
    }

    private func loadEngine() -> ScheduleEngine? {
        guard let container = ScheduleContainer.attempt() else { return nil }
        let context = ModelContext(container)
        return ScheduleConfigurationLoader.engine(from: context)
    }
}
