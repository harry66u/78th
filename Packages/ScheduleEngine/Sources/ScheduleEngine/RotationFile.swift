import Foundation

/// The shared rotation file: the official day-type calendar for the whole
/// school, published to the backend and pulled by every device.
///
/// It carries bell times and which template applies on which date. It never
/// carries anyone's courses, so it stays a public document and the student's own
/// schedule stays on the phone. This is what keeps the app correct after the
/// student who built it graduates.
public struct RotationFile: Codable, Hashable, Sendable {

    /// Monotonic. A device ignores a file whose version is not greater than the
    /// one it already applied.
    public var version: Int
    /// "2026-2027", shown in Settings so a student can see what they are on.
    public var schoolYear: String
    public var publishedAt: Date
    /// Official bell times. Optional: a file may push only the rotation and
    /// leave bell times alone.
    public var templates: [PublishedTemplate]?
    public var days: [PublishedDay]

    public init(
        version: Int,
        schoolYear: String,
        publishedAt: Date,
        templates: [PublishedTemplate]? = nil,
        days: [PublishedDay]
    ) {
        self.version = version
        self.schoolYear = schoolYear
        self.publishedAt = publishedAt
        self.templates = templates
        self.days = days
    }

    /// Templates are referenced by name, never by UUID, because the file is
    /// authored centrally and every device has its own local identifiers.
    public struct PublishedTemplate: Codable, Hashable, Sendable {
        public var name: String
        public var slots: [PublishedSlot]

        public init(name: String, slots: [PublishedSlot]) {
            self.name = name
            self.slots = slots
        }
    }

    public struct PublishedSlot: Codable, Hashable, Sendable {
        public var label: String
        /// "08:15"
        public var start: String
        public var end: String
        public var instructional: Bool?

        public init(label: String, start: String, end: String, instructional: Bool? = nil) {
            self.label = label
            self.start = start
            self.end = end
            self.instructional = instructional
        }
    }

    public struct PublishedDay: Codable, Hashable, Sendable {
        /// "2026-09-08"
        public var date: String
        /// Template name, matched case-insensitively against local templates.
        public var template: String?
        public var noSchool: Bool?
        public var note: String?

        public init(date: String, template: String? = nil, noSchool: Bool? = nil, note: String? = nil) {
            self.date = date
            self.template = template
            self.noSchool = noSchool
            self.note = note
        }
    }
}

/// A rotation file plus its detached signature.
///
/// Verification itself lives in the app target, where CryptoKit is available.
/// The engine only needs to stay honest about the fact that an unverified file
/// must never be applied.
public struct SignedRotationFile: Codable, Hashable, Sendable {
    /// Base64 of the exact UTF-8 JSON bytes that were signed. Decoding the
    /// payload rather than re-encoding the struct is what makes the signature
    /// check meaningful.
    public var payload: String
    /// Base64 Ed25519 signature over the decoded payload bytes.
    public var signature: String
    /// Which publishing key signed it, so a key can be rotated.
    public var keyID: String

    public init(payload: String, signature: String, keyID: String) {
        self.payload = payload
        self.signature = signature
        self.keyID = keyID
    }

    public func decodePayload(using decoder: JSONDecoder = RotationFile.decoder) throws -> RotationFile {
        guard let data = Data(base64Encoded: payload) else {
            throw RotationFileError.malformedPayload
        }
        return try decoder.decode(RotationFile.self, from: data)
    }

    public var payloadData: Data? { Data(base64Encoded: payload) }
    public var signatureData: Data? { Data(base64Encoded: signature) }
}

public enum RotationFileError: Error, Equatable {
    case malformedPayload
    case badSignature
    case unknownKey(String)
    case notNewer(local: Int, incoming: Int)
}

extension RotationFile {

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

// MARK: - Merging

/// What a merge changed, surfaced in Settings so an update is never silent.
public struct RotationMergeReport: Hashable, Sendable {
    public var appliedVersion: Int
    public var datesUpdated: Int
    public var templatesUpdated: [String]
    public var templatesAdded: [String]
    /// Dates that named a template this device does not have and could not
    /// create. These are left untouched rather than guessed at.
    public var unresolvedTemplateNames: [String]

    public var isEmpty: Bool {
        datesUpdated == 0 && templatesUpdated.isEmpty && templatesAdded.isEmpty
    }
}

public enum RotationMerge {

