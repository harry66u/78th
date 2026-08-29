import SwiftUI
import WidgetKit
import ScheduleEngine

/// The reason this app is native Swift rather than React Native: the schedule
/// on the home screen and the lock screen, correct with the app closed.
struct ScheduleWidget: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppIdentifiers.WidgetKind.schedule, provider: ScheduleProvider()) { entry in
            ScheduleWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Next Class")
        .description("Minutes left, what is next, and where it is.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryInline
        ])
    }
}

struct ScheduleWidgetEntryView: View {

    @Environment(\.widgetFamily) private var family
    let entry: ScheduleEntry

    var body: some View {
        switch family {
        case .systemMedium:
            MediumScheduleView(entry: entry)
        case .accessoryRectangular:
            AccessoryRectangularView(entry: entry)
        case .accessoryCircular:
            AccessoryCircularView(entry: entry)
        case .accessoryInline:
            AccessoryInlineView(entry: entry)
        default:
            SmallScheduleView(entry: entry)
        }
    }
}

#Preview("Small", as: .systemSmall) {
    ScheduleWidget()
} timeline: {
    ScheduleEntry(
        date: PreviewSchedule.midPeriodTwo(),
        snapshot: PreviewSchedule.snapshot(),
        isConfigured: true,
        timeZone: PreviewSchedule.timeZone
    )
    ScheduleEntry.unconfigured()
}

#Preview("Medium", as: .systemMedium) {
    ScheduleWidget()
} timeline: {
    ScheduleEntry(
        date: PreviewSchedule.midPeriodTwo(),
        snapshot: PreviewSchedule.snapshot(),
        isConfigured: true,
        timeZone: PreviewSchedule.timeZone
    )
}

#Preview("Lock screen", as: .accessoryRectangular) {
    ScheduleWidget()
} timeline: {
    ScheduleEntry(
        date: PreviewSchedule.midPeriodTwo(),
        snapshot: PreviewSchedule.snapshot(),
        isConfigured: true,
        timeZone: PreviewSchedule.timeZone
    )
}
