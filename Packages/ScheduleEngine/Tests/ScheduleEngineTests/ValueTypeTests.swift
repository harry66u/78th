import XCTest
import ScheduleEngine

final class TimeOfDayTests: XCTestCase {

    func testParsesTheContractFormat() {
        XCTAssertEqual(TimeOfDay("08:15")?.minutes, 8 * 60 + 15)
        XCTAssertEqual(TimeOfDay("00:00")?.minutes, 0)
        XCTAssertEqual(TimeOfDay("23:59")?.minutes, 23 * 60 + 59)
    }

    func testToleratesTheShapesRealSchedulesUse() {
        // Pasted and photographed schedules are not consistent, and a student
        // should not have to retype a whole day because of a space.
        XCTAssertEqual(TimeOfDay("8:15")?.minutes, 8 * 60 + 15)
        XCTAssertEqual(TimeOfDay(" 8:15 ")?.minutes, 8 * 60 + 15)
        XCTAssertEqual(TimeOfDay("08:15:00")?.minutes, 8 * 60 + 15)
        XCTAssertEqual(TimeOfDay("8:15 AM")?.minutes, 8 * 60 + 15)
        XCTAssertEqual(TimeOfDay("3:40 PM")?.minutes, 15 * 60 + 40)
        XCTAssertEqual(TimeOfDay("12:30 PM")?.minutes, 12 * 60 + 30)
        XCTAssertEqual(TimeOfDay("12:05 AM")?.minutes, 5)
        XCTAssertEqual(TimeOfDay("1:05 p.m.")?.minutes, 13 * 60 + 5)
    }

    func testRejectsGarbageRatherThanGuessing() {
        XCTAssertNil(TimeOfDay(""))
        XCTAssertNil(TimeOfDay("lunch"))
        XCTAssertNil(TimeOfDay("8"))
        XCTAssertNil(TimeOfDay("8:75"))
        XCTAssertNil(TimeOfDay("25:00"))
        XCTAssertNil(TimeOfDay("13:00 PM"))
    }

    func testRoundTripsThroughItsDescription() {
        let time = TimeOfDay(hour: 8, minute: 5)
        XCTAssertEqual(time.description, "08:05")
        XCTAssertEqual(TimeOfDay(time.description), time)
    }

    func testOrdersByClockTime() {
        XCTAssertLessThan(TimeOfDay("08:15")!, TimeOfDay("08:16")!)
        XCTAssertLessThan(TimeOfDay("09:59")!, TimeOfDay("10:00")!)
    }
}

final class YearMonthDayTests: XCTestCase {

    private var calendar: Calendar { Fixture.calendar }

    func testParsesAndPrintsISO8601() {
        let day = YearMonthDay(iso8601: "2026-09-08")
        XCTAssertEqual(day?.year, 2026)
        XCTAssertEqual(day?.month, 9)
        XCTAssertEqual(day?.day, 8)
        XCTAssertEqual(day?.description, "2026-09-08")
        XCTAssertNil(YearMonthDay(iso8601: "2026-13-01"))
        XCTAssertNil(YearMonthDay(iso8601: "next tuesday"))
    }

    func testWeekdayMatchesFoundationsNumbering() {
        XCTAssertEqual(Fixture.ymd("2026-09-13").weekday(in: calendar), 1, "Sunday")
        XCTAssertEqual(Fixture.ymd("2026-09-08").weekday(in: calendar), 3, "Tuesday")
        XCTAssertEqual(Fixture.ymd("2026-09-12").weekday(in: calendar), 7, "Saturday")
    }

    func testAddingDaysCrossesMonthAndYearBoundaries() {
        XCTAssertEqual(Fixture.ymd("2026-09-30").adding(days: 1, in: calendar), Fixture.ymd("2026-10-01"))
        XCTAssertEqual(Fixture.ymd("2026-12-31").adding(days: 1, in: calendar), Fixture.ymd("2027-01-01"))
        XCTAssertEqual(Fixture.ymd("2028-02-28").adding(days: 1, in: calendar), Fixture.ymd("2028-02-29"), "Leap year")
    }

    func testOrdersChronologically() {
        XCTAssertLessThan(Fixture.ymd("2026-09-08"), Fixture.ymd("2026-09-09"))
        XCTAssertLessThan(Fixture.ymd("2026-09-30"), Fixture.ymd("2026-10-01"))
        XCTAssertLessThan(Fixture.ymd("2026-12-31"), Fixture.ymd("2027-01-01"))
    }
}

final class FormattingTests: XCTestCase {

    func testCountdownReadsInWholeMinutes() {
        XCTAssertEqual(ScheduleFormatting.countdown(seconds: 0), "now")
        XCTAssertEqual(ScheduleFormatting.countdown(seconds: 1), "1 min")
        XCTAssertEqual(ScheduleFormatting.countdown(seconds: 60), "1 min")
        XCTAssertEqual(ScheduleFormatting.countdown(seconds: 61), "2 min")
        XCTAssertEqual(ScheduleFormatting.countdown(seconds: 23 * 60), "23 min")
        XCTAssertEqual(ScheduleFormatting.countdown(seconds: 60 * 60), "1:00")
        XCTAssertEqual(ScheduleFormatting.countdown(seconds: 65 * 60), "1:05")
    }

    func testSmallWidgetSplitsTheValueFromItsUnit() {
        XCTAssertEqual(ScheduleFormatting.countdownValue(seconds: 23 * 60), "23")
        XCTAssertEqual(ScheduleFormatting.countdownUnit(seconds: 23 * 60), "min")
        XCTAssertEqual(ScheduleFormatting.countdownValue(seconds: 90 * 60), "1:30")
        XCTAssertEqual(ScheduleFormatting.countdownUnit(seconds: 90 * 60), "hrs")
    }

    func testGlanceLineCoversEveryStatus() {
        let school = Fixture.school()
        let zone = Fixture.timeZone

        let inClass = school.engine.snapshot(at: Fixture.at("2026-09-08", "09:30"))
        XCTAssertEqual(ScheduleFormatting.glanceLine(for: inClass, timeZone: zone), "AP Physics C \u{00B7} 402 \u{00B7} 20 min")

        let passing = school.engine.snapshot(at: Fixture.at("2026-09-08", "08:55"))
        XCTAssertEqual(ScheduleFormatting.glanceLine(for: passing, timeZone: zone), "AP Physics C \u{00B7} 402 \u{00B7} in 5 min")

        let sunday = school.engine.snapshot(at: Fixture.at("2026-09-13", "10:00"))
        XCTAssertEqual(ScheduleFormatting.glanceLine(for: sunday, timeZone: zone), "Sunday")
    }

    func testRelativePastStaysShortEnoughForAPingRow() {
        let now = Fixture.at("2026-09-08", "12:00")
        XCTAssertEqual(ScheduleFormatting.relativePast(now.addingTimeInterval(-30), now: now), "just now")
        XCTAssertEqual(ScheduleFormatting.relativePast(now.addingTimeInterval(-120), now: now), "2 min ago")
        XCTAssertEqual(ScheduleFormatting.relativePast(now.addingTimeInterval(-7200), now: now), "2h ago")
    }
}
