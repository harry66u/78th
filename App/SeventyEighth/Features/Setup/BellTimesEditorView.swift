import SwiftUI
import ScheduleEngine

/// Editing the bell times themselves, separately from which course sits in
/// which slot. Most students never open this; the ones who do are the reason
/// the app can be right for everyone.
struct BellTimesEditorView: View {

    @Environment(ScheduleStore.self) private var schedule
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTemplateID: UUID?
    @State private var editingSlot: EditingSlot?
    @State private var isAddingTemplate = false
    @State private var newTemplateName = ""

    struct EditingSlot: Identifiable {
        var id: UUID { slot.id }
        var slot: PeriodSlot
        var templateID: UUID
        var isNew: Bool
    }

    var body: some View {
        List {
            Section("Day type") {
                Picker("Day type", selection: Binding(
                    get: { selectedTemplateID ?? schedule.configuration.templates.first?.id },
                    set: { selectedTemplateID = $0 }
                )) {
                    ForEach(schedule.configuration.templates) { template in
                        Text(template.name).tag(Optional(template.id))
                    }
                }
                .pickerStyle(.menu)

                Button("Add a day type") { isAddingTemplate = true }
            }

            if let template = currentTemplate {
                Section("Periods") {
                    ForEach(template.slots) { slot in
                        Button {
                            editingSlot = EditingSlot(slot: slot, templateID: template.id, isNew: false)
                        } label: {
                            HStack {
                                Text(slot.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(slot.start.description) \u{2013} \(slot.end.description)")
                                    .font(.subheadline)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            schedule.deleteSlot(id: template.slots[index].id, in: template.id)
                        }
                    }

                    Button("Add a period") {
                        let start = template.slots.last?.end ?? TimeOfDay(hour: 8, minute: 0)
                        editingSlot = EditingSlot(
                            slot: PeriodSlot(
                                label: "Period \(template.slots.count + 1)",
                                start: TimeOfDay(minutes: start.minutes + 5),
                                end: TimeOfDay(minutes: start.minutes + 50)
                            ),
                            templateID: template.id,
                            isNew: true
                        )
                    }
                }

                Section {
                    Button("Delete \"\(template.name)\"", role: .destructive) {
                        schedule.deleteTemplate(id: template.id)
                        selectedTemplateID = schedule.configuration.templates.first?.id
                    }
                }
            }
        }
        .navigationTitle("Bell times")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    schedule.confirmBellTimes()
                    dismiss()
                }
            }
        }
        .sheet(item: $editingSlot) { editing in
            NavigationStack {
                SlotEditorSheet(slot: editing.slot) { updated in
                    schedule.upsertSlot(updated, in: editing.templateID)
                }
            }
            .presentationDetents([.medium])
        }
        .alert("New day type", isPresented: $isAddingTemplate) {
            TextField("Name, for example B Day", text: $newTemplateName)
            Button("Cancel", role: .cancel) { newTemplateName = "" }
            Button("Add") {
                let name = newTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                let created = schedule.addTemplate(named: name, copying: currentTemplate)
                selectedTemplateID = created?.id
                newTemplateName = ""
            }
        } message: {
            Text("It starts as a copy of the day type you are looking at.")
        }
    }

    private var currentTemplate: DayTemplate? {
        let id = selectedTemplateID ?? schedule.configuration.templates.first?.id
        return schedule.configuration.templates.first { $0.id == id }
    }
}

/// One period's label and times.
struct SlotEditorSheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var start: Date
    @State private var end: Date
    @State private var isInstructional: Bool

    private let original: PeriodSlot
    private let onSave: (PeriodSlot) -> Void

    init(slot: PeriodSlot, onSave: @escaping (PeriodSlot) -> Void) {
        self.original = slot
        self.onSave = onSave
        _label = State(initialValue: slot.label)
        _start = State(initialValue: SlotEditorSheet.date(from: slot.start))
        _end = State(initialValue: SlotEditorSheet.date(from: slot.end))
        _isInstructional = State(initialValue: slot.isInstructional)
    }

    var body: some View {
        Form {
            TextField("Label", text: $label)
            DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
            DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)

            Toggle("Counts as class time", isOn: $isInstructional)
            Text("Ping alerts are muted during class time. Turn this off for lunch, davening, and frees.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if endsBeforeItStarts {
                Label("The end time is before the start time.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }
        }
        .navigationTitle(original.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(PeriodSlot(
                        id: original.id,
                        label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                        start: SlotEditorSheet.time(from: start),
                        end: SlotEditorSheet.time(from: end),
                        isInstructional: isInstructional
                    ))
                    dismiss()
                }
                .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty || endsBeforeItStarts)
            }
        }
    }

    private var endsBeforeItStarts: Bool {
        SlotEditorSheet.time(from: end).minutes <= SlotEditorSheet.time(from: start).minutes
    }

    private static func date(from time: TimeOfDay) -> Date {
        var components = DateComponents()
        components.year = 2000
        components.month = 1
        components.day = 1
        components.hour = time.hour
        components.minute = time.minute
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }

    private static func time(from date: Date) -> TimeOfDay {
        let components = Calendar(identifier: .gregorian).dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }
}

#Preview {
    NavigationStack { BellTimesEditorView() }
        .environment(PreviewSupport.store())
}
