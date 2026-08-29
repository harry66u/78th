import XCTest
import ScheduleEngine

/// M1's acceptance test: given any date and time, the engine returns the correct
/// current and next period across day types, half days, and no school days.
final class ScheduleEngineTests: XCTestCase {

    // MARK: - Inside a period

    func testInsideAPeriodReportsCurrentNextAndRemaining() {
        let school = Fixture.school()
        let snapshot = school.engine.snapshot(at: Fixture.at("2026-09-08", "09:30"))

        guard case .inPeriod(let current, let next) = snapshot.status else {
            return XCTFail("Expected .inPeriod, got \(snapshot.status)")
        }
        XCTAssertEqual(current.slot.label, "Period 2")
        XCTAssertEqual(current.title, "AP Physics C")
        XCTAssertEqual(current.room, "402")
        XCTAssertEqual(next?.slot.label, "Lunch")
        // 09:30 to 09:50.
        XCTAssertEqual(snapshot.secondsRemaining, 20 * 60)
        XCTAssertEqual(snapshot.minutesRemaining, 20)
        XCTAssertTrue(snapshot.isCountingDownCurrentPeriod)
        XCTAssertEqual(snapshot.day.templateName, "A Day")
    }

    func testPeriodStartIsInclusive() {
        let school = Fixture.school()
        let snapshot = school.engine.snapshot(at: Fixture.at("2026-09-08", "08:00"))

        guard case .inPeriod(let current, _) = snapshot.status else {
            return XCTFail("Expected .inPeriod at the bell, got \(snapshot.status)")
        }
        XCTAssertEqual(current.slot.label, "Period 1")
        XCTAssertEqual(snapshot.secondsRemaining, 50 * 60)
    }

    func testPeriodEndIsExclusive() {
        let school = Fixture.school()
        let snapshot = school.engine.snapshot(at: Fixture.at("2026-09-08", "08:50"))

        guard case .passing(let previous, let next) = snapshot.status else {
            return XCTFail("Expected .passing at the closing bell, got \(snapshot.status)")
        }
        XCTAssertEqual(previous.slot.label, "Period 1")
        XCTAssertEqual(next.slot.label, "Period 2")
        XCTAssertNil(snapshot.current)
    }

    func testLastSecondOfAPeriodIsStillInThatPeriod() {
        let school = Fixture.school()
        let snapshot = school.engine.snapshot(at: Fixture.at("2026-09-08", "08:49").addingTimeInterval(59))

        guard case .inPeriod(let current, _) = snapshot.status else {
            return XCTFail("Expected .inPeriod, got \(snapshot.status)")
        }
        XCTAssertEqual(current.slot.label, "Period 1")
        XCTAssertEqual(snapshot.secondsRemaining, 1)
        XCTAssertEqual(snapshot.minutesRemaining, 1, "A partial minute must round up, never to zero")
    }

    // MARK: - Around the edges of the day

    func testBeforeTheFirstBell() {
        let school = Fixture.school()
        let snapshot = school.engine.snapshot(at: Fixture.at("2026-09-08", "07:30"))

        guard case .beforeSchool(let next) = snapshot.status else {
            return XCTFail("Expected .beforeSchool, got \(snapshot.status)")
        }
        XCTAssertEqual(next.title, "Talmud")
        XCTAssertEqual(snapshot.secondsRemaining, 30 * 60)
        XCTAssertNil(snapshot.current)
        XCTAssertEqual(snapshot.upcoming.count, 4)
    }

    func testPassingTimeCountsDownToTheNextPeriod() {
        let school = Fixture.school()
        let snapshot = school.engine.snapshot(at: Fixture.at("2026-09-08", "08:55"))

        guard case .passing(let previous, let next) = snapshot.status else {
            return XCTFail("Expected .passing, got \(snapshot.status)")
        }
        XCTAssertEqual(previous.title, "Talmud")
        XCTAssertEqual(next.title, "AP Physics C")
        XCTAssertEqual(snapshot.secondsRemaining, 5 * 60)
        XCTAssertFalse(snapshot.isCountingDownCurrentPeriod)
    }

