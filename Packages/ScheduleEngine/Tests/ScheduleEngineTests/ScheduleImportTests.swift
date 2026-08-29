import XCTest
import ScheduleEngine

final class ScheduleImportTests: XCTestCase {

    private let validResponse = """
    {
      "dayTemplates": [
        { "name": "A Day",
          "slots": [
            { "label": "Period 1", "start": "08:15", "end": "09:00",
              "course": "Talmud", "room": "305", "teacher": "" },
            { "label": "Period 2", "start": "09:05", "end": "09:50",
              "course": "AP Physics C", "room": "402", "teacher": "Mr. Klotz" },
            { "label": "Lunch", "start": "12:00", "end": "12:40",
              "course": "", "room": "", "teacher": "" }
          ] }
      ],
      "unparsed": ["Advisory TBD"]
    }
    """

    func testDecodesTheContractShape() throws {
        let payload = try ScheduleImporter.decode(validResponse)
        XCTAssertEqual(payload.dayTemplates.count, 1)
        XCTAssertEqual(payload.dayTemplates[0].slots.count, 3)
        XCTAssertEqual(payload.unparsed, ["Advisory TBD"])
    }

    func testStripsMarkdownFencesAndProse() throws {
        // The prompt says no fences. Models add them anyway, and a student
        // should not lose a parse over three backticks.
        let fenced = "Here is the schedule:\n```json\n\(validResponse)\n```\n"
        let payload = try ScheduleImporter.decode(fenced)
        XCTAssertEqual(payload.dayTemplates.first?.name, "A Day")
    }

    func testMissingKeysDecodeAsEmptyRatherThanThrowing() throws {
        let payload = try ScheduleImporter.decode("{\"dayTemplates\": []}")
        XCTAssertTrue(payload.dayTemplates.isEmpty)
        XCTAssertTrue(payload.unparsed.isEmpty)
    }

    func testBuildsTemplatesCoursesAndAWorkingEngine() throws {
        let payload = try ScheduleImporter.decode(validResponse)
        let result = ScheduleImporter.makeConfiguration(from: payload)

        XCTAssertEqual(result.configuration.templates.count, 1)
        XCTAssertEqual(result.courseCount, 2, "Lunch has no course")
        XCTAssertEqual(result.configuration.assignments.count, 2)

        let engine = ScheduleEngine(configuration: result.configuration)
        let day = engine.schoolDay(for: Fixture.ymd("2026-09-08"))
        XCTAssertEqual(day.periods.map(\.title), ["Talmud", "AP Physics C", "Lunch"])
        XCTAssertEqual(day.periods.first?.room, "305")
    }

    func testUnparsedLinesBecomeIssuesForTheReviewScreen() throws {
        let payload = try ScheduleImporter.decode(validResponse)
        let result = ScheduleImporter.makeConfiguration(from: payload)
        XCTAssertEqual(result.issues.filter { $0.kind == .unparsedLine }.map(\.message), ["Advisory TBD"])
    }

    func testUnreadableTimesAreReportedAndTheRestSurvives() throws {
        let response = """
        { "dayTemplates": [ { "name": "A Day", "slots": [
            { "label": "Period 1", "start": "08:15", "end": "09:00", "course": "Talmud" },
            { "label": "Period 2", "start": "sometime", "end": "later", "course": "Physics" }
        ] } ], "unparsed": [] }
        """
        let result = ScheduleImporter.makeConfiguration(from: try ScheduleImporter.decode(response))

        XCTAssertEqual(result.configuration.templates.first?.slots.count, 1)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(result.issues.first?.kind, .unreadableTime)
        XCTAssertEqual(result.issues.first?.slotLabel, "Period 2")
    }

    func testBackwardsPeriodIsDroppedAndReported() throws {
        let response = """
        { "dayTemplates": [ { "name": "A Day", "slots": [
            { "label": "Period 1", "start": "09:00", "end": "08:15", "course": "Talmud" },
            { "label": "Period 2", "start": "09:05", "end": "09:50", "course": "Physics" }
        ] } ] }
        """
        let result = ScheduleImporter.makeConfiguration(from: try ScheduleImporter.decode(response))
        XCTAssertEqual(result.issues.first?.kind, .endsBeforeItStarts)
        XCTAssertEqual(result.configuration.templates.first?.slots.map(\.label), ["Period 2"])
    }

