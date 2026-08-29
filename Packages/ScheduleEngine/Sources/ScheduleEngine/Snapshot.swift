import Foundation

/// A period placed on an actual date, with its course resolved.
public struct ResolvedPeriod: Identifiable, Hashable, Sendable {

    public var id: UUID { slot.id }
    public var slot: PeriodSlot
    public var course: CourseAssignment?
    public var date: YearMonthDay
    public var start: Date
    public var end: Date

    public init(slot: PeriodSlot, course: CourseAssignment?, date: YearMonthDay, start: Date, end: Date) {
        self.slot = slot
        self.course = course
        self.date = date
        self.start = start
        self.end = end
    }

    /// What the widget shows large: the course if there is one, otherwise the
    /// slot label ("Lunch", "Mincha").
    public var title: String {
        if let name = course?.courseName, !name.isEmpty { return name }
        return slot.label
    }

    /// Present only when it adds something the title does not already say.
    public var room: String? {
        guard let room = course?.room, !room.isEmpty else { return nil }
        return room
    }

    public var teacher: String? {
        guard let teacher = course?.teacher, !teacher.isEmpty else { return nil }
        return teacher
    }

    /// "Period 3" under the course name. Nil when it would repeat the title.
    public var slotLabel: String? {
        slot.label == title ? nil : slot.label
    }

    public var colorTag: Int { course?.colorTag ?? 0 }
    public var isInstructional: Bool { slot.isInstructional }

    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }
}

/// One date's fully resolved schedule.
public struct SchoolDay: Hashable, Sendable {

    public var date: YearMonthDay
    /// "A Day", "Friday", "Half Day". Nil on a no-school day.
    public var templateName: String?
    public var isNoSchool: Bool
    public var overrideNote: String?
    /// Empty on a no-school day. Sorted by start time, dropped slots removed.
    public var periods: [ResolvedPeriod]

    public init(
        date: YearMonthDay,
        templateName: String?,
        isNoSchool: Bool,
        overrideNote: String?,
        periods: [ResolvedPeriod]
    ) {
        self.date = date
        self.templateName = templateName
        self.isNoSchool = isNoSchool
        self.overrideNote = overrideNote
        self.periods = periods
    }

    public var hasClasses: Bool { !isNoSchool && !periods.isEmpty }
    public var firstPeriod: ResolvedPeriod? { periods.first }
    public var lastPeriod: ResolvedPeriod? { periods.last }
}

/// Where the student is in the day. Every glance surface renders off this.
public enum ScheduleStatus: Hashable, Sendable {

    /// Weekend, holiday, or a date explicitly marked no school.
    case noSchool(reason: String)
    /// School day, but the first period has not started yet.
    case beforeSchool(next: ResolvedPeriod)
    /// Inside a period.
    case inPeriod(current: ResolvedPeriod, next: ResolvedPeriod?)
    /// In a gap between two periods.
    case passing(previous: ResolvedPeriod, next: ResolvedPeriod)
    /// The last period has ended. Carries the next school day's first period.
    case dayComplete(nextDay: ResolvedPeriod?)
}

/// The single value every surface reads: app, widget, and any future watch app.
public struct ScheduleSnapshot: Hashable, Sendable {

    public var now: Date
    public var day: SchoolDay
    public var status: ScheduleStatus

    /// The period happening right now, if any.
    public var current: ResolvedPeriod?
    /// The next period the student has to be somewhere for. May be on a later date.
    public var next: ResolvedPeriod?
    /// Everything left today after `now`, `next` included.
    public var upcoming: [ResolvedPeriod]

    /// What the countdown counts down to: the end of the current period, or the
    /// start of the next one.
    public var countdownTarget: Date?
    /// When the widget's next timeline entry should fire.
    public var nextBoundary: Date?

    public init(
        now: Date,
        day: SchoolDay,
        status: ScheduleStatus,
        current: ResolvedPeriod?,
        next: ResolvedPeriod?,
        upcoming: [ResolvedPeriod],
        countdownTarget: Date?,
        nextBoundary: Date?
    ) {
        self.now = now
        self.day = day
        self.status = status
        self.current = current
        self.next = next
        self.upcoming = upcoming
        self.countdownTarget = countdownTarget
        self.nextBoundary = nextBoundary
    }

    /// Whole seconds to `countdownTarget`, never negative. Nil when nothing is
    /// being counted down to.
    public var secondsRemaining: Int? {
        guard let target = countdownTarget else { return nil }
        return max(0, Int(target.timeIntervalSince(now).rounded(.up)))
    }

    /// Minutes to `countdownTarget`, rounded up so that 30 seconds left reads as
    /// "1 min" rather than "0 min".
    public var minutesRemaining: Int? {
        guard let seconds = secondsRemaining else { return nil }
        return Int((Double(seconds) / 60).rounded(.up))
    }

    /// True while the countdown refers to time left in class rather than time
    /// until the next class starts.
    public var isCountingDownCurrentPeriod: Bool {
        if case .inPeriod = status { return true }
        return false
    }
}
