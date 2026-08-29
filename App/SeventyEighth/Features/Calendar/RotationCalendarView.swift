import SwiftUI
import ScheduleEngine

/// Assign day templates to dates, mark no-school days, and bulk edit.
///
/// Half days, fast days, finals week, chagim, and snow days are the cases that
/// destroy trust when the app gets them wrong, so all of them are one screen and
/// one tap away rather than buried.
struct RotationCalendarView: View {

    @Environment(ScheduleStore.self) private var schedule
    @Environment(SocialStore.self) private var social

    @State private var month: Date = Date()
    @State private var editingDate: YearMonthDay?
    @State private var isPresentingBulk = false
    @State private var rotationMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                weekdayDefaults
                monthGrid
                bulkTools
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .navigationTitle("Rotation")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingDate) { date in
            NavigationStack { DayOverrideSheet(date: date) }
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $isPresentingBulk) {
            NavigationStack { BulkRotationSheet() }
        }
        .alert("School calendar", isPresented: .constant(rotationMessage != nil)) {
            Button("OK") { rotationMessage = nil }
        } message: {
            Text(rotationMessage ?? "")
        }
    }

    // MARK: Weekday defaults

    private var weekdayDefaults: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Normal week")
                .font(.headline)
            Text("Which day type falls on each weekday when nothing overrides it.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ForEach(1...7, id: \.self) { weekday in
                HStack {
                    Text(weekdayName(weekday))
                        .font(.subheadline)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { schedule.configuration.weekdayDefaults[weekday] },
                        set: { schedule.setWeekdayDefault(weekday: weekday, templateID: $0) }
                    )) {
                        Text("No school").tag(UUID?.none)
                        ForEach(schedule.configuration.templates) { template in
                            Text(template.name).tag(Optional(template.id))
                        }
                    }
                    .labelsHidden()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func weekdayName(_ weekday: Int) -> String {
        let symbols = schedule.configuration.calendar.weekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : "Day \(weekday)"
    }

    // MARK: Month grid

    private var monthGrid: some View {
        VStack(spacing: 12) {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(monthTitle)
                    .font(.headline)
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(shortWeekdaySymbols.indices, id: \.self) { index in
                    Text(shortWeekdaySymbols[index])
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ForEach(monthCells.indices, id: \.self) { index in
                    if let date = monthCells[index] {
                        DayCell(date: date, day: schedule.engine.schoolDay(for: date))
                            .onTapGesture { editingDate = date }
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var shortWeekdaySymbols: [String] {
        schedule.configuration.calendar.veryShortWeekdaySymbols
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.timeZone = schedule.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: month)
    }

    private func shiftMonth(_ delta: Int) {
        let calendar = schedule.configuration.calendar
        month = calendar.date(byAdding: .month, value: delta, to: month) ?? month
    }

    /// Leading nils pad the first row so the 1st lands under the right weekday.
    private var monthCells: [YearMonthDay?] {
        let calendar = schedule.configuration.calendar
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month))
        else { return [] }

        let firstWeekday = calendar.component(.weekday, from: first)
        let padding = Array(repeating: YearMonthDay?.none, count: firstWeekday - 1)
        let days = range.map { day -> YearMonthDay? in
            let components = calendar.dateComponents([.year, .month], from: first)
            guard let year = components.year, let month = components.month else { return nil }
            return YearMonthDay(year: year, month: month, day: day)
        }
        return padding + days
    }

    // MARK: Bulk tools

    private var bulkTools: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                isPresentingBulk = true
            } label: {
                Label("Apply to a date range", systemImage: "calendar.badge.plus")
            }

            Divider()

            Button {
                Task { await syncRotation() }
            } label: {
                Label("Get the school calendar", systemImage: "arrow.down.circle")
            }

            Text(rotationStatus)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var rotationStatus: String {
        guard schedule.rotationVersion > 0 else {
            return "The official rotation and holiday list, pushed from the school. Your courses stay on this phone."
        }
        let year = schedule.rotationSchoolYear.map { " for \($0)" } ?? ""
        return "Version \(schedule.rotationVersion)\(year) applied."
    }

    private func syncRotation() async {
        do {
            let signed = try await social.fetchRotationFile()
            let file = try RotationSync.verifiedRotation(from: signed)
            guard let report = schedule.applyRotation(file) else {
                rotationMessage = "You already have the latest calendar."
                return
            }
            rotationMessage = RotationSync.describe(report)
        } catch {
            rotationMessage = RotationSync.describe(error)
        }
    }
}

private struct DayCell: View {

    let date: YearMonthDay
    let day: SchoolDay

    var body: some View {
        VStack(spacing: 2) {
            Text("\(date.day)")
                .font(.footnote.weight(.medium))
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(day.isNoSchool ? Color.secondary : Theme.courseColor(0))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
            day.isNoSchool ? Color.clear : Theme.courseColor(0).opacity(0.10),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .contentShape(Rectangle())
    }

    private var label: String {
        if day.isNoSchool {
            if let note = day.overrideNote, !note.isEmpty { return note }
            return ""
        }
        return day.templateName ?? ""
    }
}