    func testAfterTheLastPeriodShowsTomorrowsFirstClass() {
        let school = Fixture.school()
        let snapshot = school.engine.snapshot(at: Fixture.at("2026-09-08", "20:00"))

        guard case .dayComplete(let nextDay) = snapshot.status else {
            return XCTFail("Expected .dayComplete, got \(snapshot.status)")
        }
        XCTAssertEqual(nextDay?.date, Fixture.ymd("2026-09-09"))
        XCTAssertEqual(nextDay?.title, "Talmud")
        XCTAssertTrue(snapshot.upcoming.isEmpty)
        XCTAssertNil(snapshot.countdownTarget, "A finished day must not count down 14 hours to tomorrow")
    }

    func testFridayEveningSkipsTheWeekendToMonday() {
        let school = Fixture.school()
        let snapshot = school.engine.snapshot(at: Fixture.at("2026-09-11", "18:00"))

        guard case .dayComplete(let nextDay) = snapshot.status else {
            return XCTFail("Expected .dayComplete, got \(snapshot.status)")
        }
        XCTAssertEqual(nextDay?.date, Fixture.ymd("2026-09-14"), "Saturday and Sunday are not school days")
        XCTAssertEqual(nextDay?.title, "Talmud", "Monday is an A Day")
    }

    // MARK: - Day types

    func testFridayUsesItsOwnBellTimes() {
        let school = Fixture.school()
        let snapshot = school.engine.snapshot(at: Fixture.at("2026-09-11", "09:00"))

        guard case .inPeriod(let current, let next) = snapshot.status else {
            return XCTFail("Expected .inPeriod, got \(snapshot.status)")
        }
        XCTAssertEqual(snapshot.day.templateName, "Friday")
        XCTAssertEqual(current.title, "AP Micro", "08:45-09:25 on a Friday")
        XCTAssertNil(next, "Friday has no period after Period 2")
        XCTAssertEqual(snapshot.secondsRemaining, 25 * 60)
    }

    func testHalfDayOverrideReplacesTheRegularBellSchedule() {
        let school = Fixture.school()
        let engine = school.overridden(by: [
            CalendarDay(
                date: Fixture.ymd("2026-09-09"),
                dayTemplateID: school.halfDay.id,
                overrideNote: "Half day, early dismissal"
            )
        ])

        let day = engine.schoolDay(for: Fixture.ymd("2026-09-09"))
        XCTAssertEqual(day.templateName, "Half Day")
        XCTAssertEqual(day.periods.count, 2)
        XCTAssertEqual(day.overrideNote, "Half day, early dismissal")

        // 09:10 is mid-morning on a regular Wednesday but after dismissal here.
        let snapshot = engine.snapshot(at: Fixture.at("2026-09-09", "09:10"))
        guard case .dayComplete = snapshot.status else {
            return XCTFail("Expected the half day to be over at 09:10, got \(snapshot.status)")
        }
    }

    func testDroppedPeriodsAreRemovedFromTheDay() {
        let school = Fixture.school()
        let droppedID = school.slot("Period 2", in: school.aDay).id
        let engine = school.overridden(by: [
            CalendarDay(
                date: Fixture.ymd("2026-09-08"),
                dayTemplateID: school.aDay.id,
                overrideNote: "Assembly, Period 2 dropped",
                droppedSlotIDs: [droppedID]
            )
        ])

        let day = engine.schoolDay(for: Fixture.ymd("2026-09-08"))
        XCTAssertEqual(day.periods.map(\.slot.label), ["Period 1", "Lunch", "Period 3"])

        // 09:30 would be Period 2 on a normal A Day.
        let snapshot = engine.snapshot(at: Fixture.at("2026-09-08", "09:30"))
        guard case .passing(let previous, let next) = snapshot.status else {
            return XCTFail("Expected .passing, got \(snapshot.status)")
        }
        XCTAssertEqual(previous.slot.label, "Period 1")
        XCTAssertEqual(next.slot.label, "Lunch")
        XCTAssertEqual(snapshot.secondsRemaining, 150 * 60, "09:30 to 12:00")
    }

    // MARK: - No school

