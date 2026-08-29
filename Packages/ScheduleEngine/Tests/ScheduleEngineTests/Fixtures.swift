import Foundation
import ScheduleEngine

/// A small, fully deterministic school used by every test.
///
/// Deliberately not `DefaultBellSchedule`: those times are placeholders that
/// will change when the real Ramaz bell schedule is confirmed, and the engine's
/// tests must not move when they do.
enum Fixture {

    static let timeZone = TimeZone(identifier: "America/New_York")!

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    struct School {
        var configuration: ScheduleConfiguration
        var engine: ScheduleEngine
        var aDay: DayTemplate
        var friday: DayTemplate
        var halfDay: DayTemplate

        func slot(_ label: String, in template: DayTemplate) -> PeriodSlot {
            template.slots.first { $0.label == label }!
        }

        /// The same school with dated overrides layered on. Reusing this
        /// school's templates keeps the override's template identifiers valid.
        func overridden(by calendarDays: [CalendarDay]) -> ScheduleEngine {
            var overridden = configuration
            overridden.calendarDays = calendarDays
            return ScheduleEngine(configuration: overridden)
        }
    }

    /// A Day:    P1 08:00-08:50, P2 09:00-09:50, Lunch 12:00-12:40, P3 13:00-13:50
    /// Friday:   P1 08:00-08:40, P2 08:45-09:25
    /// Half Day: P1 08:00-08:30, P2 08:35-09:05
    ///
    /// Monday through Thursday are A Days, Friday is a Friday, the weekend is
    /// unmapped and therefore no school.
    static func school() -> School {
        let aDay = DayTemplate(name: "A Day", slots: [
            PeriodSlot(label: "Period 1", start: TimeOfDay(hour: 8, minute: 0), end: TimeOfDay(hour: 8, minute: 50)),
            PeriodSlot(label: "Period 2", start: TimeOfDay(hour: 9, minute: 0), end: TimeOfDay(hour: 9, minute: 50)),
            PeriodSlot(label: "Lunch", start: TimeOfDay(hour: 12, minute: 0), end: TimeOfDay(hour: 12, minute: 40), isInstructional: false),
            PeriodSlot(label: "Period 3", start: TimeOfDay(hour: 13, minute: 0), end: TimeOfDay(hour: 13, minute: 50))
        ])

        let friday = DayTemplate(name: "Friday", slots: [
            PeriodSlot(label: "Period 1", start: TimeOfDay(hour: 8, minute: 0), end: TimeOfDay(hour: 8, minute: 40)),
            PeriodSlot(label: "Period 2", start: TimeOfDay(hour: 8, minute: 45), end: TimeOfDay(hour: 9, minute: 25))
        ])

        let halfDay = DayTemplate(name: "Half Day", slots: [
            PeriodSlot(label: "Period 1", start: TimeOfDay(hour: 8, minute: 0), end: TimeOfDay(hour: 8, minute: 30)),
            PeriodSlot(label: "Period 2", start: TimeOfDay(hour: 8, minute: 35), end: TimeOfDay(hour: 9, minute: 5))
        ])

        func slotID(_ label: String, _ template: DayTemplate) -> UUID {
            template.slots.first { $0.label == label }!.id
        }

        let assignments = [
            CourseAssignment(
                dayTemplateID: aDay.id, periodSlotID: slotID("Period 1", aDay),
                courseName: "Talmud", room: "305", teacher: "Rabbi Cohen", colorTag: 1
            ),
            CourseAssignment(
                dayTemplateID: aDay.id, periodSlotID: slotID("Period 2", aDay),
                courseName: "AP Physics C", room: "402", teacher: "Mr. Klotz", colorTag: 2
            ),
            CourseAssignment(
                dayTemplateID: aDay.id, periodSlotID: slotID("Period 3", aDay),
                courseName: "BC Calculus", room: "511", teacher: "Dr. Nironi", colorTag: 3
            ),
            CourseAssignment(
                dayTemplateID: friday.id, periodSlotID: slotID("Period 1", friday),
                courseName: "English", room: "208", teacher: "Mr. Prehn", colorTag: 4
            ),
            CourseAssignment(
                dayTemplateID: friday.id, periodSlotID: slotID("Period 2", friday),
                courseName: "AP Micro", room: "210", teacher: "Dr. Lerer", colorTag: 5
            ),
            CourseAssignment(
                dayTemplateID: halfDay.id, periodSlotID: slotID("Period 1", halfDay),
                courseName: "Talmud", room: "305", teacher: "Rabbi Cohen", colorTag: 1
            )
        ]

        let configuration = ScheduleConfiguration(
            templates: [aDay, friday, halfDay],
            assignments: assignments,
            calendarDays: [],
            weekdayDefaults: [2: aDay.id, 3: aDay.id, 4: aDay.id, 5: aDay.id, 6: friday.id],
            timeZoneIdentifier: timeZone.identifier
        )

        return School(
            configuration: configuration,
            engine: ScheduleEngine(configuration: configuration),
            aDay: aDay,
            friday: friday,
            halfDay: halfDay
        )
    }

    /// `Fixture.at("2026-09-08", "09:30")` in New York.
    static func at(_ day: String, _ time: String) -> Date {
        let ymd = YearMonthDay(iso8601: day)!
        let clock = TimeOfDay(time)!
        return ymd.date(at: clock, in: calendar)
    }

    static func ymd(_ day: String) -> YearMonthDay {
        YearMonthDay(iso8601: day)!
    }
}

// Calendar reference for the dates used across the suite:
//   2026-09-07 Monday      2026-09-08 Tuesday    2026-09-09 Wednesday
//   2026-09-10 Thursday    2026-09-11 Friday     2026-09-12 Saturday
//   2026-09-13 Sunday      2026-09-14 Monday
