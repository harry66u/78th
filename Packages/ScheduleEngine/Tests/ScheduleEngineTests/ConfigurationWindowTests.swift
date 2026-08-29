import XCTest
import ScheduleEngine

/// The window that decides what crosses to the watch.
///
/// It is tested here rather than alongside the sync code because it is the
/// engine's promise that is being relied on: anything the engine can reach from
/// `date` must survive the trim, or the wrist and the phone start disagreeing
/// about a holiday.
final class ConfigurationWindowTests: XCTestCase {

    /// A configuration whose only content is one dated override per day across a
    /// year either side of the reference date.
    private func school(withOverridesFrom start: String, days: Int) -> ScheduleConfiguration {
        let school = Fixture.school()
        var configuration = school.configuration
        var cursor = Fixture.ymd(start)
        var overrides: [CalendarDay] = []
        for _ in 0..<days {
            overrides.append(CalendarDay(date: cursor, isNoSchool: true, overrideNote: "Break"))
            cursor = cursor.adding(days: 1, in: Fixture.calendar)
        }
        configuration.calendarDays = overrides
        return configuration
    }

    func testKeepsEveryDateTheEngineCanStillReach() {
        let configuration = school(withOverridesFrom: "2026-09-08", days: 365)
        let trimmed = configuration.trimmingCalendarDays(around: Fixture.at("2026-09-08", "09:30"))

        // Today, and the last day inside the forward search limit, both survive.
        let kept = Set(trimmed.calendarDays.map(\.date))
        XCTAssertTrue(kept.contains(Fixture.ymd("2026-09-08")))

        let lastReachable = Fixture.ymd("2026-09-08")
            .adding(days: ScheduleEngine.forwardSearchLimitDays, in: Fixture.calendar)
        XCTAssertTrue(kept.contains(lastReachable))
    }

    func testDropsWhatIsPastAndWhatIsOutOfReach() {
        // Long enough to run past the forward search limit, so the assertion
        // about it is about the trim and not about the fixture running out.
        let configuration = school(withOverridesFrom: "2026-01-01", days: 400)
        let trimmed = configuration.trimmingCalendarDays(around: Fixture.at("2026-09-08", "09:30"))

        let kept = Set(trimmed.calendarDays.map(\.date))
        XCTAssertFalse(kept.contains(Fixture.ymd("2026-06-01")), "A day months behind is dead weight")
        XCTAssertFalse(kept.contains(Fixture.ymd("2026-09-06")), "Two days behind is still behind")

        let pastLimit = Fixture.ymd("2026-09-08")
            .adding(days: ScheduleEngine.forwardSearchLimitDays + 1, in: Fixture.calendar)
        XCTAssertFalse(kept.contains(pastLimit), "Nothing can reach past the forward search limit")
    }

    func testKeepsYesterday() {
        // A watch set to a time zone behind the schedule's can still be on the
        // previous date when the phone builds the payload.
        let configuration = school(withOverridesFrom: "2026-09-01", days: 30)
        let trimmed = configuration.trimmingCalendarDays(around: Fixture.at("2026-09-08", "00:10"))
        XCTAssertTrue(trimmed.calendarDays.map(\.date).contains(Fixture.ymd("2026-09-07")))
    }

    func testLeavesTheRestOfTheConfigurationAlone() {
        let configuration = school(withOverridesFrom: "2026-01-01", days: 365)
        let trimmed = configuration.trimmingCalendarDays(around: Fixture.at("2026-09-08", "09:30"))

        XCTAssertEqual(trimmed.templates, configuration.templates)
        XCTAssertEqual(trimmed.assignments, configuration.assignments)
        XCTAssertEqual(trimmed.weekdayDefaults, configuration.weekdayDefaults)
        XCTAssertEqual(trimmed.timeZoneIdentifier, configuration.timeZoneIdentifier)
        XCTAssertLessThan(trimmed.calendarDays.count, configuration.calendarDays.count)
    }

    func testATrimmedConfigurationAnswersTheSameQuestionsInsideTheWindow() {
        // The point of the whole exercise: what the watch receives has to behave
        // exactly like what the phone holds, for every date the watch can ask
        // about.
        let school = Fixture.school()
        var configuration = school.configuration
        configuration.calendarDays = [
            CalendarDay(date: Fixture.ymd("2026-09-09"), isNoSchool: true, overrideNote: "Yom Tov"),
            CalendarDay(date: Fixture.ymd("2025-09-09"), isNoSchool: true, overrideNote: "Last year")
        ]

        let now = Fixture.at("2026-09-08", "09:30")
        let full = ScheduleEngine(configuration: configuration)
        let onWatch = ScheduleEngine(configuration: configuration.trimmingCalendarDays(around: now))

        XCTAssertEqual(full.snapshot(at: now), onWatch.snapshot(at: now))
        XCTAssertEqual(
            full.schoolDay(for: Fixture.ymd("2026-09-09")),
            onWatch.schoolDay(for: Fixture.ymd("2026-09-09"))
        )
    }

    func testTrimmingIsSafeWhenThereIsNothingToTrim() {
        let empty = ScheduleConfiguration()
        let trimmed = empty.trimmingCalendarDays(around: Date())
        XCTAssertTrue(trimmed.calendarDays.isEmpty)
        XCTAssertTrue(trimmed.isEmpty)
    }
}
