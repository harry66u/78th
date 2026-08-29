import Foundation
import SwiftData
import WidgetKit
import ScheduleEngine

/// The phone's schedule timeline.
///
/// Two rules from the build spec are enforced here: the widget never makes a
/// network call, and it never wakes the app. It reads the shared SwiftData
/// container and hands the engine to `GlanceTimeline`, which is the same code
/// the watch complication uses — only the way the configuration is fetched
/// differs between the two.
struct ScheduleProvider: TimelineProvider {

    func placeholder(in context: Context) -> ScheduleEntry {
        .preview()
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        if context.isPreview {
            completion(.preview())
            return
        }
        completion(GlanceTimeline.entry(for: loadEngine()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        completion(GlanceTimeline.timeline(for: loadEngine()))
    }

    private func loadEngine() -> ScheduleEngine? {
        guard let container = ScheduleContainer.attempt() else { return nil }
        let context = ModelContext(container)
        return ScheduleConfigurationLoader.engine(from: context)
    }
}
