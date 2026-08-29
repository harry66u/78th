import Foundation

/// Preloaded bell schedules.
///
/// **These times are placeholders.** The build spec flags confirming the real
/// Ramaz bell times as an open question, and the app is worthless if it shows
/// the wrong minute. Everything the student sees comes from this one file, so
/// correcting it is a single edit: replace the times below, bump
/// `DefaultBellSchedule.version`, and the onboarding seed picks them up.
///
/// Students can edit any of this in Settings, so a wrong default is recoverable.
/// A wrong default that nobody notices is not, which is why the Today screen
/// shows an "unconfirmed bell times" banner until the student confirms them.
public enum DefaultBellSchedule {

    /// Bumped whenever the placeholder times change, so an existing install can
    /// tell the student their schedule may be stale.
    public static let version = 1

    /// Set to `true` once the real bell times replace the placeholders below.
    /// The Today screen and the setup flow read this to decide whether to warn.
    public static let timesAreConfirmed = false

    public enum TemplateName {
        public static let regular = "Regular Day"
        public static let friday = "Friday"
        public static let halfDay = "Half Day"
        public static let fastDay = "Fast Day"
    }

    // MARK: - Templates

    public static func regularDay() -> DayTemplate {
        DayTemplate(name: TemplateName.regular, slots: [
            slot("Period 1", "08:15", "09:00"),
            slot("Period 2", "09:05", "09:50"),
            slot("Period 3", "09:55", "10:40"),
            slot("Break", "10:40", "10:55", instructional: false),
            slot("Period 4", "10:55", "11:40"),
            slot("Period 5", "11:45", "12:30"),
            slot("Lunch", "12:30", "13:10", instructional: false),
            slot("Period 6", "13:10", "13:55"),
            slot("Mincha", "13:55", "14:15", instructional: false),
            slot("Period 7", "14:20", "15:05"),
            slot("Period 8", "15:10", "15:55")
        ])
    }

    public static func fridayDay() -> DayTemplate {
        DayTemplate(name: TemplateName.friday, slots: [
            slot("Period 1", "08:15", "08:55"),
            slot("Period 2", "09:00", "09:40"),
            slot("Period 3", "09:45", "10:25"),
            slot("Break", "10:25", "10:35", instructional: false),
            slot("Period 4", "10:35", "11:15"),
            slot("Period 5", "11:20", "12:00"),
            slot("Period 6", "12:05", "12:45")
        ])
    }

    public static func halfDay() -> DayTemplate {
        DayTemplate(name: TemplateName.halfDay, slots: [
            slot("Period 1", "08:15", "08:50"),
            slot("Period 2", "08:55", "09:30"),
            slot("Period 3", "09:35", "10:10"),
            slot("Period 4", "10:15", "10:50"),
            slot("Period 5", "10:55", "11:30")
        ])
    }

    public static func fastDay() -> DayTemplate {
        DayTemplate(name: TemplateName.fastDay, slots: [
            slot("Period 1", "08:15", "08:55"),
            slot("Period 2", "09:00", "09:40"),
            slot("Period 3", "09:45", "10:25"),
            slot("Period 4", "10:30", "11:10"),
            slot("Period 5", "11:15", "11:55"),
            slot("Period 6", "12:00", "12:40"),
            slot("Mincha", "12:45", "13:10", instructional: false),
            slot("Period 7", "13:15", "13:55")
        ])
    }

    public static func allTemplates() -> [DayTemplate] {
        [regularDay(), fridayDay(), halfDay(), fastDay()]
    }

    // MARK: - Seed configuration

    /// A first-run configuration: default bell times, Monday to Friday mapped,
    /// and no courses yet.
    public static func seedConfiguration() -> ScheduleConfiguration {
        let templates = allTemplates()
        guard let regular = templates.first(where: { $0.name == TemplateName.regular }),
              let friday = templates.first(where: { $0.name == TemplateName.friday })
        else {
            return ScheduleConfiguration(templates: templates)
        }

        // 1 = Sunday ... 7 = Saturday. Sunday and Saturday are left unmapped,
        // which the engine reads as no school.
        let weekdayDefaults: [Int: UUID] = [
            2: regular.id,
            3: regular.id,
            4: regular.id,
            5: regular.id,
            6: friday.id
        ]

        return ScheduleConfiguration(
            templates: templates,
            assignments: [],
            calendarDays: [],
            weekdayDefaults: weekdayDefaults
        )
    }

    /// Builds a lettered rotation ("A Day" ... "E Day") that all share one set of
    /// bell times. Most schools with a letter rotation vary the courses, not the
    /// bells, so this is usually the shape a student wants.
    public static func rotationTemplates(
        letters: [String] = ["A", "B", "C", "D", "E"],
        basedOn template: DayTemplate
    ) -> [DayTemplate] {
        letters.map { letter in
            DayTemplate(
                name: "\(letter) Day",
                slots: template.slots.map {
                    PeriodSlot(
                        label: $0.label,
                        start: $0.start,
                        end: $0.end,
                        isInstructional: $0.isInstructional
                    )
                }
            )
        }
    }

    // MARK: - Helpers

    private static func slot(
        _ label: String,
        _ start: String,
        _ end: String,
        instructional: Bool = true
    ) -> PeriodSlot {
        PeriodSlot(
            label: label,
            start: TimeOfDay(start) ?? TimeOfDay(minutes: 0),
            end: TimeOfDay(end) ?? TimeOfDay(minutes: 0),
            isInstructional: instructional
        )
    }
}
