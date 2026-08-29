import SwiftUI
import WidgetKit
import ScheduleEngine

/// Home screen, medium.
///
/// Current period on the left, next two stacked on the right.
struct MediumScheduleView: View {

    let entry: ScheduleEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            content(snapshot)
        } else {
            SetupPromptView()
        }
    }

    @ViewBuilder
    private func content(_ snapshot: ScheduleSnapshot) -> some View {
        let glance = GlanceContent(snapshot: snapshot)

        HStack(alignment: .top, spacing: 14) {
            leading(glance)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            trailing(snapshot)
                .frame(width: 132, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ScheduleFormatting.glanceLine(for: snapshot, timeZone: entry.timeZone))
    }

    @ViewBuilder
    private func leading(_ glance: GlanceContent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let label = glance.slotLabel {
                Text(label.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Text(glance.title)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            if let room = glance.room {
                Text("Room \(room)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if let seconds = glance.secondsRemaining(at: entry.date) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(ScheduleFormatting.countdownValue(seconds: seconds))
                        .font(Theme.countdownFont(size: 34))
                    Text("\(ScheduleFormatting.countdownUnit(seconds: seconds)) \(glance.caption)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(glance.color)
            }
        }
    }

    @ViewBuilder
    private func trailing(_ snapshot: ScheduleSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let note = snapshot.day.overrideNote, !note.isEmpty {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            let next = Array(snapshot.upcoming.prefix(2))
            if next.isEmpty {
                Text(emptyTrailingText(snapshot))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            } else {
                ForEach(next) { period in
                    UpcomingRow(period: period, timeZone: entry.timeZone)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func emptyTrailingText(_ snapshot: ScheduleSnapshot) -> String {
        switch snapshot.status {
        case .noSchool:
            return snapshot.day.overrideNote ?? "No school"
        case .dayComplete(let nextDay):
            guard let nextDay else { return "Nothing else scheduled" }
            return "Tomorrow: \(nextDay.title) at \(ScheduleFormatting.clock(nextDay.start, timeZone: entry.timeZone))"
        default:
            return "Last period of the day"
        }
    }
}

private struct UpcomingRow: View {

    let period: ResolvedPeriod
    let timeZone: TimeZone

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.courseColor(for: period))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text(period.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(height: 30)
    }

    private var subtitle: String {
        let time = ScheduleFormatting.clock(period.start, timeZone: timeZone)
        guard let room = period.room else { return time }
        return "\(time) \u{00B7} \(room)"
    }
}
