import Foundation

// MARK: - Bell schedule

/// One slot in a bell schedule: a labelled span of the day that repeats on every
/// date the owning `DayTemplate` is assigned to.
public struct PeriodSlot: Identifiable, Hashable, Codable, Sendable {

    public var id: UUID
    /// "Period 3", "Lunch", "Mincha".
    public var label: String
    public var start: TimeOfDay
    public var end: TimeOfDay
    /// Instructional slots are the ones that mute ping notifications, and the
    /// only ones a course can be assigned to.
    public var isInstructional: Bool

    public init(
        id: UUID = UUID(),
        label: String,
        start: TimeOfDay,
        end: TimeOfDay,
        isInstructional: Bool = true
    ) {
        self.id = id
        self.label = label
        self.start = start
        self.end = end
        self.isInstructional = isInstructional
    }

    public var durationMinutes: Int { max(0, end.minutes - start.minutes) }
}

/// A named bell schedule: "A Day", "Friday", "Fast Day", "Half Day".
public struct DayTemplate: Identifiable, Hashable, Codable, Sendable {

    public var id: UUID
    public var name: String
    /// Always sorted by start time.
    public private(set) var slots: [PeriodSlot]

    public init(id: UUID = UUID(), name: String, slots: [PeriodSlot]) {
        self.id = id
        self.name = name
        self.slots = slots.sorted { ($0.start, $0.end.minutes) < ($1.start, $1.end.minutes) }
    }

    public mutating func setSlots(_ slots: [PeriodSlot]) {
        self.slots = slots.sorted { ($0.start, $0.end.minutes) < ($1.start, $1.end.minutes) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, slots
    }

    /// Decoding routes through the memberwise initialiser so that decoded slots
    /// are sorted exactly like constructed ones.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let slots = try container.decode([PeriodSlot].self, forKey: .slots)
        self.init(id: id, name: name, slots: slots)
    }
}

/// The course a student sits in for one slot of one day template.
public struct CourseAssignment: Identifiable, Hashable, Codable, Sendable {

    public var id: UUID
    public var dayTemplateID: UUID
    public var periodSlotID: UUID
    public var courseName: String
    public var room: String
    public var teacher: String?
    /// Index into `CourseColor.palette`, kept as a plain integer so it survives
    /// SwiftData, JSON, and the widget without importing SwiftUI.
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
}

/// A single dated entry in the rotation. Entries are sparse: a date with no
/// entry falls back to `ScheduleConfiguration.weekdayDefaults`.
public struct CalendarDay: Hashable, Codable, Sendable {

    public var date: YearMonthDay
    /// Which template applies. Ignored when `isNoSchool` is true.
    public var dayTemplateID: UUID?
    public var isNoSchool: Bool
    /// "Assembly, periods 5 and 6 dropped". Shown verbatim on Today and in the
    /// widget's medium size.
    public var overrideNote: String?
    /// Slots removed from this date only. This is what makes an override note
    /// actually true rather than decorative.
    public var droppedSlotIDs: Set<UUID>

    public init(
        date: YearMonthDay,
        dayTemplateID: UUID? = nil,
        isNoSchool: Bool = false,
        overrideNote: String? = nil,
        droppedSlotIDs: Set<UUID> = []
    ) {
        self.date = date
        self.dayTemplateID = dayTemplateID
        self.isNoSchool = isNoSchool
        self.overrideNote = overrideNote
        self.droppedSlotIDs = droppedSlotIDs
    }
}

// MARK: - Configuration

/// Everything the engine needs. This is the entire input surface: given a
/// configuration and an instant, the engine is a pure function.
public struct ScheduleConfiguration: Hashable, Codable, Sendable {

    public var templates: [DayTemplate]
    public var assignments: [CourseAssignment]
    /// Sparse dated overrides, highest priority.
    public var calendarDays: [CalendarDay]
    /// Fallback rotation by weekday (1 = Sunday ... 7 = Saturday). A weekday with
    /// no entry is a no-school day.
    public var weekdayDefaults: [Int: UUID]
    public var timeZoneIdentifier: String

    public init(
        templates: [DayTemplate] = [],
        assignments: [CourseAssignment] = [],
        calendarDays: [CalendarDay] = [],
        weekdayDefaults: [Int: UUID] = [:],
        timeZoneIdentifier: String = "America/New_York"
    ) {
        self.templates = templates
        self.assignments = assignments
        self.calendarDays = calendarDays
        self.weekdayDefaults = weekdayDefaults
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public var isEmpty: Bool { templates.isEmpty }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(identifier: "America/New_York") ?? .gmt
    }

    public var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
