import Foundation
import SwiftData

/// The one SwiftData container, living in the App Group so the widget extension
/// can read it without the app running and without a network call.
public enum ScheduleContainer {

    public static let schema = Schema([
        StoredDayTemplate.self,
        StoredPeriodSlot.self,
        StoredCourseAssignment.self,
        StoredCalendarDay.self,
        StoredScheduleSettings.self
    ])

    /// The shared, on-disk container. Created once per process.
    public static let shared: ModelContainer = {
        do {
            return try ModelContainer(for: schema, configurations: configuration())
        } catch {
            // A container that cannot open is not recoverable at runtime: every
            // screen depends on it. Crashing here surfaces the problem in
            // TestFlight instead of shipping an app that silently shows nothing.
            fatalError("Could not open the schedule store: \(error)")
        }
    }()

    public static func configuration(readOnly: Bool = false) -> ModelConfiguration {
        ModelConfiguration(
            AppIdentifiers.storeFilename,
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: !readOnly,
            groupContainer: .identifier(AppIdentifiers.appGroup),
            cloudKitDatabase: .none
        )
    }

    /// A non-fatal accessor for the widget extension, where a crash means the
    /// tile silently disappears from the home screen. The widget shows a "open
    /// the app" prompt instead.
    public static func attempt() -> ModelContainer? {
        try? ModelContainer(for: schema, configurations: configuration(readOnly: true))
    }

    /// An in-memory container for previews and tests.
    public static func inMemory() -> ModelContainer {
        do {
            return try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
        } catch {
            fatalError("Could not build an in-memory schedule store: \(error)")
        }
    }
}
