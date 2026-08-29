import SwiftUI
import ScheduleEngine

/// The default tab: the current period with a live countdown, then the rest of
/// the day below.
struct TodayView: View {

    @Environment(ScheduleStore.self) private var schedule
    @State private var isPresentingSetup = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let snapshot = schedule.snapshot(at: context.date)

            ScrollView {
                VStack(spacing: 16) {
                    if schedule.needsBellTimeConfirmation {
                        BellTimesBanner()
                    }

                    if !schedule.hasAnyCourses {
                        EmptyScheduleCard(onSetUp: { isPresentingSetup = true })
                    }

                    CurrentPeriodCard(snapshot: snapshot, timeZone: schedule.timeZone)

                    if !snapshot.day.periods.isEmpty {
                        DayListCard(snapshot: snapshot, timeZone: schedule.timeZone)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle(title(for: snapshot))
            .navigationBarTitleDisplayMode(.large)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingSetup = true
                } label: {
                    Label("Edit schedule", systemImage: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $isPresentingSetup) {
            NavigationStack { ScheduleSetupView() }
        }
    }

    private func title(for snapshot: ScheduleSnapshot) -> String {
        snapshot.day.templateName ?? ScheduleFormatting.mediumDay(snapshot.now, timeZone: schedule.timeZone)
    }
}

/// The card the whole app exists for.
struct CurrentPeriodCard: View {

    let snapshot: ScheduleSnapshot
    let timeZone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch snapshot.status {
            case .inPeriod(let current, let next):
                header(current.slotLabel ?? "Now", color: Theme.courseColor(for: current))
                title(current)
                countdown(seconds: snapshot.secondsRemaining ?? 0, caption: "left", color: Theme.courseColor(for: current))
                if let next {
                    upNext(next)
                }

            case .passing(_, let next):
                header("Passing time", color: .secondary)
                title(next)
                countdown(seconds: snapshot.secondsRemaining ?? 0, caption: "until it starts", color: Theme.courseColor(for: next))

            case .beforeSchool(let next):
                header("First up", color: .secondary)
                title(next)
                countdown(seconds: snapshot.secondsRemaining ?? 0, caption: "until it starts", color: Theme.courseColor(for: next))

            case .dayComplete(let nextDay):
                header("Done for today", color: .secondary)
                if let nextDay {
                    Text(nextDay.title)
                        .font(.title2.weight(.semibold))
                    Text("Tomorrow at \(ScheduleFormatting.clock(nextDay.start, timeZone: timeZone))\(nextDay.room.map { " \u{00B7} Room \($0)" } ?? "")")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Nothing else scheduled")
                        .foregroundStyle(.secondary)
                }

            case .noSchool(let reason):
                header("No school", color: .secondary)
                Text(reason)
                    .font(.title.weight(.semibold))
            }

            if let note = snapshot.day.overrideNote, !note.isEmpty {
                Label(note, systemImage: "exclamationmark.bubble")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ScheduleFormatting.glanceLine(for: snapshot, timeZone: timeZone))
    }

    @ViewBuilder
    private func header(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
    }

    @ViewBuilder
    private func title(_ period: ResolvedPeriod) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(period.title)
                .font(.largeTitle.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.6)

            HStack(spacing: 8) {
                if let room = period.room {
                    Label("Room \(room)", systemImage: "door.left.hand.open")
                }
                Text(ScheduleFormatting.range(period, timeZone: timeZone))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let teacher = period.teacher {
                Text(teacher)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func countdown(seconds: Int, caption: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(ScheduleFormatting.countdownValue(seconds: seconds))
                .font(Theme.countdownFont(size: 64))
                .foregroundStyle(color)
                .monospacedDigit()
                .contentTransition(.numericText())
            VStack(alignment: .leading, spacing: -2) {
                Text(ScheduleFormatting.countdownUnit(seconds: seconds))
                    .font(.headline)
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func upNext(_ period: ResolvedPeriod) -> some View {
        Divider()
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.courseColor(for: period))
                .frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Next")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(nextLine(period))
                    .font(.subheadline.weight(.medium))
            }
            Spacer()
        }
    }

    private func nextLine(_ period: ResolvedPeriod) -> String {
        let time = ScheduleFormatting.clock(period.start, timeZone: timeZone)
        guard let room = period.room else { return "\(period.title) at \(time)" }
        return "\(period.title) \u{00B7} \(room) at \(time)"
    }
}

/// The rest of the day, current period highlighted.
struct DayListCard: View {

    let snapshot: ScheduleSnapshot
    let timeZone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(snapshot.day.templateName ?? "Today")
                .font(.headline)
                .padding(.bottom, 10)

            ForEach(Array(snapshot.day.periods.enumerated()), id: \.element.id) { index, period in
                PeriodRow(
                    period: period,
                    timeZone: timeZone,
                    isCurrent: period.id == snapshot.current?.id,
                    isPast: period.end <= snapshot.now
                )
                if index < snapshot.day.periods.count - 1 {
                    Divider().padding(.leading, 62)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct PeriodRow: View {

    let period: ResolvedPeriod
    let timeZone: TimeZone
    let isCurrent: Bool
    let isPast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(ScheduleFormatting.clock(period.start, timeZone: timeZone))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.courseColor(for: period))
                .frame(width: 4)
                .opacity(isPast ? 0.3 : 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(period.title)
                    .font(.subheadline.weight(isCurrent ? .bold : .medium))
                HStack(spacing: 6) {
                    if let label = period.slotLabel {
                        Text(label)
                    }
                    if let room = period.room {
                        Text(room)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if isCurrent {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(Theme.courseColor(for: period))
            }
        }
        .padding(.vertical, 8)
        .opacity(isPast ? 0.45 : 1)
    }
}

/// Shown until the student confirms the bell times, because the shipped defaults
/// are a placeholder and being quietly wrong is the one thing this app cannot be.
struct BellTimesBanner: View {

    @Environment(ScheduleStore.self) private var schedule
    @State private var isPresentingBellTimes = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Check your bell times")
                    .font(.subheadline.weight(.semibold))
                Text("78th shipped with a default set. Confirm them once so the countdown is right.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Review") { isPresentingBellTimes = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("They're right") { schedule.confirmBellTimes() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .sheet(isPresented: $isPresentingBellTimes) {
            NavigationStack { BellTimesEditorView() }
        }
    }
}

struct EmptyScheduleCard: View {

    let onSetUp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No courses yet")
                .font(.headline)
            Text("Paste your schedule, photograph it, or fill in the grid. It takes about two minutes and you never have to do it again.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Add my schedule", action: onSetUp)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview {
    NavigationStack { TodayView() }
        .environment(PreviewSupport.store())
        .environment(PreviewSupport.social())
}
