import SwiftUI
import ScheduleEngine

/// Parsed output is never saved without the student confirming it.
///
/// This screen exists to make that confirmation meaningful: every period is
/// editable here, and anything the parser was unsure about is at the top rather
/// than buried.
struct ReviewImportView: View {

    @Environment(ScheduleStore.self) private var schedule
    @Environment(\.dismiss) private var dismiss

    @State private var working: ScheduleConfiguration
    @State private var issues: [ImportIssue]
    @State private var editing: EditingCell?

    private let courseCount: Int

    struct EditingCell: Identifiable {
        var id: UUID { slot.id }
        var templateID: UUID
        var slot: PeriodSlot
        var assignment: CourseAssignment?
    }

    init(result: ParsedSchedule) {
        _working = State(initialValue: result.configuration)
        _issues = State(initialValue: result.issues)
        self.courseCount = result.courseCount
    }

    var body: some View {
        List {
            Section {
                summaryRow
            }

            if !issues.isEmpty {
                Section {
                    ForEach(issues) { issue in
                        IssueRow(issue: issue) {
                            issues.removeAll { $0.id == issue.id }
                        }
                    }
                } header: {
                    Text("Check these \(issues.count)")
                } footer: {
                    Text("These are the lines the parser was not sure about. Fix them below, or dismiss the ones that do not matter.")
                }
            }

            ForEach(working.templates) { template in
                Section(template.name) {
                    ForEach(template.slots) { slot in
                        Button {
                            editing = EditingCell(
                                templateID: template.id,
                                slot: slot,
                                assignment: assignment(template.id, slot.id)
                            )
                        } label: {
                            ReviewSlotRow(slot: slot, assignment: assignment(template.id, slot.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Check it over")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    schedule.replaceSchedule(with: working)
                    dismiss()
                }
            }
        }
        .sheet(item: $editing) { cell in
            NavigationStack {
                CourseEditorSheet(
                    slotLabel: cell.slot.label,
                    timeRange: "\(cell.slot.start.description) \u{2013} \(cell.slot.end.description)",
                    courseName: cell.assignment?.courseName ?? "",
                    room: cell.assignment?.room ?? "",
                    teacher: cell.assignment?.teacher ?? "",
                    courseSuggestions: knownCourses,
                    roomSuggestions: knownRooms
                ) { course, room, teacher in
                    apply(course: course, room: room, teacher: teacher, to: cell)
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var summaryRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(working.templates.count) day \(working.templates.count == 1 ? "type" : "types"), \(courseCount) courses")
                .font(.headline)
            Text("Tap any period to fix it. Nothing is saved until you press Save.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var knownCourses: [String] {
        Array(Set(working.assignments.map(\.courseName).filter { !$0.isEmpty })).sorted()
    }

    private var knownRooms: [String] {
        Array(Set(working.assignments.map(\.room).filter { !$0.isEmpty })).sorted()
    }

    private func assignment(_ templateID: UUID, _ slotID: UUID) -> CourseAssignment? {
        working.assignments.first { $0.dayTemplateID == templateID && $0.periodSlotID == slotID }
    }

    private func apply(course: String, room: String, teacher: String, to cell: EditingCell) {
        let trimmed = course.trimmingCharacters(in: .whitespacesAndNewlines)
        working.assignments.removeAll {
            $0.dayTemplateID == cell.templateID && $0.periodSlotID == cell.slot.id
        }
        guard !trimmed.isEmpty else { return }

        let color = working.assignments
            .first { $0.courseName.compare(trimmed, options: .caseInsensitive) == .orderedSame }?
            .colorTag
            ?? working.assignments.count

        working.assignments.append(CourseAssignment(
            dayTemplateID: cell.templateID,
            periodSlotID: cell.slot.id,
            courseName: trimmed,
            room: room.trimmingCharacters(in: .whitespacesAndNewlines),
            teacher: teacher.isEmpty ? nil : teacher.trimmingCharacters(in: .whitespacesAndNewlines),
            colorTag: color
        ))
    }
}

private struct ReviewSlotRow: View {

    let slot: PeriodSlot
    let assignment: CourseAssignment?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(slot.start.description).font(.caption.weight(.semibold)).monospacedDigit()
                Text(slot.end.description).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(width: 46, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(assignment?.courseName ?? slot.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(assignment == nil ? .secondary : .primary)
                HStack(spacing: 8) {
                    if assignment != nil { Text(slot.label) }
                    if let room = assignment?.room, !room.isEmpty { Text("Room \(room)") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

private struct IssueRow: View {

    let issue: ImportIssue
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.orange)
                .font(.footnote)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.message)
                    .font(.footnote)
                if !issue.templateName.isEmpty {
                    Text(issue.templateName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private var symbol: String {
        switch issue.kind {
        case .unparsedLine: return "questionmark.circle"
        case .unreadableTime, .endsBeforeItStarts: return "clock.badge.exclamationmark"
        case .overlap: return "rectangle.2.swap"
        case .duplicateTemplateName: return "doc.on.doc"
        case .emptyTemplate: return "tray"
        }
    }
}

/// Shared by the review screen and the manual grid, so a cell edits the same way
/// wherever the student meets it.
struct CourseEditorSheet: View {

    @Environment(\.dismiss) private var dismiss

    let slotLabel: String
    let timeRange: String
    let courseSuggestions: [String]
    let roomSuggestions: [String]
    let onSave: (String, String, String) -> Void

    @State private var courseName: String
    @State private var room: String
    @State private var teacher: String

    init(
        slotLabel: String,
        timeRange: String,
        courseName: String,
        room: String,
        teacher: String,
        courseSuggestions: [String],
        roomSuggestions: [String],
        onSave: @escaping (String, String, String) -> Void
    ) {
        self.slotLabel = slotLabel
        self.timeRange = timeRange
        self.courseSuggestions = courseSuggestions
        self.roomSuggestions = roomSuggestions
        self.onSave = onSave
        _courseName = State(initialValue: courseName)
        _room = State(initialValue: room)
        _teacher = State(initialValue: teacher)
    }

    var body: some View {
        Form {
            Section {
                TextField("Course", text: $courseName)
                    .textInputAutocapitalization(.words)
                TextField("Room", text: $room)
                TextField("Teacher, optional", text: $teacher)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("\(slotLabel) \u{00B7} \(timeRange)")
            } footer: {
                Text("Leave the course blank to mark this period free.")
            }

            // The same course repeats across day types, so suggesting what has
            // already been typed is most of what makes the grid bearable.
            if !matchingCourses.isEmpty {
                Section("Already in your schedule") {
                    ForEach(matchingCourses, id: \.self) { suggestion in
                        Button(suggestion) { courseName = suggestion }
                    }
                }
            }

            if !matchingRooms.isEmpty {
                Section("Rooms you have used") {
                    ForEach(matchingRooms, id: \.self) { suggestion in
                        Button(suggestion) { room = suggestion }
                    }
                }
            }
        }
        .navigationTitle(slotLabel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(courseName, room, teacher)
                    dismiss()
                }
            }
        }
    }

    private var matchingCourses: [String] {
        suggestions(courseSuggestions, matching: courseName, currentlyEqualTo: courseName)
    }

    private var matchingRooms: [String] {
        suggestions(roomSuggestions, matching: room, currentlyEqualTo: room)
    }

    private func suggestions(_ all: [String], matching text: String, currentlyEqualTo current: String) -> [String] {
        let query = text.trimmingCharacters(in: .whitespaces)
        let filtered = query.isEmpty
            ? all
            : all.filter { $0.localizedCaseInsensitiveContains(query) && $0 != current }
        return Array(filtered.prefix(5))
    }
}
