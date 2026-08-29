import SwiftUI
import WidgetKit
import ScheduleEngine

@main
struct SeventyEighthWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        WatchScheduleComplication()
    }
}

/// The schedule on the watch face.
///
/// Four families, because a student picks a face and then lives with it: corner
/// and circular for the dense faces, rectangular for the ones with a wide slot,
/// inline for the top of the Infograph Modular.
struct WatchScheduleComplication: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: AppIdentifiers.WidgetKind.watchSchedule,
            provider: WatchScheduleProvider()
        ) { entry in
            WatchComplicationView(entry: entry)
        }
        .configurationDisplayName("Next Class")
        .description("Minutes left, what is next, and where it is.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

struct WatchComplicationView: View {

    @Environment(\.widgetFamily) private var family
    let entry: ScheduleEntry

    var body: some View {
        switch family {
        case .accessoryCorner:
            AccessoryCornerView(entry: entry)
        case .accessoryCircular:
            AccessoryCircularView(entry: entry)
        case .accessoryInline:
            AccessoryInlineView(entry: entry)
        default:
            AccessoryRectangularView(entry: entry)
        }
    }
}

#Preview("Circular", as: .accessoryCircular) {
    WatchScheduleComplication()
} timeline: {
    ScheduleEntry.preview()
    ScheduleEntry.unconfigured()
}

#Preview("Rectangular", as: .accessoryRectangular) {
    WatchScheduleComplication()
} timeline: {
    ScheduleEntry.preview()
}

#Preview("Corner", as: .accessoryCorner) {
    WatchScheduleComplication()
} timeline: {
    ScheduleEntry.preview()
}