    func testWeekendIsNoSchoolAndNamesTheDay() {
        let school = Fixture.school()
        let snapshot = school.engine.snapshot(at: Fixture.at("2026-09-13", "10:00"))

        guard case .noSchool(let reason) = snapshot.status else {
            return XCTFail("Expected .noSchool, got \(snapshot.status)")
        }
        XCTAssertEqual(reason, "Sunday")
        XCTAssertNil(snapshot.current)
        XCTAssertNil(snapshot.next, "A no-school day shows the day name and nothing else")
        XCTAssertNil(snapshot.countdownTarget)
    }

    func testExplicitNoSchoolDayUsesItsNote() {
        let school = Fixture.school()
        let engine = school.overridden(by: [
            CalendarDay(date: Fixture.ymd("2026-09-08"), isNoSchool: true, overrideNote: "Rosh Hashanah")
        ])
        let snapshot = engine.snapshot(at: Fixture.at("2026-09-08", "09:30"))

        guard case .noSchool(let reason) = snapshot.status else {
            return XCTFail("Expected .noSchool, got \(snapshot.status)")
        }
        XCTAssertEqual(reason, "Rosh Hashanah")
        XCTAssertTrue(snapshot.day.isNoSchool)
    }

    func testNoSchoolDayStillKnowsTheNextSchoolDay() {
        let school = Fixture.school()
        let next = school.engine.nextSchoolDay(after: Fixture.ymd("2026-09-12"))
        XCTAssertEqual(next?.date, Fixture.ymd("2026-09-14"))
        XCTAssertEqual(next?.templateName, "A Day")
    }

    func testEmptyConfigurationIsNoSchoolRatherThanACrash() {
        let engine = ScheduleEngine(configuration: ScheduleConfiguration())
        let snapshot = engine.snapshot(at: Fixture.at("2026-09-08", "09:30"))

        guard case .noSchool = snapshot.status else {
            return XCTFail("Expected .noSchool, got \(snapshot.status)")
        }
        XCTAssertNil(engine.nextSchoolDay(onOrAfter: Fixture.ymd("2026-09-08")))
    }

    // MARK: - Courses

    func testSlotWithoutACourseFallsBackToItsLabel() {
        let school = Fixture.school()
        let snapshot = school.engine.snapshot(at: Fixture.at("2026-09-08", "12:15"))

        guard case .inPeriod(let current, _) = snapshot.status else {
            return XCTFail("Expected .inPeriod, got \(snapshot.status)")
        }
        XCTAssertEqual(current.title, "Lunch")
        XCTAssertNil(current.room)
        XCTAssertNil(current.slotLabel, "The label must not be repeated under itself")
        XCTAssertFalse(current.isInstructional)
    }

    func testInstructionalPeriodDetectionDrivesNotificationMuting() {
        let school = Fixture.school()
        XCTAssertTrue(school.engine.isInInstructionalPeriod(at: Fixture.at("2026-09-08", "09:30")))
        XCTAssertFalse(school.engine.isInInstructionalPeriod(at: Fixture.at("2026-09-08", "12:15")), "Lunch")
        XCTAssertFalse(school.engine.isInInstructionalPeriod(at: Fixture.at("2026-09-08", "08:55")), "Passing time")
        XCTAssertFalse(school.engine.isInInstructionalPeriod(at: Fixture.at("2026-09-13", "09:30")), "Sunday")
    }

    // MARK: - Widget timeline

    func testTimelineBoundariesLandOnEveryBell() {
        let school = Fixture.school()
        let start = Fixture.at("2026-09-08", "07:00")
        let boundaries = school.engine.timelineBoundaries(from: start, limit: 10)

        XCTAssertEqual(boundaries, [
            start,
            Fixture.at("2026-09-08", "08:00"),
            Fixture.at("2026-09-08", "08:50"),
            Fixture.at("2026-09-08", "09:00"),
            Fixture.at("2026-09-08", "09:50"),
            Fixture.at("2026-09-08", "12:00"),
            Fixture.at("2026-09-08", "12:40"),
            Fixture.at("2026-09-08", "13:00"),
            Fixture.at("2026-09-08", "13:50"),
            Fixture.at("2026-09-09", "00:00")
        ])
    }

    func testTimelineBoundariesAreStrictlyIncreasingAndBounded() {
        let school = Fixture.school()
        let boundaries = school.engine.timelineBoundaries(
            from: Fixture.at("2026-09-11", "18:00"),
            limit: 6
        )
        XCTAssertEqual(boundaries.count, 6)
        for index in boundaries.indices.dropFirst() {
            XCTAssertGreaterThan(boundaries[index], boundaries[index - 1])
        }
    }

