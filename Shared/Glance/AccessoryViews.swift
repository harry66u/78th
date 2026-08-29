import SwiftUI
import WidgetKit
import ScheduleEngine

/// The accessory family renderers.
///
/// These live in `Shared/` rather than in one extension because the iPhone lock
/// screen and the watch face ask for the same families and want the same answer.
/// One implementation, two extensions.

/// Rectangular: course, room, and countdown in one block, readable without
/// unlocking the phone or raising the wrist very far.
public struct AccessoryRectangularView: View {

    private let entry: ScheduleEntry

    public init(entry: ScheduleEntry) {
        self.entry = entry
    }

    public var body: some View {
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

/// Circular: the ring only, showing how much of the current period is left.
public struct AccessoryCircularView: View {

    private let entry: ScheduleEntry

    public init(entry: ScheduleEntry) {
        self.entry = entry
    }

    public var body: some View {
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

/// Inline: one line, above the clock on the Lock Screen and on the watch face's
/// inline slot.
public struct AccessoryInlineView: View {

    private let entry: ScheduleEntry

    public init(entry: ScheduleEntry) {
        self.entry = entry
    }

    public var body: some View {
        if let snapshot = entry.snapshot {
            Text(ScheduleFormatting.glanceLine(for: snapshot, timeZone: entry.timeZone))
        } else {
            Text("78th: set up your schedule")
        }
    }
}

#if os(watchOS)

/// Corner: watch faces only. The minutes sit in the corner and the course name
/// curves around the bezel, which is the most information this family can carry
/// without becoming unreadable.
public struct AccessoryCornerView: View {

    private let entry: ScheduleEntry

    public init(entry: ScheduleEntry) {
        self.entry = entry
    }

    public var body: some View {
        if let snapshot = entry.snapshot {
            let glance = GlanceContent(snapshot: snapshot)
            Group {
                if let seconds = glance.secondsRemaining(at: entry.date) {
                    Text(ScheduleFormatting.countdownValue(seconds: seconds))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .minimumScaleFactor(0.6)
                } else {
                    Image(systemName: "checkmark")
                }
            }
            .widgetLabel {
                Text(curvedLabel(glance))
            }
            .containerBackground(.clear, for: .widget)
            .accessibilityLabel(ScheduleFormatting.glanceLine(for: snapshot, timeZone: entry.timeZone))
        } else {
            Image(systemName: "calendar.badge.plus")
                .widgetLabel { Text("Set up 78th") }
                .containerBackground(.clear, for: .widget)
        }
    }

    /// The bezel has room for the course and the room number, and nothing else.
    private func curvedLabel(_ glance: GlanceContent) -> String {
        guard let room = glance.room else { return glance.title }
        return "\(glance.title) \u{00B7} \(room)"
    }
}

#endif
