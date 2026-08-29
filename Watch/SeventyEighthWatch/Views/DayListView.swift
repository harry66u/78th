import SwiftUI
import ScheduleEngine

/// The second page: the rest of the day, for when "what is next" is not the
/// question. Past periods stay in the list, dimmed, because scrolling up to see
/// what you just came out of is a real thing students do.
struct DayListView: View {

    @Environment(WatchScheduleStore.self) private var store

    var body: some View {
        TimelineView(.everyMinute) { context in
            let snapshot = store.snapshot(at: context.date)

            List {
                if snapshot.day.periods.isEmpty {
                    Text(emptyMessage(snapshot))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.day.periods) { period in
                        row(period, now: context.date)
                    }
                }

                syncSection
            }
            .navigationTitle(snapshot.day.templateName ?? "Today")
        }
    }

    @ViewBuilder
    private func row(_ period: ResolvedPeriod, now: Date) -> some View {
        let isNow = period.contains(now)
        let isPast = period.end <= now

        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Theme.courseColor(for: period))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text(period.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(detail(period))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isNow {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(Theme.courseColor(for: period))
            }
        }
        .opacity(isPast ? 0.4 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(period.title), \(detail(period))\(isNow ? ", now" : "")")
    }

    private func detail(_ period: ResolvedPeriod) -> String {
        let range = ScheduleFormatting.range(period, timeZone: store.timeZone)
        guard let room = period.room else { return range }
        return "\(range) \u{00B7} \(room)"
    }

    private func emptyMessage(_ snapshot: ScheduleSnapshot) -> String {
        if case .noSchool(let reason) = snapshot.status { return reason }
        return "Nothing scheduled today."
    }

    /// The watch cannot fetch a schedule on its own, so when it looks stale the
    /// only honest thing to offer is "ask the phone again".
    @ViewBuilder
    private var syncSection: some View {
        Section {
            Button {
                store.requestRefresh()
            } label: {
                Label(
                    store.isRequesting ? "Updating\u{2026}" : "Update from iPhone",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.footnote)
            }
            .disabled(store.isRequesting)
        } footer: {
            if let syncedAt = store.syncedAt {
                Text("Synced \(ScheduleFormatting.relativePast(syncedAt))")
            } else {
                Text("Not synced yet.")
            }
        }
    }
}
