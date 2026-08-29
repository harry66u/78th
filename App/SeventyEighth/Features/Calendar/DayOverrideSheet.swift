import SwiftUI
import ScheduleEngine

/// One date's override: which day type, whether there is school, and which
/// periods were dropped.
struct DayOverrideSheet: View {

    @Environment(ScheduleStore.self) private var schedule
    @Environment(\.dismiss) private var dismiss

    let date: YearMonthDay

    @State private var templateID: UUID?
    @State private var isNoSchool = false
    @State private var note = ""
    @State private var dropped: Set<UUID> = []
    @State private var didLoad = false

    var body: some View {
        Form {
            Section {
                Toggle("No school", isOn: $isNoSchool)

                if !isNoSchool {
                    Picker("Day type", selection: $templateID) {
                        Text("Use the normal week").tag(UUID?.none)
                        ForEach(schedule.configuration.templates) { template in
                            Text(template.name).tag(Optional(template.id))
                        }
                    }
                }

                TextField("Note, for example Assembly", text: $note)
            } header: {
                Text(title)
            } footer: {
                Text("The note shows on Today and on the medium widget.")
            }

            if !isNoSchool, let template = effectiveTemplate {
                Section {
                    ForEach(template.slots) { slot in
                        Toggle(isOn: Binding(
                            get: { !dropped.contains(slot.id) },
                            set: { keep in
                                if keep { dropped.remove(slot.id) } else { dropped.insert(slot.id) }
                            }
                        )) {
                            HStack {
                                Text(courseName(template: template, slot: slot))
                                Spacer()
                                Text(slot.start.description)
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Periods running this day")
                } footer: {
                    Text("Turn off any period that was dropped. The countdown skips them.")
                }
            }

            Section {
                Button("Clear this day", role: .destructive) {
                    schedule.clearDay(date)
                    dismiss()
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    schedule.setDay(
                        date,
                        templateID: isNoSchool ? nil : templateID,
                        isNoSchool: isNoSchool,
                        note: note.isEmpty ? nil : note,
                        droppedSlotIDs: isNoSchool ? [] : dropped
                    )
                    dismiss()
                }
            }
        }
        .onAppear(perform: loadOnce)
    }

    private var title: String {
        ScheduleFormatting.mediumDay(
            date.startOfDay(in: schedule.configuration.calendar),
            timeZone: schedule.timeZone
        )
    }

    private var effectiveTemplate: DayTemplate? {
        if let templateID {
            return schedule.configuration.templates.first { $0.id == templateID }
        }
        let weekday = date.weekday(in: schedule.configuration.calendar)
        guard let fallback = schedule.configuration.weekdayDefaults[weekday] else { return nil }
        return schedule.configuration.templates.first { $0.id == fallback }
    }

    private func courseName(template: DayTemplate, slot: PeriodSlot) -> String {
        schedule.engine.assignment(dayTemplateID: template.id, periodSlotID: slot.id)?.courseName ?? slot.label
    }

    private func loadOnce() {
        guard !didLoad else { return }
        didLoad = true
        guard let existing = schedule.configuration.calendarDays.first(where: { $0.date == date }) else {
            let day = schedule.engine.schoolDay(for: date)
            isNoSchool = day.isNoSchool
            return
        }
        templateID = existing.dayTemplateID
        isNoSchool = existing.isNoSchool
        note = existing.overrideNote ?? ""
        dropped = existing.droppedSlotIDs
    }
}

/// Repeat weekly, apply to a date range, mark no school: the tools that make a
/// year's rotation a two-minute job instead of a two-hour one.
struct BulkRotationSheet: View {

    @Environment(ScheduleStore.self) private var schedule
    @Environment(\.dismiss) private var dismiss

    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(60 * 60 * 24 * 7)
    @State private var templateID: UUID?
    @State private var isNoSchool = false
    @State private var note = ""
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]

    var body: some View {
        Form {
            Section("Dates") {
                DatePicker("From", selection: $start, displayedComponents: .date)
                DatePicker("Through", selection: $end, displayedComponents: .date)
            }

            Section("Weekdays") {
                HStack(spacing: 6) {
                    ForEach(1...7, id: \.self) { weekday in
                        Button {
                            if weekdays.contains(weekday) { weekdays.remove(weekday) } else { weekdays.insert(weekday) }
                        } label: {
                            Text(symbol(weekday))
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.bordered)
                        .tint(weekdays.contains(weekday) ? Theme.courseColor(0) : .secondary)
                    }
                }
            }

            Section("What to set") {
                Toggle("No school", isOn: $isNoSchool)
                if !isNoSchool {
                    Picker("Day type", selection: $templateID) {
                        Text("Use the normal week").tag(UUID?.none)
                        ForEach(schedule.configuration.templates) { template in
                            Text(template.name).tag(Optional(template.id))
                        }
                    }
                }
                TextField("Note, optional", text: $note)
            }

            Section {
                Button("Apply") {
                    let calendar = schedule.configuration.calendar
                    schedule.applyTemplate(
                        isNoSchool ? nil : templateID,
                        from: YearMonthDay(date: start, calendar: calendar),
                        through: YearMonthDay(date: end, calendar: calendar),
                        weekdays: weekdays.isEmpty ? nil : weekdays,
                        isNoSchool: isNoSchool,
                        note: note.isEmpty ? nil : note
                    )
                    dismiss()
                }
                .disabled(end < start)
            }
        }
        .navigationTitle("Bulk edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }

    private func symbol(_ weekday: Int) -> String {
        let symbols = schedule.configuration.calendar.veryShortWeekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : "\(weekday)"
    }
}
