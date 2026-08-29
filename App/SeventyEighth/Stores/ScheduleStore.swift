import Foundation
import Observation
import SwiftData
import WidgetKit
import ScheduleEngine

/// The app's single owner of the schedule.
///
/// Views never touch SwiftData directly. They read `engine` and call the
/// mutation methods here, which means there is exactly one place that saves and
/// exactly one place that tells the widget to reload. A schedule edit that does
/// not reach the home screen is the failure mode students notice first.
@MainActor
@Observable
public final class ScheduleStore {

    public private(set) var engine: ScheduleEngine
    public private(set) var lastError: String?
    /// Bumped on every save; views observing it re-render.
    public private(set) var revision: Int = 0

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
        self.engine = ScheduleEngine(configuration: ScheduleConfiguration())
        do {
            try ScheduleConfigurationLoader.seedIfEmpty(in: context)
        } catch {
            lastError = "Could not prepare the schedule store: \(error.localizedDescription)"
        }
        reload()
    }

    public var configuration: ScheduleConfiguration { engine.configuration }
    public var timeZone: TimeZone { configuration.timeZone }
    public var isConfigured: Bool { !configuration.templates.isEmpty }
    public var hasAnyCourses: Bool { !configuration.assignments.isEmpty }

    /// True until the student has looked at the bell times and confirmed them.
    /// The placeholder times in `DefaultBellSchedule` are a guess, and the app
    /// says so rather than quietly being wrong.
    public var needsBellTimeConfirmation: Bool {
        guard let settings = try? ScheduleConfigurationLoader.settings(in: context) else { return false }
        return !settings.bellTimesConfirmed
    }

    public func snapshot(at date: Date = Date()) -> ScheduleSnapshot {
        engine.snapshot(at: date)
    }

    // MARK: - Loading

    public func reload() {
        do {
            engine = ScheduleEngine(configuration: try ScheduleConfigurationLoader.load(from: context))
            revision += 1
        } catch {
            lastError = "Could not read your schedule: \(error.localizedDescription)"
        }
    }

    private func commit() {
        do {
            try context.save()
            reload()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            lastError = "Could not save: \(error.localizedDescription)"
        }
    }

    // MARK: - Bell times

    public func confirmBellTimes() {
        guard let settings = try? ScheduleConfigurationLoader.settingsOrCreate(in: context) else { return }
        settings.bellTimesConfirmed = true
        commit()
    }

    // MARK: - Templates

    @discardableResult
    public func addTemplate(named name: String, copying source: DayTemplate? = nil) -> DayTemplate? {
        let slots = (source?.slots ?? DefaultBellSchedule.regularDay().slots).map {
            PeriodSlot(label: $0.label, start: $0.start, end: $0.end, isInstructional: $0.isInstructional)
        }
        let template = DayTemplate(name: name, slots: slots)

        let stored = StoredDayTemplate(
            id: template.id,
            name: template.name,
            sortIndex: configuration.templates.count
        )
        context.insert(stored)
        for slot in template.slots {
            let storedSlot = StoredPeriodSlot(slot)
            storedSlot.template = stored
            context.insert(storedSlot)
        }
        commit()
        return template
    }

    public func renameTemplate(id: UUID, to name: String) {
        guard let stored = storedTemplate(id) else { return }
        stored.name = name
        commit()
    }

    public func deleteTemplate(id: UUID) {
        guard let stored = storedTemplate(id) else { return }
        context.delete(stored)

        // Anything pointing at it goes too, so the store never holds a dangling
        // reference the engine would silently treat as no school.
        for assignment in storedAssignments() where assignment.dayTemplateID == id {
            context.delete(assignment)
        }
        if let settings = try? ScheduleConfigurationLoader.settingsOrCreate(in: context) {
            settings.weekdayDefaults = settings.weekdayDefaults.filter { $0.value != id }
        }
        for day in storedCalendarDays() where day.dayTemplateID == id {
            day.dayTemplateID = nil
            day.isNoSchool = true
        }
        commit()
    }

    // MARK: - Slots

    public func upsertSlot(
        _ slot: PeriodSlot,
        in templateID: UUID
    ) {
        guard let template = storedTemplate(templateID) else { return }
        if let existing = template.slots.first(where: { $0.id == slot.id }) {
            existing.label = slot.label
            existing.startMinutes = slot.start.minutes
            existing.endMinutes = slot.end.minutes
            existing.isInstructional = slot.isInstructional
        } else {
            let stored = StoredPeriodSlot(slot)
            stored.template = template
            context.insert(stored)
        }
        commit()
    }

    public func deleteSlot(id: UUID, in templateID: UUID) {
        guard let template = storedTemplate(templateID),
              let slot = template.slots.first(where: { $0.id == id })
        else { return }
        context.delete(slot)
        for assignment in storedAssignments() where assignment.periodSlotID == id {
            context.delete(assignment)
        }
        commit()
    }

    // MARK: - Courses

    /// The manual grid's write path. An empty course name clears the cell.
    public func setCourse(
        templateID: UUID,
        slotID: UUID,
        courseName: String,
        room: String,
        teacher: String?,
        colorTag: Int? = nil
    ) {
        let trimmed = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = storedAssignments().first {
            $0.dayTemplateID == templateID && $0.periodSlotID == slotID
        }

        guard !trimmed.isEmpty else {
            if let existing { context.delete(existing) }
            commit()
            return
        }

        // A course keeps one colour everywhere it appears.
        let resolvedColor = colorTag
            ?? colorForExistingCourse(named: trimmed)
            ?? nextAvailableColor()

        if let existing {
            existing.courseName = trimmed
            existing.room = room.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.teacher = teacher?.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.colorTag = resolvedColor
        } else {
            context.insert(StoredCourseAssignment(
                dayTemplateID: templateID,
                periodSlotID: slotID,
                courseName: trimmed,
                room: room.trimmingCharacters(in: .whitespacesAndNewlines),
                teacher: teacher?.trimmingCharacters(in: .whitespacesAndNewlines),
                colorTag: resolvedColor
            ))
        }
        commit()
    }

    private func colorForExistingCourse(named name: String) -> Int? {
        configuration.assignments
            .first { $0.courseName.compare(name, options: .caseInsensitive) == .orderedSame }?
            .colorTag
    }

    private func nextAvailableColor() -> Int {
        let used = Set(configuration.assignments.map(\.colorTag))
        return (0..<64).first { !used.contains($0) } ?? used.count
    }

    // MARK: - Rotation

    public func setWeekdayDefault(weekday: Int, templateID: UUID?) {
        guard let settings = try? ScheduleConfigurationLoader.settingsOrCreate(in: context) else { return }
        if let templateID {
            settings.weekdayDefaults[weekday] = templateID
        } else {
            settings.weekdayDefaults[weekday] = nil
        }
        commit()
    }

    public func setDay(
        _ date: YearMonthDay,
        templateID: UUID?,
        isNoSchool: Bool,
        note: String?,
        droppedSlotIDs: Set<UUID> = []
    ) {
        let key = date.description
        if let existing = storedCalendarDays().first(where: { $0.dateKey == key }) {
            existing.dayTemplateID = templateID
            existing.isNoSchool = isNoSchool
            existing.overrideNote = note
            existing.droppedSlotIDs = Array(droppedSlotIDs)
            existing.isFromSharedRotation = false
        } else {
            context.insert(StoredCalendarDay(
                dateKey: key,
                dayTemplateID: templateID,
                isNoSchool: isNoSchool,
                overrideNote: note,
                droppedSlotIDs: Array(droppedSlotIDs)
            ))
        }
        commit()
    }

    /// Clears a dated override, so the weekday default applies again.
    public func clearDay(_ date: YearMonthDay) {
        let key = date.description
        guard let existing = storedCalendarDays().first(where: { $0.dateKey == key }) else { return }
        context.delete(existing)
        commit()
    }

    /// "Apply to a date range", optionally limited to particular weekdays.
    public func applyTemplate(
        _ templateID: UUID?,
        from start: YearMonthDay,
        through end: YearMonthDay,
        weekdays: Set<Int>? = nil,
        isNoSchool: Bool = false,
        note: String? = nil
    ) {
        let calendar = configuration.calendar
        var cursor = start
        var guardCount = 0

        while cursor <= end && guardCount < 400 {
            guardCount += 1
            let weekday = cursor.weekday(in: calendar)
            if weekdays == nil || weekdays?.contains(weekday) == true {
                let key = cursor.description
                if let existing = storedCalendarDays().first(where: { $0.dateKey == key }) {
                    existing.dayTemplateID = templateID
                    existing.isNoSchool = isNoSchool
                    existing.overrideNote = note
                    existing.isFromSharedRotation = false
                } else {
                    context.insert(StoredCalendarDay(
                        dateKey: key,
                        dayTemplateID: templateID,
                        isNoSchool: isNoSchool,
                        overrideNote: note
                    ))
                }
            }
            cursor = cursor.adding(days: 1, in: calendar)
        }
        commit()
    }

    // MARK: - Import and shared rotation

    /// The only path that writes a schedule the student did not type. Called
    /// from the review screen, after they confirm.
    public func replaceSchedule(with configuration: ScheduleConfiguration) {
        do {
            try ScheduleConfigurationLoader.replaceSchedule(with: configuration, in: context)
            reload()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            lastError = "Could not save the imported schedule: \(error.localizedDescription)"
        }
    }

    @discardableResult
    public func applyRotation(_ file: RotationFile) -> RotationMergeReport? {
        guard let settings = try? ScheduleConfigurationLoader.settingsOrCreate(in: context) else { return nil }
        guard file.version > settings.rotationVersion else { return nil }

        let (merged, report) = RotationMerge.apply(file, to: configuration)
        do {
            try ScheduleConfigurationLoader.replaceSchedule(
                with: merged,
                keepingCalendarDays: false,
                in: context
            )
            let refreshed = try ScheduleConfigurationLoader.settingsOrCreate(in: context)
            refreshed.rotationVersion = file.version
            refreshed.rotationSchoolYear = file.schoolYear
            try context.save()
            reload()
            WidgetCenter.shared.reloadAllTimelines()
            return report
        } catch {
            lastError = "Could not apply the school calendar: \(error.localizedDescription)"
            return nil
        }
    }

    public var rotationVersion: Int {
        (try? ScheduleConfigurationLoader.settings(in: context))?.rotationVersion ?? 0
    }

    public var rotationSchoolYear: String? {
        (try? ScheduleConfigurationLoader.settings(in: context))?.rotationSchoolYear
    }

    // MARK: - Erasing

    /// Settings offers this next to account deletion: the schedule is local, so
    /// erasing it is a local operation and it is honest to say so.
    public func eraseSchedule() {
        do {
            try ScheduleConfigurationLoader.replaceSchedule(
                with: ScheduleConfiguration(),
                keepingCalendarDays: false,
                in: context
            )
            try ScheduleConfigurationLoader.seedIfEmpty(in: context)
            reload()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            lastError = "Could not erase the schedule: \(error.localizedDescription)"
        }
    }

    public func dismissError() { lastError = nil }

    // MARK: - Store access

    private func storedTemplate(_ id: UUID) -> StoredDayTemplate? {
        try? context.fetch(
            FetchDescriptor<StoredDayTemplate>(predicate: #Predicate { $0.id == id })
        ).first
    }

    private func storedAssignments() -> [StoredCourseAssignment] {
        (try? context.fetch(FetchDescriptor<StoredCourseAssignment>())) ?? []
    }

    private func storedCalendarDays() -> [StoredCalendarDay] {
        (try? context.fetch(FetchDescriptor<StoredCalendarDay>())) ?? []
    }
}
