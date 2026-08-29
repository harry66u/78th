import Foundation

/// The JSON contract the paste and photo importers hold the model to.
///
/// The shape is fixed by the build spec. Parsing is deliberately forgiving on
/// the way in and strict on the way out: anything the model returns that does
/// not survive validation becomes a line in `unparsed`, which the review screen
/// puts in front of the student. Parsed output is never saved without
/// confirmation.
public struct ScheduleImportPayload: Codable, Hashable, Sendable {

    public var dayTemplates: [ImportedDayTemplate]
    /// Lines the model could not confidently interpret.
    public var unparsed: [String]

    public init(dayTemplates: [ImportedDayTemplate] = [], unparsed: [String] = []) {
        self.dayTemplates = dayTemplates
        self.unparsed = unparsed
    }

    private enum CodingKeys: String, CodingKey {
        case dayTemplates, unparsed
    }

    /// Tolerant of a model that omits a key entirely.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.dayTemplates = try container.decodeIfPresent([ImportedDayTemplate].self, forKey: .dayTemplates) ?? []
        self.unparsed = try container.decodeIfPresent([String].self, forKey: .unparsed) ?? []
    }
}

public struct ImportedDayTemplate: Codable, Hashable, Sendable {
    public var name: String
    public var slots: [ImportedSlot]

    public init(name: String, slots: [ImportedSlot]) {
        self.name = name
        self.slots = slots
    }
}

public struct ImportedSlot: Codable, Hashable, Sendable {
    public var label: String
    /// "08:15"
    public var start: String
    public var end: String
    public var course: String?
    public var room: String?
    public var teacher: String?

    public init(
        label: String,
        start: String,
        end: String,
        course: String? = nil,
        room: String? = nil,
        teacher: String? = nil
    ) {
        self.label = label
        self.start = start
        self.end = end
        self.course = course
        self.room = room
        self.teacher = teacher
    }
}

/// A problem worth showing the student on the review screen. None of these
/// block saving: the student is the authority, and a schedule they can fix by
/// hand beats an import that refuses to finish.
public struct ImportIssue: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case unparsedLine
        case unreadableTime
        case endsBeforeItStarts
        case overlap(otherLabel: String)
        case duplicateTemplateName
        case emptyTemplate
    }

    public var id: String { "\(templateName)|\(slotLabel ?? "")|\(message)" }
    public var kind: Kind
    public var templateName: String
    public var slotLabel: String?
    public var message: String
}

/// Turns a model response into a `ScheduleConfiguration`, collecting everything
/// that looked wrong along the way.
public enum ScheduleImporter {

    public struct Result: Sendable {
        public var configuration: ScheduleConfiguration
        public var issues: [ImportIssue]
        /// Slots that produced a course, for the review screen's summary count.
        public var courseCount: Int
    }

    /// Strips markdown fences and surrounding prose before decoding, because a
    /// model told not to emit fences will occasionally emit fences anyway.
    public static func decode(_ raw: String) throws -> ScheduleImportPayload {
        let cleaned = extractJSONObject(from: raw)
        guard let data = cleaned.data(using: .utf8) else {
            throw ImportDecodingError.notUTF8
        }
        return try JSONDecoder().decode(ScheduleImportPayload.self, from: data)
    }

    public enum ImportDecodingError: Error, Equatable {
        case notUTF8
        case noJSONObjectFound
    }

    /// Returns the substring from the first `{` to the last `}`.
    public static func extractJSONObject(from raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("```") {
            // Drop the opening fence and its optional language tag.
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
            if let closing = text.range(of: "```", options: .backwards) {
                text = String(text[text.startIndex..<closing.lowerBound])
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let first = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}"), first < last else {
            return text
        }
        return String(text[first...last])
    }

    /// Converts a decoded payload into local entities.
    ///
    /// `existing` supplies the weekday mapping and time zone so that an import
    /// run twice does not lose the student's rotation.
    public static func makeConfiguration(
        from payload: ScheduleImportPayload,
        existing: ScheduleConfiguration = ScheduleConfiguration()
    ) -> Result {

        var issues: [ImportIssue] = []
        var templates: [DayTemplate] = []
        var assignments: [CourseAssignment] = []
        var seenNames: Set<String> = []

        for line in payload.unparsed where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(ImportIssue(
                kind: .unparsedLine,
                templateName: "",
                slotLabel: nil,
                message: line
            ))
        }

