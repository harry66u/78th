import AppIntents
import SwiftData
import SwiftUI
import WidgetKit
import ScheduleEngine

/// The one-tap half of the ping loop, on the home screen.
///
/// The spec's main loop is "tap a location, done". Putting four locations on a
/// medium widget makes that a single tap from the home screen with no app launch
/// at all. There is nothing to read here and nothing about other people: it only
/// sends, so a widget on a visible home screen never leaks who is where.
struct PingWidget: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SeventyEighthPingWidget", provider: PingWidgetProvider()) { entry in
            PingWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Ping")
        .description("Tell your friends where you are, in one tap.")
        .supportedFamilies([.systemMedium])
    }
}

struct PingWidgetEntry: TimelineEntry {
    let date: Date
    /// Set right after a ping so the widget can confirm it landed.
    let lastPing: (location: PingLocation, sentAt: Date)?
    /// Ping sending is disabled while the student is in an instructional period.
    let isInClass: Bool
}

struct PingWidgetProvider: TimelineProvider {

    func placeholder(in context: Context) -> PingWidgetEntry {
        PingWidgetEntry(date: Date(), lastPing: nil, isInClass: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (PingWidgetEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PingWidgetEntry>) -> Void) {
        let entry = currentEntry()
        // Refresh when the student's own class state next changes, so the tile
        // stops offering to ping mid-lesson.
        let next = nextClassBoundary() ?? Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func currentEntry() -> PingWidgetEntry {
        PingWidgetEntry(
            date: Date(),
            lastPing: PingOutbox.shared.lastConfirmed(),
            isInClass: engine()?.isInInstructionalPeriod() ?? false
        )
    }

    private func nextClassBoundary() -> Date? {
        engine()?.snapshot(at: Date()).nextBoundary
    }

    private func engine() -> ScheduleEngine? {
        guard let container = ScheduleContainer.attempt() else { return nil }
        return ScheduleConfigurationLoader.engine(from: ModelContext(container))
    }
}

struct PingWidgetView: View {

    let entry: PingWidgetEntry

    /// The four spots that carry most pings. Everything else is one tap further,
    /// in the app.
    private let locations: [PingLocation] = [.lobby, .library, .cafeteria, .lounge4]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(locations) { location in
                    Button(intent: SendPingIntent(location: location)) {
                        Label(location.shortName, systemImage: location.symbolName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
        .disabled(entry.isInClass)
        .opacity(entry.isInClass ? 0.5 : 1)
    }

    @ViewBuilder
    private var header: some View {
        if entry.isInClass {
            Text("In class")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        } else if let last = entry.lastPing, last.sentAt.timeIntervalSinceNow > -600 {
            Text("Sent \u{00B7} \(last.location.shortName)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        } else {
            Text("Where are you?")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
