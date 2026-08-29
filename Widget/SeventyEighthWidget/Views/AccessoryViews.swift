import SwiftUI
import WidgetKit
import ScheduleEngine

/// Lock screen, rectangular. Course, room, and countdown in one line, readable
/// without unlocking.
struct AccessoryRectangularView: View {

    let entry: ScheduleEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            let glance = GlanceContent(snapshot: snapshot)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(glance.title)
                        .font(.headline)
                        .lineLimit(1)
                    if let room = glance.room {
                        Text(room)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let seconds = glance.secondsRemaining(at: entry.date) {
                    Text("\(ScheduleFormatting.countdown(seconds: seconds)) \(glance.caption)")
                        .font(.subheadline.weight(.semibold))
                } else if let label = glance.slotLabel {
                    Text(label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(.clear, for: .widget)
            .accessibilityLabel(ScheduleFormatting.glanceLine(for: snapshot, timeZone: entry.timeZone))
        } else {
            Text("Open 78th to set up")
                .font(.subheadline)
                .containerBackground(.clear, for: .widget)
        }
    }
}

/// Lock screen, circular. The ring only: how much of the current period is left.
struct AccessoryCircularView: View {

    let entry: ScheduleEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            let glance = GlanceContent(snapshot: snapshot)
            Gauge(value: 1 - glance.progress(at: entry.date)) {
                Image(systemName: "clock")
            } currentValueLabel: {
                if let seconds = glance.secondsRemaining(at: entry.date) {
                    Text(ScheduleFormatting.countdownValue(seconds: seconds))
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .minimumScaleFactor(0.6)
                } else {
                    Image(systemName: "checkmark")
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .containerBackground(.clear, for: .widget)
            .accessibilityLabel(ScheduleFormatting.glanceLine(for: snapshot, timeZone: entry.timeZone))
        } else {
            Image(systemName: "calendar.badge.plus")
                .containerBackground(.clear, for: .widget)
        }
    }
}

/// Lock screen, inline. Fits above the clock on the Lock Screen and on the Watch
/// complication rail.
struct AccessoryInlineView: View {

    let entry: ScheduleEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            Text(ScheduleFormatting.glanceLine(for: snapshot, timeZone: entry.timeZone))
        } else {
            Text("78th: set up your schedule")
        }
    }
}
