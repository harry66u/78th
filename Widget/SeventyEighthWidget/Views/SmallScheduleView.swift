import SwiftUI
import WidgetKit
import ScheduleEngine

/// Home screen, small.
///
/// Minutes remaining is the dominant element, then the course name and the room.
/// Nothing else earns the space.
struct SmallScheduleView: View {

    let entry: ScheduleEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            content(GlanceContent(snapshot: snapshot))
        } else {
            SetupPromptView()
        }
    }

    @ViewBuilder
    private func content(_ glance: GlanceContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let seconds = glance.secondsRemaining(at: entry.date) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(ScheduleFormatting.countdownValue(seconds: seconds))
                        .font(Theme.countdownFont(size: 52))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    VStack(alignment: .leading, spacing: -2) {
                        Text(ScheduleFormatting.countdownUnit(seconds: seconds))
                            .font(.caption.weight(.semibold))
                        Text(glance.caption)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 6)
                }
                .foregroundStyle(glance.color)
            } else {
                Text(glance.slotLabel ?? "Today")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Text(glance.title)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            if let room = glance.room {
                Text("Room \(room)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if glance.mode == .idle, let label = glance.slotLabel {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(glanceDescription())
    }

    private func glanceDescription() -> String {
        guard let snapshot = entry.snapshot else { return "Open 78th to set up your schedule" }
        return ScheduleFormatting.glanceLine(for: snapshot, timeZone: entry.timeZone)
    }
}

/// Shown when the shared container has no schedule in it. The widget cannot
/// fetch one, so the only useful thing it can do is say so.
struct SetupPromptView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "calendar.badge.plus")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Open 78th")
                .font(.headline)
            Text("Add your schedule once and this fills in.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}
