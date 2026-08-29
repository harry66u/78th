import Foundation
import ScheduleEngine

/// A fixed schedule used by SwiftUI previews and by the widget's placeholder,
/// so a gallery preview never shows an empty tile.
public enum PreviewSchedule {

    public static let timeZone = TimeZone(identifier: "America/New_York") ?? .current

    public static func configuration() -> ScheduleConfiguration {
        let template = DayTemplate(name: "A Day", slots: [
            PeriodSlot(label: "Period 1", start: TimeOfDay(hour: 8, minute: 15), end: TimeOfDay(hour: 9, minute: 0)),
            PeriodSlot(label: "Period 2", start: TimeOfDay(hour: 9, minute: 5), end: TimeOfDay(hour: 9, minute: 50)),
            PeriodSlot(label: "Period 3", start: TimeOfDay(hour: 9, minute: 55), end: TimeOfDay(hour: 10, minute: 40)),
            PeriodSlot(label: "Lunch", start: TimeOfDay(hour: 12, minute: 30), end: TimeOfDay(hour: 13, minute: 10), isInstructional: false),
            PeriodSlot(label: "Period 6", start: TimeOfDay(hour: 13, minute: 10), end: TimeOfDay(hour: 13, minute: 55))
        ])

        func slotID(_ label: String) -> UUID {
            template.slots.first { $0.label == label }?.id ?? UUID()
        }

        let assignments = [
            CourseAssignment(dayTemplateID: template.id, periodSlotID: slotID("Period 1"), courseName: "Talmud", room: "305", teacher: "Rabbi Cohen", colorTag: 0),
            CourseAssignment(dayTemplateID: template.id, periodSlotID: slotID("Period 2"), courseName: "AP Physics C", room: "402", teacher: "Mr. Klotz", colorTag: 1),
            CourseAssignment(dayTemplateID: template.id, periodSlotID: slotID("Period 3"), courseName: "BC Calculus", room: "511", teacher: "Dr. Nironi", colorTag: 2),
            CourseAssignment(dayTemplateID: template.id, periodSlotID: slotID("Period 6"), courseName: "AP Micro", room: "210", teacher: "Dr. Lerer", colorTag: 3)
        ]

        return ScheduleConfiguration(
            templates: [template],
            assignments: assignments,
            weekdayDefaults: [2: template.id, 3: template.id, 4: template.id, 5: template.id, 6: template.id],
            timeZoneIdentifier: timeZone.identifier
        )
    }

    public static func engine() -> ScheduleEngine {
        ScheduleEngine(configuration: configuration())
    }

    /// Mid Period 2, with 23 minutes left: the state the widget spends most of
    /// its visible life in.
    public static func snapshot() -> ScheduleSnapshot {
        engine().snapshot(at: midPeriodTwo())
    }

    public static func midPeriodTwo() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 8
        components.hour = 9
        components.minute = 27
        return calendar.date(from: components) ?? Date()
    }
}
