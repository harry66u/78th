import Foundation

/// The pure schedule engine.
///
/// Architectural rule from the build spec: this type has no network dependency,
/// no persistence dependency, and no UI dependency. Given a configuration and an
/// instant it returns the current period, the next period, and the time
/// remaining. The app, the widget, and any future watch app all call this.
public struct ScheduleEngine: Sendable {

    public let configuration: ScheduleConfiguration

    private let calendar: Calendar
    private let templatesByID: [UUID: DayTemplate]
    private let calendarDaysByDate: [YearMonthDay: CalendarDay]
    private let assignmentsByKey: [AssignmentKey: CourseAssignment]

    private struct AssignmentKey: Hashable {
        let dayTemplateID: UUID
        let periodSlotID: UUID
    }

    /// How far ahead the engine will look for the next school day before giving
    /// up. Covers summer-length gaps in the rotation.
    public static let forwardSearchLimitDays = 120

    public init(configuration: ScheduleConfiguration) {
        self.configuration = configuration
        self.calendar = configuration.calendar
        self.templatesByID = Dictionary(
            configuration.templates.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.calendarDaysByDate = Dictionary(
            configuration.calendarDays.map { ($0.date, $0) },
            uniquingKeysWith: { _, last in last }
        )
        self.assignmentsByKey = Dictionary(
            configuration.assignments.map {
                (AssignmentKey(dayTemplateID: $0.dayTemplateID, periodSlotID: $0.periodSlotID), $0)
            },
            uniquingKeysWith: { _, last in last }
        )
    }

    // MARK: - Days

    /// Resolves one date into its periods. Priority: an explicit `CalendarDay`
    /// entry, then the weekday fallback, then no school.
    public func schoolDay(for date: YearMonthDay) -> SchoolDay {
        let override = calendarDaysByDate[date]

        if override?.isNoSchool == true {
            return noSchoolDay(date, note: override?.overrideNote)
        }

        let templateID = override?.dayTemplateID ?? configuration.weekdayDefaults[date.weekday(in: calendar)]
        guard let templateID, let template = templatesByID[templateID] else {
            return noSchoolDay(date, note: override?.overrideNote)
        }

        let dropped = override?.droppedSlotIDs ?? []
        let periods = template.slots
            .filter { !dropped.contains($0.id) }
            .map { slot in
                ResolvedPeriod(
                    slot: slot,
                    course: assignmentsByKey[AssignmentKey(dayTemplateID: template.id, periodSlotID: slot.id)],
                    date: date,
                    start: date.date(at: slot.start, in: calendar),
                    end: date.date(at: slot.end, in: calendar)
                )
            }

        guard !periods.isEmpty else {
            return noSchoolDay(date, note: override?.overrideNote)
        }

        return SchoolDay(
            date: date,
            templateName: template.name,
            isNoSchool: false,
            overrideNote: override?.overrideNote,
            periods: periods
        )
    }

    public func schoolDay(for date: Date) -> SchoolDay {
        schoolDay(for: YearMonthDay(date: date, calendar: calendar))
    }

    private func noSchoolDay(_ date: YearMonthDay, note: String?) -> SchoolDay {
        SchoolDay(
            date: date,
            templateName: nil,
            isNoSchool: true,
            overrideNote: note,
            periods: []
        )
    }

    /// The next date with at least one period, searching forward from `date`.
    public func nextSchoolDay(after date: YearMonthDay) -> SchoolDay? {
        nextSchoolDay(onOrAfter: date.adding(days: 1, in: calendar))
    }

    public func nextSchoolDay(onOrAfter date: YearMonthDay) -> SchoolDay? {
        var cursor = date
        for _ in 0..<Self.forwardSearchLimitDays {
            let day = schoolDay(for: cursor)
            if day.hasClasses { return day }
            cursor = cursor.adding(days: 1, in: calendar)
        }
        return nil
    }

    // MARK: - Snapshot

    /// The whole product in one function.
    public func snapshot(at now: Date = Date()) -> ScheduleSnapshot {
        let today = YearMonthDay(date: now, calendar: calendar)
        let day = schoolDay(for: today)
        let startOfTomorrow = today.adding(days: 1, in: calendar).startOfDay(in: calendar)

        guard day.hasClasses else {
            return ScheduleSnapshot(
                now: now,
                day: day,
                status: .noSchool(reason: noSchoolReason(for: day)),
                current: nil,
                next: nil,
                upcoming: [],
                countdownTarget: nil,
                nextBoundary: startOfTomorrow
            )
        }

        let periods = day.periods
        let upcoming = periods.filter { $0.start > now }

        // Inside a period.
        if let current = periods.first(where: { $0.contains(now) }) {
            let next = upcoming.first
            return ScheduleSnapshot(
                now: now,
                day: day,
                status: .inPeriod(current: current, next: next),
                current: current,
                next: next,
                upcoming: upcoming,
                countdownTarget: current.end,
                nextBoundary: current.end
            )
        }

        // Before the first bell.
        if let first = periods.first, now < first.start {
            return ScheduleSnapshot(
                now: now,
                day: day,
                status: .beforeSchool(next: first),
                current: nil,
                next: first,
                upcoming: upcoming,
                countdownTarget: first.start,
                nextBoundary: first.start
            )
        }

        // Passing time: past one period's end, before the next one's start.
        if let next = upcoming.first,
           let previous = periods.last(where: { $0.end <= now }) {
            return ScheduleSnapshot(
                now: now,
                day: day,
                status: .passing(previous: previous, next: next),
                current: nil,
                next: next,
                upcoming: upcoming,
                countdownTarget: next.start,
                nextBoundary: next.start
            )
        }

        // The day is over. Show tomorrow's first class.
        let tomorrowFirst = nextSchoolDay(after: today)?.firstPeriod
        return ScheduleSnapshot(
            now: now,
            day: day,
            status: .dayComplete(nextDay: tomorrowFirst),
            current: nil,
            next: tomorrowFirst,
            upcoming: [],
            countdownTarget: nil,
            nextBoundary: startOfTomorrow
        )
    }

    private func noSchoolReason(for day: SchoolDay) -> String {
        if let note = day.overrideNote, !note.isEmpty { return note }
        let weekday = day.date.weekday(in: calendar)
        let symbols = calendar.weekdaySymbols
        if symbols.indices.contains(weekday - 1) { return symbols[weekday - 1] }
        return "No school"
    }

    // MARK: - Widget timeline

    /// Instants at which a glance surface would display something different.
    ///
    /// `WidgetKit` precomputes entries for these so the countdown flips at the
    /// bell without the app ever waking.
    public func timelineBoundaries(from now: Date, limit: Int = 40) -> [Date] {
        guard limit > 0 else { return [] }
        var boundaries: [Date] = [now]
        var cursor = now

        while boundaries.count < limit {
            let snapshot = self.snapshot(at: cursor)
            guard let boundary = snapshot.nextBoundary, boundary > cursor else { break }
            boundaries.append(boundary)
            cursor = boundary
        }

        return boundaries
    }

    /// Dates at which a widget timeline should render an entry.
    ///
    /// Period boundaries alone are not enough: between two bells the countdown
    /// would sit frozen on the minute the last entry was built. So while there
    /// is something to count down to, entries are emitted every minute for the
    /// next `minuteWindow`, and only then does the timeline fall back to bells.
    /// Entries are cheap; widget reloads are not, and this needs neither.
    public func timelineEntryDates(
        from now: Date,
        minuteWindow: TimeInterval = 90 * 60,
        limit: Int = 120
    ) -> [Date] {
        guard limit > 0 else { return [] }

        var dates: [Date] = [now]
        let windowEnd = now.addingTimeInterval(minuteWindow)

        if snapshot(at: now).countdownTarget != nil {
            var tick = nextWholeMinute(after: now)
            while tick < windowEnd && dates.count < limit {
                dates.append(tick)
                tick = tick.addingTimeInterval(60)
            }
        }

        for boundary in timelineBoundaries(from: now, limit: 40)
        where boundary > (dates.last ?? now) && dates.count < limit {
            dates.append(boundary)
        }

        return dates
    }

    /// The next instant with zero seconds, strictly after `date`.
    private func nextWholeMinute(after date: Date) -> Date {
        calendar.nextDate(
            after: date,
            matching: DateComponents(second: 0),
            matchingPolicy: .nextTime
        ) ?? date.addingTimeInterval(60)
    }

    // MARK: - Lookups

    public func template(id: UUID) -> DayTemplate? { templatesByID[id] }

    public func assignment(dayTemplateID: UUID, periodSlotID: UUID) -> CourseAssignment? {
        assignmentsByKey[AssignmentKey(dayTemplateID: dayTemplateID, periodSlotID: periodSlotID)]
    }

    /// Distinct course names already entered, for the manual grid's autocomplete.
    public var knownCourseNames: [String] {
        Array(Set(configuration.assignments.map(\.courseName).filter { !$0.isEmpty })).sorted()
    }

    /// Distinct room numbers already entered, for the manual grid's autocomplete.
    public var knownRooms: [String] {
        Array(Set(configuration.assignments.map(\.room).filter { !$0.isEmpty })).sorted()
    }

    /// Whether ping notifications should be suppressed right now, per the spec's
    /// rule that alerts are muted during the student's own instructional periods.
    public func isInInstructionalPeriod(at now: Date = Date()) -> Bool {
        snapshot(at: now).current?.isInstructional ?? false
    }
}
