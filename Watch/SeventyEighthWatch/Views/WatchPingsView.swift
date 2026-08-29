import SwiftUI
import ScheduleEngine

/// The third page: where your friends are, and one tap to say where you are.
///
/// Same rule as the phone — there is no text field anywhere on this screen.
/// Everything a student can say comes from two closed lists, which is what keeps
/// this a utility rather than a messaging app on a wrist.
struct WatchPingsView: View {

    @Environment(WatchSocialStore.self) private var social

    var body: some View {
        Group {
            switch social.state {
            case .unconfigured:
                MessageView(
                    symbol: "wifi.slash",
                    title: "No backend",
                    detail: "This build has no server configured, so pings are off."
                )
            case .signedOut:
                WatchSignInView()
            case .needsProfileOnPhone:
                MessageView(
                    symbol: "iphone",
                    title: "Finish on your iPhone",
                    detail: "Pick a name and an emoji in 78th on your phone, then come back."
                )
            case .ready:
                content
            }
        }
        .navigationTitle("Pings")
        .task {
            await social.restore()
            await social.flushOutbox()
            social.startRealtime()
        }
        .onDisappear { social.stopRealtime() }
        .alert("Something went wrong", isPresented: .constant(social.lastError != nil)) {
            Button("OK") { social.dismissError() }
        } message: {
            Text(social.lastError ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        List {
            statusSection

            if social.groups.isEmpty {
                Section {
                    Text(social.hasFriends
                         ? "Nobody is out right now. Pings disappear when they expire."
                         : "Add a friend by their code on your iPhone to see where they are.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(social.groups) { group in
                    LocationSection(group: group)
                }
            }
        }
        .refreshable { await social.refresh() }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section {
            if social.isInvisible {
                Label("Invisible today", systemImage: "eye.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Turn it off on your iPhone.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                let live = social.myPing.flatMap { $0.isLive() ? $0 : nil }

                NavigationLink {
                    SendPingView()
                } label: {
                    Label(
                        live.map { "At \($0.location.shortName)" } ?? "Where are you?",
                        systemImage: live?.location.symbolName ?? "mappin.and.ellipse"
                    )
                }

                if live != nil {
                    Button(role: .destructive) {
                        Task { await social.clearMyPing() }
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                            .font(.footnote)
                    }
                }
            }
        }
    }
}

/// One location and the friends at it, with a join button underneath.
///
/// Join is its own row rather than a tappable section header: on a screen this
/// size a header that is secretly a button is a header people never press.
private struct LocationSection: View {

    @Environment(WatchScheduleStore.self) private var schedule
    @Environment(WatchSocialStore.self) private var social

    let group: LocationGroup

    var body: some View {
        Section {
            ForEach(group.pings) { friendPing in
                WatchFriendPingRow(friendPing: friendPing)
            }

            if !social.isInvisible {
                Button {
                    Task {
                        await social.ping(
                            group.location,
                            note: nil,
                            currentPeriodEnd: schedule.snapshot().current?.end
                        )
                    }
                } label: {
                    Label("Join", systemImage: "arrow.right.circle")
                        .font(.footnote)
                }
                .disabled(social.isSending)
            }
        } header: {
            Label(group.location.shortName, systemImage: group.location.symbolName)
        }
    }
}

struct WatchFriendPingRow: View {

    let friendPing: FriendPing

    var body: some View {
        HStack(spacing: 8) {
            Text(friendPing.profile.avatarEmoji)
                .font(.body)
                .frame(width: 26, height: 26)
                .background(Color.secondary.opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 0) {
                Text(friendPing.profile.displayName)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(friendPing.profile.displayName), \(detail)")
    }

    private var detail: String {
        let age = ScheduleFormatting.relativePast(friendPing.ping.createdAt)
        guard let note = friendPing.ping.noteKey else { return age }
        return "\(note.displayName) \u{00B7} \(age)"
    }
}

/// A centred line of explanation, for the three states that are not a list.
struct MessageView: View {

    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
