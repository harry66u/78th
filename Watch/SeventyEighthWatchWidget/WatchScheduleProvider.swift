import Foundation
import WidgetKit
import ScheduleEngine

/// The watch face's timeline.
///
/// The phone's provider reads SwiftData; this one reads the synced mirror. That
/// is the entire difference between them — everything downstream, the entry
/// dates, the reload policy, and the views, is the same code.
///
/// It never talks to the watch app, never talks to the phone, and never touches
/// the network. A complication on a watch left in a locker with the phone at
/// home still counts down correctly, because the timeline for the day was
/// precomputed from a schedule already on the device.
struct WatchScheduleProvider: TimelineProvider {

    func placeholder(in context: Context) -> ScheduleEntry {
        .preview()
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        if context.isPreview {
            completion(.preview())
            return
        }
        completion(GlanceTimeline.entry(for: ScheduleMirror.engine()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        completion(GlanceTimeline.timeline(for: ScheduleMirror.engine()))
    }
}