        for imported in payload.dayTemplates {
            let name = imported.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let templateName = name.isEmpty ? "Untitled Day" : name

            if !seenNames.insert(templateName.lowercased()).inserted {
                issues.append(ImportIssue(
                    kind: .duplicateTemplateName,
                    templateName: templateName,
                    slotLabel: nil,
                    message: "Two day types are both called \"\(templateName)\"."
                ))
            }

            var slots: [PeriodSlot] = []
            var pending: [(slot: PeriodSlot, imported: ImportedSlot)] = []

            for importedSlot in imported.slots {
                let label = importedSlot.label.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let start = TimeOfDay(importedSlot.start), let end = TimeOfDay(importedSlot.end) else {
                    issues.append(ImportIssue(
                        kind: .unreadableTime,
                        templateName: templateName,
                        slotLabel: label.isEmpty ? nil : label,
                        message: "Could not read \"\(importedSlot.start)\" to \"\(importedSlot.end)\"."
                    ))
                    continue
                }

                guard end > start else {
                    issues.append(ImportIssue(
                        kind: .endsBeforeItStarts,
                        templateName: templateName,
                        slotLabel: label.isEmpty ? nil : label,
                        message: "\(label.isEmpty ? "A period" : label) ends at or before it starts."
                    ))
                    continue
                }

                let courseName = importedSlot.course?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let slot = PeriodSlot(
                    label: label.isEmpty ? "Period" : label,
                    start: start,
                    end: end,
                    isInstructional: isInstructional(label: label, course: courseName)
                )
                slots.append(slot)
                pending.append((slot, importedSlot))
            }

            guard !slots.isEmpty else {
                issues.append(ImportIssue(
                    kind: .emptyTemplate,
                    templateName: templateName,
                    slotLabel: nil,
                    message: "\"\(templateName)\" had no readable periods."
                ))
                continue
            }

            let template = DayTemplate(name: templateName, slots: slots)
            templates.append(template)

            // Overlaps are reported, not corrected. A schedule with a genuine
            // overlap exists, and silently moving a bell would be worse.
            let sorted = template.slots
            for index in sorted.indices.dropFirst() {
                let previous = sorted[index - 1]
                let slot = sorted[index]
                if slot.start < previous.end {
                    issues.append(ImportIssue(
                        kind: .overlap(otherLabel: previous.label),
                        templateName: templateName,
                        slotLabel: slot.label,
                        message: "\(slot.label) starts before \(previous.label) ends."
                    ))
                }
            }

            for entry in pending {
                let courseName = entry.imported.course?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !courseName.isEmpty else { continue }
                assignments.append(CourseAssignment(
                    dayTemplateID: template.id,
                    periodSlotID: entry.slot.id,
                    courseName: courseName,
                    room: entry.imported.room?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                    teacher: entry.imported.teacher?.trimmingCharacters(in: .whitespacesAndNewlines),
                    colorTag: 0
                ))
            }
        }

        // One colour per distinct course, stable across day templates so a
        // course looks the same everywhere it appears.
        var colorByCourse: [String: Int] = [:]
        for index in assignments.indices {
            let key = assignments[index].courseName.lowercased()
            if let existingColor = colorByCourse[key] {
                assignments[index].colorTag = existingColor
            } else {
                let color = colorByCourse.count
                colorByCourse[key] = color
                assignments[index].colorTag = color
            }
        }

        let configuration = ScheduleConfiguration(
            templates: templates,
            assignments: assignments,
            calendarDays: existing.calendarDays,
            weekdayDefaults: remapWeekdayDefaults(existing: existing, newTemplates: templates),
            timeZoneIdentifier: existing.timeZoneIdentifier,
            localeIdentifier: existing.localeIdentifier
        )

        return Result(
            configuration: configuration,
            issues: issues,
            courseCount: Set(assignments.map(\.courseName)).count
        )
    }

    /// Keeps the weekday mapping pointing at same-named templates after a
    /// reimport, and otherwise falls back to Monday-to-Friday over whatever
    /// templates came back.
    private static func remapWeekdayDefaults(
        existing: ScheduleConfiguration,
        newTemplates: [DayTemplate]
    ) -> [Int: UUID] {
        guard !newTemplates.isEmpty else { return [:] }

        var namesToID: [String: UUID] = [:]
        for template in newTemplates {
            namesToID[template.name.lowercased()] = template.id
        }

        var remapped: [Int: UUID] = [:]
        for (weekday, oldID) in existing.weekdayDefaults {
            guard let oldTemplate = existing.templates.first(where: { $0.id == oldID }),
                  let newID = namesToID[oldTemplate.name.lowercased()]
            else { continue }
            remapped[weekday] = newID
        }
        guard remapped.isEmpty else { return remapped }

        // Monday through Friday, cycling through whatever the import produced.
        for (offset, weekday) in (2...6).enumerated() {
            remapped[weekday] = newTemplates[offset % newTemplates.count].id
        }
        return remapped
    }

    /// Lunch, davening, and free periods are not instructional, which is what
    /// keeps ping notifications from being muted through the exact periods the
    /// feature exists for.
    private static let nonInstructionalLabels = [
        "lunch", "break", "recess", "free", "mincha", "davening", "tefillah",
        "tefilla", "shacharit", "minyan", "advisory", "assembly", "homeroom",
        "dismissal", "arrival", "study hall"
    ]

    public static func isInstructional(label: String, course: String) -> Bool {
        let haystack = "\(label) \(course)".lowercased()
        return !nonInstructionalLabels.contains { haystack.contains($0) }
    }
}