    func testOverlapsAreReportedButNotSilentlyCorrected() throws {
        let response = """
        { "dayTemplates": [ { "name": "A Day", "slots": [
            { "label": "Period 1", "start": "08:15", "end": "09:10", "course": "Talmud" },
            { "label": "Period 2", "start": "09:05", "end": "09:50", "course": "Physics" }
        ] } ] }
        """
        let result = ScheduleImporter.makeConfiguration(from: try ScheduleImporter.decode(response))

        XCTAssertEqual(result.issues.first?.kind, .overlap(otherLabel: "Period 1"))
        XCTAssertEqual(
            result.configuration.templates.first?.slots.count, 2,
            "Both periods are kept: the student decides which bell is wrong"
        )
    }

    func testEmptyTemplateIsReportedRatherThanCreated() throws {
        let response = """
        { "dayTemplates": [ { "name": "Ghost Day", "slots": [] } ] }
        """
        let result = ScheduleImporter.makeConfiguration(from: try ScheduleImporter.decode(response))
        XCTAssertTrue(result.configuration.templates.isEmpty)
        XCTAssertEqual(result.issues.first?.kind, .emptyTemplate)
    }

    func testLunchAndTefillahImportAsNonInstructional() throws {
        let payload = try ScheduleImporter.decode(validResponse)
        let result = ScheduleImporter.makeConfiguration(from: payload)
        let slots = result.configuration.templates.first!.slots
        XCTAssertEqual(slots.first { $0.label == "Lunch" }?.isInstructional, false)
        XCTAssertEqual(slots.first { $0.label == "Period 1" }?.isInstructional, true)
    }

    func testTheSameCourseGetsTheSameColourEverywhereItAppears() throws {
        let response = """
        { "dayTemplates": [
          { "name": "A Day", "slots": [
            { "label": "Period 1", "start": "08:15", "end": "09:00", "course": "Talmud" },
            { "label": "Period 2", "start": "09:05", "end": "09:50", "course": "Physics" } ] },
          { "name": "B Day", "slots": [
            { "label": "Period 1", "start": "08:15", "end": "09:00", "course": "Physics" },
            { "label": "Period 2", "start": "09:05", "end": "09:50", "course": "Talmud" } ] }
        ] }
        """
        let result = ScheduleImporter.makeConfiguration(from: try ScheduleImporter.decode(response))
        var colorsByCourse: [String: Set<Int>] = [:]
        for assignment in result.configuration.assignments {
            colorsByCourse[assignment.courseName, default: []].insert(assignment.colorTag)
        }
        XCTAssertEqual(colorsByCourse["Talmud"]?.count, 1)
        XCTAssertEqual(colorsByCourse["Physics"]?.count, 1)
        XCTAssertNotEqual(colorsByCourse["Talmud"], colorsByCourse["Physics"])
    }

    func testReimportKeepsTheStudentsWeekdayRotation() throws {
        // A student who reimports after fixing a typo must not lose which day
        // types fall on which weekdays.
        let first = ScheduleImporter.makeConfiguration(from: try ScheduleImporter.decode(validResponse))
        var configured = first.configuration
        let aDayID = configured.templates.first!.id
        configured.weekdayDefaults = [2: aDayID, 4: aDayID]

        let second = ScheduleImporter.makeConfiguration(
            from: try ScheduleImporter.decode(validResponse),
            existing: configured
        )
        let newADayID = second.configuration.templates.first!.id
        XCTAssertEqual(second.configuration.weekdayDefaults, [2: newADayID, 4: newADayID])
    }

    func testAFreshImportFallsBackToMondayThroughFriday() throws {
        let result = ScheduleImporter.makeConfiguration(from: try ScheduleImporter.decode(validResponse))
        XCTAssertEqual(Set(result.configuration.weekdayDefaults.keys), [2, 3, 4, 5, 6])
    }

    func testGarbageInputThrowsRatherThanProducingAnEmptySchedule() {
        XCTAssertThrowsError(try ScheduleImporter.decode("I could not read that schedule, sorry."))
    }
}
