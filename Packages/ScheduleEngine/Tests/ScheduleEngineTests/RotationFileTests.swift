import XCTest
import ScheduleEngine

final class RotationMergeTests: XCTestCase {

    func testAPushedRotationAssignsTemplatesToDates() {
        let school = Fixture.school()
        let file = RotationFile(
            version: 3,
            schoolYear: "2026-2027",
            publishedAt: Date(timeIntervalSince1970: 0),
            days: [
                RotationFile.PublishedDay(date: "2026-09-08", template: "Friday"),
                RotationFile.PublishedDay(date: "2026-09-09", noSchool: true, note: "Rosh Hashanah")
            ]
        )

        let (merged, report) = RotationMerge.apply(file, to: school.configuration)
        let engine = ScheduleEngine(configuration: merged)

        XCTAssertEqual(report.appliedVersion, 3)
        XCTAssertEqual(report.datesUpdated, 2)
        XCTAssertEqual(engine.schoolDay(for: Fixture.ymd("2026-09-08")).templateName, "Friday")
        XCTAssertTrue(engine.schoolDay(for: Fixture.ymd("2026-09-09")).isNoSchool)
        XCTAssertEqual(engine.schoolDay(for: Fixture.ymd("2026-09-09")).overrideNote, "Rosh Hashanah")
    }

    func testUpdatedBellTimesKeepTheStudentsCourses() {
        // The rule that makes the shared rotation safe to push: changing when a
        // period runs must never detach the course sitting in it.
        let school = Fixture.school()
        let file = RotationFile(
            version: 4,
            schoolYear: "2026-2027",
            publishedAt: Date(timeIntervalSince1970: 0),
            templates: [
                RotationFile.PublishedTemplate(name: "A Day", slots: [
                    RotationFile.PublishedSlot(label: "Period 1", start: "08:10", end: "08:55"),
                    RotationFile.PublishedSlot(label: "Period 2", start: "09:05", end: "09:50"),
                    RotationFile.PublishedSlot(label: "Lunch", start: "12:00", end: "12:40", instructional: false),
                    RotationFile.PublishedSlot(label: "Period 3", start: "13:00", end: "13:50")
                ])
            ],
            days: []
        )

        let (merged, report) = RotationMerge.apply(file, to: school.configuration)
        let engine = ScheduleEngine(configuration: merged)

        XCTAssertEqual(report.templatesUpdated, ["A Day"])
        XCTAssertTrue(report.templatesAdded.isEmpty)

        // 08:10 is the new first bell, and Talmud is still in it.
        guard case .inPeriod(let current, _) = engine.snapshot(at: Fixture.at("2026-09-08", "08:12")).status else {
            return XCTFail("Expected the new bell time to be live")
        }
        XCTAssertEqual(current.title, "Talmud")
        XCTAssertEqual(current.room, "305")
    }

    func testAPublishedTemplateThatDoesNotExistLocallyIsCreated() {
        let school = Fixture.school()
        let file = RotationFile(
            version: 5,
            schoolYear: "2026-2027",
            publishedAt: Date(timeIntervalSince1970: 0),
            templates: [
                RotationFile.PublishedTemplate(name: "Fast Day", slots: [
                    RotationFile.PublishedSlot(label: "Period 1", start: "08:15", end: "08:55")
                ])
            ],
            days: [RotationFile.PublishedDay(date: "2026-09-10", template: "Fast Day")]
        )

        let (merged, report) = RotationMerge.apply(file, to: school.configuration)
        XCTAssertEqual(report.templatesAdded, ["Fast Day"])
        XCTAssertTrue(report.unresolvedTemplateNames.isEmpty)

        let engine = ScheduleEngine(configuration: merged)
        XCTAssertEqual(engine.schoolDay(for: Fixture.ymd("2026-09-10")).templateName, "Fast Day")
    }

    func testADateNamingAnUnknownTemplateIsLeftAloneAndReported() {
        // Guessing here would put a student in the wrong room. Reporting it puts
        // a fixable message in Settings instead.
        let school = Fixture.school()
        let file = RotationFile(
            version: 6,
            schoolYear: "2026-2027",
            publishedAt: Date(timeIntervalSince1970: 0),
            days: [RotationFile.PublishedDay(date: "2026-09-08", template: "Yom Iyun")]
        )

        let (merged, report) = RotationMerge.apply(file, to: school.configuration)
        XCTAssertEqual(report.unresolvedTemplateNames, ["Yom Iyun"])
        XCTAssertEqual(report.datesUpdated, 0)

        let engine = ScheduleEngine(configuration: merged)
        XCTAssertEqual(
            engine.schoolDay(for: Fixture.ymd("2026-09-08")).templateName,
            "A Day",
            "The weekday default still applies"
        )
    }

