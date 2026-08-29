import SwiftUI
import ScheduleEngine

/// The whole point of putting this on a watch: raise your wrist, see how long is
/// left and where you are going.
///
/// It renders from `GlanceContent`, the same reduction the widget and the
/// complications use, so the wrist cannot say one thing and the home screen
/// another.
struct NowView: View {

    @Environment(WatchScheduleStore.self) private var store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let snapshot = store.snapshot(at: context.date)
            let glance = GlanceContent(snapshot: snapshot)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    countdown(glance, at: context.date)

                    Text(glance.title)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)

                    if let room = glance.room {
                        Text("Room \(room)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    } else if glance.mode == .idle, let label = glance.slotLabel {
                        Text(label)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let note = snapshot.day.overrideNote, !note.isEmpty {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }

                    if let next = upNext(snapshot) {
                        Divider()
                            .padding(.vertical, 2)
                        Text("Then \(next.title)\(next.room.map { " \u{00B7} \($0)" } ?? "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if !store.bellTimesConfirmed {
                        Text("Bell times unconfirmed")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .containerBackground(glance.color.opacity(0.35).gradient, for: .navigation)
            .navigationTitle(snapshot.day.templateName ?? "Today")
            .accessibilityElement(children: .combine)
            .accessibilityLabel(ScheduleFormatting.glanceLine(for: snapshot, timeZone: store.timeZone))
        }
    }

    /// The dominant element, exactly as on the small widget: a bare number, with
    /// its unit and its caption small beside it.
    @ViewBuilder
    private func countdown(_ glance: GlanceContent, at date: Date) -> some View {
        if let seconds = glance.secondsRemaining(at: date) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(ScheduleFormatting.countdownValue(seconds: seconds))
                    .font(Theme.countdownFont(size: 44))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                VStack(alignment: .leading, spacing: -2) {
                    Text(ScheduleFormatting.countdownUnit(seconds: seconds))
                        .font(.caption.weight(.semibold))
                    Text(glance.caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)
            }
        } else {
            Text(glance.slotLabel ?? "Today")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    /// The period after the one being counted down to. Nil when the countdown is
    /// already pointing at the last thing of the day.
    private func upNext(_ snapshot: ScheduleSnapshot) -> ResolvedPeriod? {
        switch snapshot.status {
        case .inPeriod(_, let next):
            return next
        case .beforeSchool, .passing:
            // `upcoming` starts with the period being counted down to.
            return snapshot.upcoming.dropFirst().first
        case .dayComplete, .noSchool:
            return nil
        }
    }
}
