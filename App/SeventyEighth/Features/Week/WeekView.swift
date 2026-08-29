import SwiftUI
import ScheduleEngine

/// Horizontal scroll by day template, read only, for planning.
struct WeekView: View {

    @Environment(ScheduleStore.self) private var schedule
    @State private var selectedTemplateID: UUID?

    var body: some View {
        Group {
            if schedule.configuration.templates.isEmpty {
                ContentUnavailableView(
                    "No day types yet",
                    systemImage: "calendar",
                    description: Text("Add your schedule and your day types show up here.")
                )
            } else {
                content
            }
        }
        .navigationTitle("Week")
    }

    private var templates: [DayTemplate] { schedule.configuration.templates }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(templates) { template in
                        let isSelected = template.id == (selectedTemplateID ?? templates.first?.id)
                        Button {
                            withAnimation(.snappy) { selectedTemplateID = template.id }
                        } label: {
                            Text(template.name)
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(isSelected ? Theme.courseColor(0) : .secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            Divider()

            if let template = templates.first(where: { $0.id == (selectedTemplateID ?? templates.first?.id) }) {
                List {
                    Section {
                        ForEach(template.slots) { slot in
                            TemplateSlotRow(
                                slot: slot,
                                assignment: schedule.engine.assignment(dayTemplateID: template.id, periodSlotID: slot.id)
                            )
                        }
                    } footer: {
                        Text("\(template.slots.count) periods \u{00B7} \(dayLength(template))")
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func dayLength(_ template: DayTemplate) -> String {
        guard let first = template.slots.first, let last = template.slots.last else { return "" }
        return "\(first.start.description) to \(last.end.description)"
    }
}

struct TemplateSlotRow: View {

    let slot: PeriodSlot
    let assignment: CourseAssignment?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(slot.start.description)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                Text(slot.end.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(width: 46, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(assignment.map { Theme.courseColor($0.colorTag) } ?? Color.secondary.opacity(0.4))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(assignment?.courseName ?? slot.label)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    if assignment != nil {
                        Text(slot.label)
                    }
                    if let room = assignment?.room, !room.isEmpty {
                        Text("Room \(room)")
                    }
                    if let teacher = assignment?.teacher, !teacher.isEmpty {
                        Text(teacher)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if !slot.isInstructional {
                Image(systemName: "cup.and.saucer")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack { WeekView() }
        .environment(PreviewSupport.store())
}
