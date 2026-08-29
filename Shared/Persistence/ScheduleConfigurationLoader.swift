import Foundation
import SwiftData
import ScheduleEngine

/// Reads the SwiftData store into the engine's plain value types, and writes
/// them back.
///
/// This is the only seam between persistence and the engine. Both the app and
/// the widget go through it, which is what keeps them from ever disagreeing
/// about what period it is.
public enum ScheduleConfigurationLoader {

    // MARK: - Reading

    public static func load(from context: ModelContext) throws -> ScheduleConfiguration {
        let templates = try context.fetch(
            FetchDescriptor<StoredDayTemplate>(sortBy: [SortDescriptor(\.sortIndex)])
        )
        let assignments = try context.fetch(FetchDescriptor<StoredCourseAssignment>())
        let calendarDays = try context.fetch(FetchDescriptor<StoredCalendarDay>())
        let settings = try settings(in: context)

        return ScheduleConfiguration(
            templates: templates.map(\.engineValue),
            assignments: assignments.map(\.engineValue),
            calendarDays: calendarDays.compactMap(\.engineValue),
            weekdayDefaults: settings?.weekdayDefaults ?? [:],
            timeZoneIdentifier: settings?.timeZoneIdentifier ?? "America/New_York"
        )
    }

    /// Best-effort load for the widget, where throwing would mean a blank tile
    /// with no explanation.
    public static func loadOrEmpty(from context: ModelContext) -> ScheduleConfiguration {
        (try? load(from: context)) ?? ScheduleConfiguration()
    }

    public static func settings(in context: ModelContext) throws -> StoredScheduleSettings? {
        let id = StoredScheduleSettings.singletonID
        var descriptor = FetchDescriptor<StoredScheduleSettings>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @discardableResult
    public static func settingsOrCreate(in context: ModelContext) throws -> StoredScheduleSettings {
        if let existing = try settings(in: context) { return existing }
        let created = StoredScheduleSettings()
        context.insert(created)
        return created
    }

    // MARK: - Writing

    /// Replaces the stored schedule wholesale.
    ///
    /// Used by the import review screen, which is the only place a student
    /// confirms a schedule they did not type by hand. Course assignments and
    /// templates are replaced together so the store never holds an assignment
    /// pointing at a slot that no longer exists.
    ///
    /// Dated overrides are preserved by default: a student's marked no-school
    /// days survive a reimport of their courses.
    public static func replaceSchedule(
        with configuration: ScheduleConfiguration,
        keepingCalendarDays: Bool = true,
        in context: ModelContext
    ) throws {
        for template in try context.fetch(FetchDescriptor<StoredDayTemplate>()) {
            context.delete(template)
        }
        for assignment in try context.fetch(FetchDescriptor<StoredCourseAssignment>()) {
            context.delete(assignment)
        }
        if !keepingCalendarDays {
            for day in try context.fetch(FetchDescriptor<StoredCalendarDay>()) {
                context.delete(day)
            }
        }

        for (index, template) in configuration.templates.enumerated() {
            let stored = StoredDayTemplate(id: template.id, name: template.name, sortIndex: index)
            context.insert(stored)
            for slot in template.slots {
                let storedSlot = StoredPeriodSlot(slot)
                storedSlot.template = stored
                context.insert(storedSlot)
            }
        }

        for assignment in configuration.assignments {
            context.insert(StoredCourseAssignment(assignment))
        }

        if !keepingCalendarDays {
            for day in configuration.calendarDays {
                context.insert(StoredCalendarDay(day))
            }
        }

        let settings = try settingsOrCreate(in: context)
        settings.weekdayDefaults = configuration.weekdayDefaults
        settings.timeZoneIdentifier = configuration.timeZoneIdentifier

        try context.save()
    }

    /// Writes the dated overrides from a merged rotation, leaving templates and
    /// courses alone.
    public static func applyCalendarDays(
        _ days: [CalendarDay],
        fromSharedRotation: Bool,
        in context: ModelContext
    ) throws {
        let existing = try context.fetch(FetchDescriptor<StoredCalendarDay>())
        var byKey = Dictionary(existing.map { ($0.dateKey, $0) }, uniquingKeysWith: { first, _ in first })

        for day in days {
            let key = day.date.description
            if let stored = byKey[key] {
                stored.dayTemplateID = day.dayTemplateID
                stored.isNoSchool = day.isNoSchool
                stored.overrideNote = day.overrideNote
                stored.droppedSlotIDs = Array(day.droppedSlotIDs)
                stored.isFromSharedRotation = fromSharedRotation
            } else {
                let stored = StoredCalendarDay(day, isFromSharedRotation: fromSharedRotation)
                context.insert(stored)
                byKey[key] = stored
            }
        }

        try context.save()
    }

    /// Installs the placeholder bell schedule on a fresh install.
    ///
    /// Idempotent: a store that already has templates is left alone, so this can
    /// be called on every launch.
    @discardableResult
    public static func seedIfEmpty(in context: ModelContext) throws -> Bool {
        let existing = try context.fetchCount(FetchDescriptor<StoredDayTemplate>())
        guard existing == 0 else { return false }

        let seed = DefaultBellSchedule.seedConfiguration()
        try replaceSchedule(with: seed, keepingCalendarDays: false, in: context)

        let settings = try settingsOrCreate(in: context)
        settings.seededBellScheduleVersion = DefaultBellSchedule.version
        settings.bellTimesConfirmed = DefaultBellSchedule.timesAreConfirmed
        try context.save()
        return true
    }

    // MARK: - Convenience

    /// A ready-to-use engine from a context. The widget calls this and nothing
    /// else.
    public static func engine(from context: ModelContext) -> ScheduleEngine {
        ScheduleEngine(configuration: loadOrEmpty(from: context))
    }
}
