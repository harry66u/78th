import SwiftUI
import ScheduleEngine

/// The second tab. Location buttons at the top, friends grouped by location
/// below.
///
/// There is no text field anywhere on this screen. Everything a student can say
/// here comes from two closed lists, which is what keeps this a utility rather
/// than a messaging app.
struct PingsView: View {

    @Environment(ScheduleStore.self) private var schedule
    @Environment(SocialStore.self) private var social

    @State private var selectedNote: PingNote?
    @State private var isPresentingFriends = false

    var body: some View {
        Group {
            if social.isSignedIn {
                content
            } else {
                SignedOutPingsView()
            }
        }
        .navigationTitle("Pings")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingFriends = true
                } label: {
                    Label("Friends", systemImage: "person.2")
                }
                .overlay(alignment: .topTrailing) {
                    if incomingCount > 0 {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                            .offset(x: 4, y: -2)
                    }
                }
            }
        }
        .sheet(isPresented: $isPresentingFriends) {
            NavigationStack { FriendsView() }
        }
        .refreshable { await social.refreshAll() }
        .alert("Something went wrong", isPresented: .constant(social.lastError != nil)) {
            Button("OK") { social.lastError = nil }
        } message: {
            Text(social.lastError ?? "")
        }
    }

    private var incomingCount: Int {
        social.requests.filter { !$0.isOutgoing }.count
    }

    @ViewBuilder
    private var content: some View {
        List {
            if social.isInvisible {
                Section {
                    Label("You are invisible today. Friends cannot see where you are.", systemImage: "eye.slash")
                        .font(.footnote)
                }
            }

            Section {
                noteChips
                locationGrid
            } header: {
                Text("Where are you?")
            } footer: {
                Text(footerText)
            }

            if social.groups.isEmpty {
                Section {
                    ContentUnavailableView(
                        social.friends.isEmpty ? "No friends yet" : "Nobody is out right now",
                        systemImage: social.friends.isEmpty ? "person.badge.plus" : "moon.zzz",
                        description: Text(
                            social.friends.isEmpty
                                ? "Add a friend by their code to see where they are."
                                : "Pings disappear when they expire. Nothing is kept."
                        )
                    )
                }
            } else {
                ForEach(social.groups) { group in
                    Section {
                        ForEach(group.pings) { friendPing in
                            FriendPingRow(friendPing: friendPing)
                        }
                    } header: {
                        Button {
                            Task { await send(group.location) }
                        } label: {
                            HStack {
                                Label(group.location.displayName, systemImage: group.location.symbolName)
                                Spacer()
                                Text("Join")
                                    .font(.caption.weight(.bold))
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .task { await social.refreshAll() }
    }

    private var footerText: String {
        if let ping = social.myPing, ping.isLive() {
            return "You are at \(ping.locationKey.displayName). It clears itself when the period ends."
        }
        return "A ping lasts 45 minutes, or until the period ends, whichever comes first."
    }

    /// The optional tag. Tapping the same one again clears it.
    private var noteChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PingNote.allCases) { note in
                    Button {
                        selectedNote = selectedNote == note ? nil : note
                    } label: {
                        Label(note.displayName, systemImage: note.symbolName)
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(selectedNote == note ? Theme.courseColor(0) : .secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 0))
    }

    private var locationGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(PingLocation.allCases) { location in
                Button {
                    Task { await send(location) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: location.symbolName)
                        Text(location.shortName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .tint(social.myPing?.locationKey == location && social.myPing?.isLive() == true
                      ? Theme.courseColor(0)
                      : .secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// One tap: the whole action.
    private func send(_ location: PingLocation) async {
        let end = schedule.snapshot().current?.end
        await social.ping(location, note: selectedNote, currentPeriodEnd: end)
    }
}

struct FriendPingRow: View {

    let friendPing: FriendPing

    var body: some View {
        HStack(spacing: 12) {
            Text(friendPing.profile.avatarEmoji)
                .font(.title2)
                .frame(width: 34, height: 34)
                .background(Color.secondary.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(friendPing.profile.displayName)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 6) {
                    if let note = friendPing.ping.noteKey {
                        Text(note.displayName)
                    }
                    Text(ScheduleFormatting.relativePast(friendPing.ping.createdAt))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

struct SignedOutPingsView: View {

    @Environment(SocialStore.self) private var social
    @State private var coordinator = SignInWithAppleCoordinator()

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Pings need an account")
                .font(.headline)
            Text("Your schedule works without one. Signing in is only so friends can find you during frees.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            AppleSignInButton(coordinator: coordinator)
                .frame(height: 46)
                .padding(.horizontal, 32)
        }
        .padding()
    }
}