    /// Applies an official rotation onto a local configuration.
    ///
    /// The rule that matters: a student's course assignments must survive. Slots
    /// are matched by label within a template so that updating a bell time keeps
    /// the same slot identity, and the courses sitting in those slots stay put.
    public static func apply(
        _ file: RotationFile,
        to configuration: ScheduleConfiguration
    ) -> (ScheduleConfiguration, RotationMergeReport) {

        var result = configuration
        var templatesUpdated: [String] = []
        var templatesAdded: [String] = []

        // 1. Bell times.
        for published in file.templates ?? [] {
            let existingIndex = result.templates.firstIndex {
                $0.name.compare(published.name, options: .caseInsensitive) == .orderedSame
            }

            if let index = existingIndex {
                let existing = result.templates[index]
                let merged = mergeSlots(published: published, into: existing)
                if merged.slots != existing.slots {
                    result.templates[index] = merged
                    templatesUpdated.append(published.name)
                }
            } else {
                let created = DayTemplate(
                    name: published.name,
                    slots: published.slots.compactMap(makeSlot)
                )
                guard !created.slots.isEmpty else { continue }
                result.templates.append(created)
                templatesAdded.append(published.name)
            }
        }

        // 2. Rotation. Official dated entries replace local ones for the same date.
        var byDate = Dictionary(
            result.calendarDays.map { ($0.date, $0) },
            uniquingKeysWith: { _, last in last }
        )
        var templateIDsByName: [String: UUID] = [:]
        for template in result.templates {
            templateIDsByName[template.name.lowercased()] = template.id
        }

        var datesUpdated = 0
        var unresolved: Set<String> = []

        for day in file.days {
            guard let date = YearMonthDay(iso8601: day.date) else { continue }

            if day.noSchool == true {
                let entry = CalendarDay(
                    date: date,
                    dayTemplateID: nil,
                    isNoSchool: true,
                    overrideNote: day.note,
                    droppedSlotIDs: []
                )
                if byDate[date] != entry { datesUpdated += 1 }
                byDate[date] = entry
                continue
            }

            guard let name = day.template else {
                // A note with no template: annotate without changing the day type.
                if var existing = byDate[date] {
                    if existing.overrideNote != day.note {
                        existing.overrideNote = day.note
                        byDate[date] = existing
                        datesUpdated += 1
                    }
                }
                continue
            }

            guard let templateID = templateIDsByName[name.lowercased()] else {
                unresolved.insert(name)
                continue
            }

            let entry = CalendarDay(
                date: date,
                dayTemplateID: templateID,
                isNoSchool: false,
                overrideNote: day.note,
                // Dropped slots are a personal, local edit and are not carried
                // across a rotation update for a date the file redefines.
                droppedSlotIDs: []
            )
            if byDate[date] != entry { datesUpdated += 1 }
            byDate[date] = entry
        }

        result.calendarDays = byDate.values.sorted { $0.date < $1.date }

        let report = RotationMergeReport(
            appliedVersion: file.version,
            datesUpdated: datesUpdated,
            templatesUpdated: templatesUpdated,
            templatesAdded: templatesAdded,
            unresolvedTemplateNames: unresolved.sorted()
        )
        return (result, report)
    }

    /// Rewrites a template's bell times from the published version, keeping the
    /// identity of any slot whose label the school still publishes.
    private static func mergeSlots(
        published: RotationFile.PublishedTemplate,
        into existing: DayTemplate
    ) -> DayTemplate {
        var byLabel: [String: PeriodSlot] = [:]
        for slot in existing.slots {
            byLabel[slot.label.lowercased()] = slot
        }

        let slots: [PeriodSlot] = published.slots.compactMap { publishedSlot in
            guard let start = TimeOfDay(publishedSlot.start),
                  let end = TimeOfDay(publishedSlot.end)
            else { return nil }

            let existingSlot = byLabel[publishedSlot.label.lowercased()]
            return PeriodSlot(
                id: existingSlot?.id ?? UUID(),
                label: publishedSlot.label,
                start: start,
                end: end,
                isInstructional: publishedSlot.instructional
                    ?? existingSlot?.isInstructional
                    ?? true
            )
        }

        guard !slots.isEmpty else { return existing }

        var updated = existing
        updated.setSlots(slots)
        return updated
    }

    private static func makeSlot(_ published: RotationFile.PublishedSlot) -> PeriodSlot? {
        guard let start = TimeOfDay(published.start), let end = TimeOfDay(published.end) else {
            return nil
        }
        return PeriodSlot(
            label: published.label,
            start: start,
            end: end,
            isInstructional: published.instructional ?? true
        )
    }
}
