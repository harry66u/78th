import Foundation
import SwiftData
import ScheduleEngine

/// SwiftData mirrors of the engine's value types.
///
/// The engine deliberately knows nothing about persistence, so these classes
/// exist only to store and to convert. Nothing in here makes a scheduling
/// decision; that all happens in `ScheduleEngine`.
///
/// None of this is ever uploaded. The class schedule stays on the device.

@Model
public final class StoredDayTemplate {

    @Attribute(.unique) public var id: UUID
    public var name: String
    public var sortIndex: Int

    @Relationship(deleteRule: .cascade, inverse: \StoredPeriodSlot.template)
    public var slots: [StoredPeriodSlot]

    public init(id: UUID = UUID(), name: String, sortIndex: Int = 0, slots: [StoredPeriodSlot] = []) {
        self.id = id
        self.name = name
        self.sortIndex = sortIndex
        self.slots = slots
    }

    public var engineValue: DayTemplate {
        DayTemplate(id: id, name: name, slots: slots.map(\.engineValue))
    }
}

@Model
public final class StoredPeriodSlot {

    @Attribute(.unique) public var id: UUID
    public var label: String
    /// Minutes from midnight.
    public var startMinutes: Int
    public var endMinutes: Int
    public var isInstructional: Bool
    public var template: StoredDayTemplate?

    public init(
        id: UUID = UUID(),
        label: String,
        startMinutes: Int,
        endMinutes: Int,
        isInstructional: Bool = true
    ) {
        self.id = id
        self.label = label
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.isInstructional = isInstructional
    }

    public convenience init(_ slot: PeriodSlot) {
        self.init(
            id: slot.id,
            label: slot.label,
            startMinutes: slot.start.minutes,
            endMinutes: slot.end.minutes,
            isInstructional: slot.isInstructional
        )
    }

    public var engineValue: PeriodSlot {
        PeriodSlot(
            id: id,
            label: label,
            start: TimeOfDay(minutes: startMinutes),
            end: TimeOfDay(minutes: endMinutes),
            isInstructional: isInstructional
        )
    }
}

@Model
public final class StoredCourseAssignment {

    @Attribute(.unique) public var id: UUID
    public var dayTemplateID: UUID
    public var periodSlotID: UUID
    public var courseName: String
    public var room: String
    public var teacher: String?
    public var colorTag: Int

    public init(
        id: UUID = UUID(),
        dayTemplateID: UUID,
        periodSlotID: UUID,
        courseName: String,
        room: String = "",
        teacher: String? = nil,
        colorTag: Int = 0
    ) {
        self.id = id
        self.dayTemplateID = dayTemplateID
        self.periodSlotID = periodSlotID
        self.courseName = courseName
        self.room = room
        self.teacher = teacher
        self.colorTag = colorTag
    }

    public convenience init(_ assignment: CourseAssignment) {
        self.init(
            id: assignment.id,
            dayTemplateID: assignment.dayTemplateID,
            periodSlotID: assignment.periodSlotID,
            courseName: assignment.courseName,
            room: assignment.room,
            teacher: assignment.teacher,
            colorTag: assignment.colorTag
        )
    }

    public var engineValue: CourseAssignment {
        CourseAssignment(
            id: id,
            dayTemplateID: dayTemplateID,
            periodSlotID: periodSlotID,
            courseName: courseName,
            room: room,
            teacher: teacher,
            colorTag: colorTag
        )
    }
}

@Model
public final class StoredCalendarDay {

    /// "2026-09-08". Stored as a string so it sorts, queries, and stays free of
    /// time-zone ambiguity.
    @Attribute(.unique) public var dateKey: String
    public var dayTemplateID: UUID?
    public var isNoSchool: Bool
    public var overrideNote: String?
    public var droppedSlotIDs: [UUID]
    /// True when this entry came from the shared rotation file rather than from
    /// the student, so a later push can replace it without stepping on a manual
    /// edit.
    public var isFromSharedRotation: Bool

    public init(
        dateKey: String,
        dayTemplateID: UUID? = nil,
        isNoSchool: Bool = false,
        overrideNote: String? = nil,
        droppedSlotIDs: [UUID] = [],
        isFromSharedRotation: Bool = false
    ) {
        self.dateKey = dateKey
        self.dayTemplateID = dayTemplateID
        self.isNoSchool = isNoSchool
        self.overrideNote = overrideNote
        self.droppedSlotIDs = droppedSlotIDs
        self.isFromSharedRotation = isFromSharedRotation
    }

    public convenience init(_ day: CalendarDay, isFromSharedRotation: Bool = false) {
        self.init(
            dateKey: day.date.description,
            dayTemplateID: day.dayTemplateID,
            isNoSchool: day.isNoSchool,
            overrideNote: day.overrideNote,
            droppedSlotIDs: Array(day.droppedSlotIDs),
            isFromSharedRotation: isFromSharedRotation
        )
    }

    public var engineValue: CalendarDay? {
        guard let date = YearMonthDay(iso8601: dateKey) else { return nil }
        return CalendarDay(
            date: date,
            dayTemplateID: dayTemplateID,
            isNoSchool: isNoSchool,
            overrideNote: overrideNote,
            droppedSlotIDs: Set(droppedSlotIDs)
        )
    }
}

/// Single-row settings. Kept in SwiftData rather than defaults so the widget
/// reads one store and not two.
@Model
public final class StoredScheduleSettings {

    @Attribute(.unique) public var id: String
    /// Weekday number (1 = Sunday ... 7 = Saturday) to template id.
    public var weekdayDefaults: [Int: UUID]
    public var timeZoneIdentifier: String
    /// Which version of the placeholder bell times this install was seeded with.
    public var seededBellScheduleVersion: Int
    /// The student has looked at the bell times and said they are right.
    public var bellTimesConfirmed: Bool
    /// Last applied shared rotation version.
    public var rotationVersion: Int
    public var rotationSchoolYear: String?

    public static let singletonID = "settings"

    public init(
        id: String = StoredScheduleSettings.singletonID,
        weekdayDefaults: [Int: UUID] = [:],
        timeZoneIdentifier: String = "America/New_York",
        seededBellScheduleVersion: Int = 0,
        bellTimesConfirmed: Bool = false,
        rotationVersion: Int = 0,
        rotationSchoolYear: String? = nil
    ) {
        self.id = id
        self.weekdayDefaults = weekdayDefaults
        self.timeZoneIdentifier = timeZoneIdentifier
        self.seededBellScheduleVersion = seededBellScheduleVersion
        self.bellTimesConfirmed = bellTimesConfirmed
        self.rotationVersion = rotationVersion
        self.rotationSchoolYear = rotationSchoolYear
    }
}
