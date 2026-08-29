import Foundation
import SwiftData
import ScheduleEngine

/// Builds an in-memory store seeded with a believable week, so every preview in
/// the app renders something real rather than an empty state.
@MainActor
enum PreviewSupport {

    static func context() -> ModelContext {
        let container = ScheduleContainer.inMemory()
        let context = ModelContext(container)
        try? ScheduleConfigurationLoader.replaceSchedule(
            with: PreviewSchedule.configuration(),
            keepingCalendarDays: false,
            in: context
        )
        return context
    }

    static func store() -> ScheduleStore {
        ScheduleStore(context: context())
    }

    static func social() -> SocialStore {
        SocialStore(backend: InMemorySocialBackend.populated())
    }
}