    func testTemplateNamesMatchCaseInsensitively() {
        let school = Fixture.school()
        let file = RotationFile(
            version: 7,
            schoolYear: "2026-2027",
            publishedAt: Date(timeIntervalSince1970: 0),
            days: [RotationFile.PublishedDay(date: "2026-09-08", template: "friday")]
        )
        let (merged, _) = RotationMerge.apply(file, to: school.configuration)
        XCTAssertEqual(
            ScheduleEngine(configuration: merged).schoolDay(for: Fixture.ymd("2026-09-08")).templateName,
            "Friday"
        )
    }

    func testReapplyingTheSameFileChangesNothing() {
        let school = Fixture.school()
        let file = RotationFile(
            version: 8,
            schoolYear: "2026-2027",
            publishedAt: Date(timeIntervalSince1970: 0),
            days: [RotationFile.PublishedDay(date: "2026-09-08", template: "Friday")]
        )
        let (once, _) = RotationMerge.apply(file, to: school.configuration)
        let (twice, secondReport) = RotationMerge.apply(file, to: once)

        XCTAssertEqual(once.calendarDays, twice.calendarDays)
        XCTAssertTrue(secondReport.isEmpty)
    }

    func testSignedEnvelopeDecodesTheExactBytesThatWereSigned() throws {
        let file = RotationFile(
            version: 9,
            schoolYear: "2026-2027",
            publishedAt: Date(timeIntervalSince1970: 1_757_000_000),
            days: [RotationFile.PublishedDay(date: "2026-09-08", template: "Friday")]
        )
        let data = try RotationFile.encoder.encode(file)
        let envelope = SignedRotationFile(
            payload: data.base64EncodedString(),
            signature: Data("not-a-real-signature".utf8).base64EncodedString(),
            keyID: "2026-rotation"
        )

        XCTAssertEqual(envelope.payloadData, data)
        let decoded = try envelope.decodePayload()
        XCTAssertEqual(decoded.version, 9)
        XCTAssertEqual(decoded.days.first?.template, "Friday")
    }

    func testMalformedPayloadIsRejected() {
        let envelope = SignedRotationFile(payload: "not base64!!!", signature: "", keyID: "k")
        XCTAssertThrowsError(try envelope.decodePayload()) { error in
            XCTAssertEqual(error as? RotationFileError, .malformedPayload)
        }
    }
}

final class DefaultBellScheduleTests: XCTestCase {

    func testSeedConfigurationProducesAWorkingWeek() {
        let engine = ScheduleEngine(configuration: DefaultBellSchedule.seedConfiguration())

        XCTAssertTrue(engine.schoolDay(for: Fixture.ymd("2026-09-08")).hasClasses, "Tuesday")
        XCTAssertEqual(engine.schoolDay(for: Fixture.ymd("2026-09-11")).templateName, "Friday")
        XCTAssertTrue(engine.schoolDay(for: Fixture.ymd("2026-09-12")).isNoSchool, "Saturday")
        XCTAssertTrue(engine.schoolDay(for: Fixture.ymd("2026-09-13")).isNoSchool, "Sunday")
    }

    func testNoDefaultTemplateHasOverlappingOrBackwardsSlots() {
        for template in DefaultBellSchedule.allTemplates() {
            XCTAssertFalse(template.slots.isEmpty, "\(template.name) is empty")
            for slot in template.slots {
                XCTAssertGreaterThan(
                    slot.end, slot.start,
                    "\(template.name) / \(slot.label) ends at or before it starts"
                )
            }
            for index in template.slots.indices.dropFirst() {
                XCTAssertGreaterThanOrEqual(
                    template.slots[index].start, template.slots[index - 1].end,
                    "\(template.name): \(template.slots[index].label) overlaps \(template.slots[index - 1].label)"
                )
            }
        }
    }

    func testLunchAndTefillahAreNotInstructional() {
        // Ping notifications are muted during instructional periods only. If
        // lunch were instructional the feature would be silent exactly when it
        // is meant to be used.
        let regular = DefaultBellSchedule.regularDay()
        XCTAssertEqual(regular.slots.first { $0.label == "Lunch" }?.isInstructional, false)
        XCTAssertEqual(regular.slots.first { $0.label == "Mincha" }?.isInstructional, false)
        XCTAssertEqual(regular.slots.first { $0.label == "Period 1" }?.isInstructional, true)
    }

    func testARotationBuiltFromOneTemplateGivesEveryLetterItsOwnSlotIdentities() {
        // Otherwise a course assigned to A Day Period 1 would appear on every
        // other letter day too.
        let letters = DefaultBellSchedule.rotationTemplates(basedOn: DefaultBellSchedule.regularDay())
        XCTAssertEqual(letters.map(\.name), ["A Day", "B Day", "C Day", "D Day", "E Day"])

        let allSlotIDs = letters.flatMap { $0.slots.map(\.id) }
        XCTAssertEqual(Set(allSlotIDs).count, allSlotIDs.count)
    }
}
