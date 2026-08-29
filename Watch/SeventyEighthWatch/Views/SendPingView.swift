import SwiftUI
import ScheduleEngine

/// One tap, from a list of nine spots.
///
/// The expiry is computed here, on the watch, from the watch's own copy of the
/// schedule: 45 minutes or the end of the current period, whichever comes first.
/// That is the same rule the phone and the widget apply, from the same engine —
/// the server is told an instant and never a schedule.
struct SendPingView: View {

    @Environment(WatchScheduleStore.self) private var schedule
    @Environment(WatchSocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss

    @State private var note: PingNote?

    var body: some View {
        List {
            Section {
                Picker("Tag", selection: $note) {
                    Text("No tag").tag(PingNote?.none)
                    ForEach(PingNote.allCases) { option in
                        Label(option.displayName, systemImage: option.symbolName)
                            .tag(PingNote?.some(option))
                    }
                }
            }

            Section {
                ForEach(PingLocation.allCases) { location in
                    Button {
                        Task { await send(location) }
                    } label: {
                        HStack(spacing: 6) {
                            Label(location.shortName, systemImage: location.symbolName)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if isCurrent(location) {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } footer: {
                Text(footer)
                    .font(.caption2)
            }
        }
        .navigationTitle("Where are you?")
        .disabled(social.isSending)
    }

    private func isCurrent(_ location: PingLocation) -> Bool {
        social.myPing?.location == location && social.myPing?.isLive() == true
    }

    private var footer: String {
        guard let end = schedule.snapshot().current?.end else {
            return "Lasts 45 minutes."
        }
        let clock = ScheduleFormatting.clock(end, timeZone: schedule.timeZone)
        return "Clears itself at \(clock), when this period ends."
    }

    private func send(_ location: PingLocation) async {
        await social.ping(
            location,
            note: note,
            currentPeriodEnd: schedule.snapshot().current?.end
        )
        // Staying on the picker after a successful tap would be one more press
        // to get back to the list of friends, which is the thing worth seeing.
        if social.lastError == nil { dismiss() }
    }
}