    func testTimelineFromAnEmptyScheduleStillAdvances() {
        let engine = ScheduleEngine(configuration: ScheduleConfiguration())
        let boundaries = engine.timelineBoundaries(from: Fixture.at("2026-09-08", "09:30"), limit: 4)
        XCTAssertEqual(boundaries.count, 4, "A blank schedule must still refresh at midnight, not spin")
    }

    // MARK: - Time zones

    func testBellTimesSurviveTheSpringForwardTransition() {
        let school = Fixture.school()
        // 2027-03-14 is the spring-forward Sunday; the Monday after it is the
        // first school day on the new offset.
        let day = school.engine.schoolDay(for: Fixture.ymd("2027-03-15"))
        let first = day.periods.first!

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Fixture.timeZone
        XCTAssertEqual(calendar.component(.hour, from: first.start), 8)
        XCTAssertEqual(calendar.component(.minute, from: first.start), 0)
    }

    func testTheEngineUsesTheSchoolTimeZoneNotTheDeviceOne() {
        let school = Fixture.school()
        // 06:30 in Los Angeles is 09:30 in New York: mid Period 2.
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = losAngeles
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 8
        components.hour = 6
        components.minute = 30
        let instant = calendar.date(from: components)!

        guard case .inPeriod(let current, _) = school.engine.snapshot(at: instant).status else {
            return XCTFail("Expected .inPeriod")
        }
        XCTAssertEqual(current.title, "AP Physics C")
    }
}

/// The widget's timeline is generated ahead of time and never woken by the app,
/// so its entry dates are part of the engine's contract.
final class TimelineEntryTests: XCTestCase {

    func testEntriesTickEveryMinuteWhileACountdownIsRunning() {
        let school = Fixture.school()
        let start = Fixture.at("2026-09-08", "09:00")
        let dates = school.engine.timelineEntryDates(from: start, minuteWindow: 10 * 60, limit: 120)

        XCTAssertEqual(dates.first, start)
        XCTAssertEqual(dates[1], Fixture.at("2026-09-08", "09:01"))
        XCTAssertEqual(dates[2], Fixture.at("2026-09-08", "09:02"))
        // Ten one-minute ticks inside the window, then the 09:50 bell.
        XCTAssertTrue(dates.contains(Fixture.at("2026-09-08", "09:50")))
    }

    func testEntriesAreStrictlyIncreasingAndWithinTheLimit() {
        let school = Fixture.school()
        let dates = school.engine.timelineEntryDates(from: Fixture.at("2026-09-08", "09:00"), limit: 40)
        XCTAssertLessThanOrEqual(dates.count, 40)
        for index in dates.indices.dropFirst() {
            XCTAssertGreaterThan(dates[index], dates[index - 1])
        }
    }

    func testAMidnightStartTickIsAlignedToWholeMinutes() {
        let school = Fixture.school()
        let offset = Fixture.at("2026-09-08", "09:00").addingTimeInterval(37)
        let dates = school.engine.timelineEntryDates(from: offset, minuteWindow: 5 * 60, limit: 10)

        XCTAssertEqual(dates.first, offset)
        XCTAssertEqual(dates[1], Fixture.at("2026-09-08", "09:01"), "Ticks land on the minute, not 37 seconds past")
    }

    func testNoSchoolDayDoesNotBurnEntriesOnAMinuteTicker() {
        let school = Fixture.school()
        let dates = school.engine.timelineEntryDates(from: Fixture.at("2026-09-13", "10:00"), limit: 40)

        XCTAssertEqual(dates[1], Fixture.at("2026-09-14", "00:00"))
        XCTAssertGreaterThan(
            dates[1].timeIntervalSince(dates[0]), 60,
            "There is nothing to count down on a Sunday, so nothing to tick"
        )
    }

    func testAFinishedDayWaitsForMidnightRatherThanTicking() {
        let school = Fixture.school()
        let dates = school.engine.timelineEntryDates(from: Fixture.at("2026-09-08", "20:00"), limit: 40)
        XCTAssertEqual(dates[1], Fixture.at("2026-09-09", "00:00"))
    }
}
