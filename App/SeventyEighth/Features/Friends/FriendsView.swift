import SwiftUI
import AuthenticationServices

/// Pending requests, accepted friends, add by code, block list.
///
/// Friendship is mutual and explicit: a request has to be accepted before either
/// side sees anything about the other. Adding is by short code only. There is no
/// contacts scan and no school directory anywhere in this app.
struct FriendsView: View {

    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var isAdding = false
    @State private var confirmation: String?

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Friend code, like 78TH-K3QP", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await add() } }
                    Button("Add") { Task { await add() } }
                        .disabled(code.trimmingCharacters(in: .whitespaces).count < 4 || isAdding)
                }
            } header: {
                Text("Add a friend")
            } footer: {
                if let myCode = social.profile?.friendCode {
                    Text("Your code is \(myCode). Share it however you like; it only lets someone send you a request.")
                } else {
                    Text("They accept the request before either of you can see the other.")
                }
            }

            if let confirmation {
                Section {
                    Label(confirmation, systemImage: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            let incoming = social.requests.filter { !$0.isOutgoing }
            if !incoming.isEmpty {
                Section("Waiting on you") {
                    ForEach(incoming) { request in
                        HStack {
                            ProfileLabel(profile: request.profile)
                            Spacer()
                            Button("Accept") { Task { await social.respond(to: request, accept: true) } }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            Button("Ignore") { Task { await social.respond(to: request, accept: false) } }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }

            let outgoing = social.requests.filter(\.isOutgoing)
            if !outgoing.isEmpty {
                Section("Sent") {
                    ForEach(outgoing) { request in
                        HStack {
                            ProfileLabel(profile: request.profile)
                            Spacer()
                            Text("Pending")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Friends") {
                if social.friends.isEmpty {
                    Text("Nobody yet.")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
                ForEach(social.friends) { friend in
                    ProfileLabel(profile: friend)
                        .swipeActions(edge: .trailing) {
                            Button("Remove", role: .destructive) {
                                Task { await social.removeFriend(friend) }
                            }
                            Button("Block") {
                                Task { await social.block(friend) }
                            }
                            .tint(.orange)
                        }
                }
            }

            if !social.blocked.isEmpty {
                Section("Blocked") {
                    ForEach(social.blocked) { profile in
                        HStack {
                            ProfileLabel(profile: profile)
                            Spacer()
                            Button("Unblock") { Task { await social.unblock(profile) } }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .task {
            await social.refreshAll()
            await social.refreshBlocked()
        }
    }

    private func add() async {
        isAdding = true
        defer { isAdding = false }
        let entered = code
        guard let profile = await social.addFriend(code: entered) else { return }
        confirmation = "Request sent to \(profile.displayName)."
        code = ""
    }
}

struct ProfileLabel: View {

    let profile: Profile

    var body: some View {
        HStack(spacing: 10) {
            Text(profile.avatarEmoji)
                .frame(width: 30, height: 30)
                .background(Color.secondary.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.displayName)
                    .font(.subheadline.weight(.medium))
                if let grade = profile.grade {
                    Text("Grade \(grade)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The Sign in with Apple button, wired to the coordinator's nonce handling.
struct AppleSignInButton: View {

    @Environment(SocialStore.self) private var social
    let coordinator: SignInWithAppleCoordinator
    var onSignedIn: (String?) -> Void = { _ in }

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            coordinator.configure(request)
        } onCompletion: { result in
            let suggestedName = coordinator.suggestedName(from: result)
            guard let credentials = coordinator.credentials(from: result) else { return }
            Task {
                await social.signInWithApple(idToken: credentials.idToken, nonce: credentials.nonce)
                onSignedIn(suggestedName)
            }
        }
        .signInWithAppleButtonStyle(.black)
    }
}
