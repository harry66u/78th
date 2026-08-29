import SwiftUI
import ScheduleEngine

/// Path C: the manual grid. The fallback that must exist, because a parser that
/// fails on one student's schedule cannot be the only way in.
///
/// Day templates are columns, period slots are rows. Tapping a cell opens the
/// same editor the review screen uses, with autocomplete from what has already
/// been typed.
struct ManualGridView: View {

    @Environment(ScheduleStore.self) private var schedule
    @State private var editing: Cell?

    struct Cell: Identifiable {
        var id: String { "\(templateID)-\(slot.id)" }
        var templateID: UUID
        var templateName: String
        var slot: PeriodSlot
        var assignment: CourseAssignment?
    }

    private let columnWidth: CGFloat = 116
    private let timeColumnWidth: CGFloat = 54

    var body: some View {
        Group {
            if templates.isEmpty {
                ContentUnavailableView(
                    "No day types yet",
                    systemImage: "square.grid.3x3",
                    description: Text("Add a day type in Bell times first.")
                )
            } else {
                grid
            }
        }
        .navigationTitle("Grid")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { cell in
            NavigationStack {
                CourseEditorSheet(
                    slotLabel: "\(cell.templateName) \u{00B7} \(cell.slot.label)",
                    timeRange: "\(cell.slot.start.description) \u{2013} \(cell.slot.end.description)",
                    courseName: cell.assignment?.courseName ?? "",
                    room: cell.assignment?.room ?? "",
                    teacher: cell.assignment?.teacher ?? "",
                    courseSuggestions: schedule.engine.knownCourseNames,
                    roomSuggestions: schedule.engine.knownRooms
                ) { course, room, teacher in
                    schedule.setCourse(
                        templateID: cell.templateID,
                        slotID: cell.slot.id,
                        courseName: course,
                        room: room,
                        teacher: teacher.isEmpty ? nil : teacher
                    )
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var templates: [DayTemplate] { schedule.configuration.templates }

    /// Rows are the union of every day type's period labels, so a Friday with
    /// fewer periods leaves gaps rather than shifting everything up a row.
    private var rowLabels: [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for template in templates {
            for slot in template.slots where seen.insert(slot.label).inserted {
                ordered.append(slot.label)
            }
        }
        return ordered
    }

    @ViewBuilder
    private var grid: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(rowLabels, id: \.self) { label in
                        HStack(spacing: 0) {
                            Text(label)
                                .font(.caption.weight(.semibold))
                                .frame(width: timeColumnWidth, alignment: .leading)
                                .padding(.leading, 4)

                            ForEach(templates) { template in
                                cellView(template: template, label: label)
                                    .frame(width: columnWidth, height: 60)
                            }
                        }
                        Divider()
                    }
                } header: {
                    HStack(spacing: 0) {
                        Text("")
                            .frame(width: timeColumnWidth)
                        ForEach(templates) { template in
                            Text(template.name)
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(width: columnWidth, height: 34)
                        }
                    }
                    .background(.bar)
                }
            }
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func cellView(template: DayTemplate, label: String) -> some View {
        if let slot = template.slots.first(where: { $0.label == label }) {
            let assignment = schedule.engine.assignment(dayTemplateID: template.id, periodSlotID: slot.id)
            Button {
                editing = Cell(
                    templateID: template.id,
                    templateName: template.name,
                    slot: slot,
                    assignment: assignment
                )
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(assignment?.courseName ?? "\u{2014}")
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(assignment == nil ? Color.secondary : .primary)
                    if let room = assignment?.room, !room.isEmpty {
                        Text(room)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(slot.start.description)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(
                    (assignment.map { Theme.courseColor($0.colorTag).opacity(0.14) } ?? Color.clear),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .padding(2)
            }
            .buttonStyle(.plain)
        } else {
            Color.clear
        }
    }
}

#Preview {
    NavigationStack { ManualGridView() }
        .environment(PreviewSupport.store())
}
