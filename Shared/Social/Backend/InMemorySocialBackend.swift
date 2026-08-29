import Foundation
import ScheduleEngine

/// An in-memory backend for SwiftUI previews, UI work without a network, and
/// tests. It enforces the same visibility rule the database does, so a preview
/// that shows a stranger's ping is a bug you can see.
public actor InMemorySocialBackend: SocialBackend {

    private var me: UUID?
    private var profiles: [UUID: Profile] = [:]
    private var friendships: [Friendship] = []
    private var pings: [UUID: Ping] = [:]
    private var blocked: Set<UUID> = []
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    public init(signedInAs profile: Profile? = nil, friends: [Profile] = [], pings: [Ping] = []) {
        if let profile {
            me = profile.id
            profiles[profile.id] = profile
            for friend in friends {
                profiles[friend.id] = friend
                friendships.append(Friendship(
                    id: UUID(),
                    requesterID: profile.id,
                    addresseeID: friend.id,
                    status: .accepted,
                    createdAt: Date()
                ))
            }
            for ping in pings {
                self.pings[ping.userID] = ping
            }
        }
    }

    /// The stock preview world: signed in, three friends, two of them out.
    public static func populated() -> InMemorySocialBackend {
        let me = Profile(id: UUID(), displayName: "Harry", grade: 11, avatarEmoji: "\u{1F9E0}", friendCode: "78TH-K3QP")
        let noam = Profile(id: UUID(), displayName: "Noam", grade: 11, avatarEmoji: "\u{1F3C0}")
        let eitan = Profile(id: UUID(), displayName: "Eitan", grade: 12, avatarEmoji: "\u{1F4DA}")
        let maya = Profile(id: UUID(), displayName: "Maya", grade: 11, avatarEmoji: "\u{1F3B8}")

        return InMemorySocialBackend(
            signedInAs: me,
            friends: [noam, eitan, maya],
            pings: [
                Ping(userID: noam.id, locationKey: .lounge4, noteKey: .freeNow,
                     createdAt: Date().addingTimeInterval(-240), expiresAt: Date().addingTimeInterval(1800)),
                Ping(userID: eitan.id, locationKey: .library, noteKey: .studying,
                     createdAt: Date().addingTimeInterval(-900), expiresAt: Date().addingTimeInterval(900))
            ]
        )
    }

    // MARK: Identity

    public func currentUserID() async -> UUID? { me }

    @discardableResult
    public func signInWithApple(idToken: String, nonce: String) async throws -> UUID {
        let id = me ?? UUID()
        me = id
        if profiles[id] == nil {
            profiles[id] = Profile(id: id, displayName: "You", friendCode: "78TH-DEMO")
        }
        return id
    }

    public func signOut() async throws { me = nil }

    public func currentProfile() async throws -> Profile? {
        guard let me else { return nil }
        return profiles[me]
    }

    @discardableResult
    public func saveProfile(displayName: String, grade: Int?, avatarEmoji: String) async throws -> Profile {
        guard let me else { throw SocialBackendError.notSignedIn }
        let profile = Profile(
            id: me,
            displayName: displayName,
            grade: grade,
            avatarEmoji: avatarEmoji,
            friendCode: profiles[me]?.friendCode ?? "78TH-DEMO"
        )
        profiles[me] = profile
        return profile
    }

    public func deleteAccount() async throws {
        guard let me else { return }
        profiles[me] = nil
        pings[me] = nil
        friendships.removeAll { $0.requesterID == me || $0.addresseeID == me }
        self.me = nil
    }

    // MARK: Friends

    public func friends() async throws -> [Profile] {
        guard let me else { return [] }
        return friendships
            .filter { $0.status == .accepted && ($0.requesterID == me || $0.addresseeID == me) }
            .compactMap { profiles[$0.otherSide(from: me)] }
            .sorted { $0.displayName < $1.displayName }
    }

    public func pendingRequests() async throws -> [FriendRequest] {
        guard let me else { return [] }
        return friendships
            .filter { $0.status == .pending && ($0.requesterID == me || $0.addresseeID == me) }
            .compactMap { friendship in
                guard let profile = profiles[friendship.otherSide(from: me)] else { return nil }
                return FriendRequest(friendship: friendship, profile: profile, isOutgoing: friendship.requesterID == me)
            }
    }

    @discardableResult
    public func sendFriendRequest(code: String) async throws -> Profile {
        guard let me else { throw SocialBackendError.notSignedIn }
        guard let match = profiles.values.first(where: { $0.friendCode == code }) else {
            throw SocialBackendError.unknownFriendCode
        }
        guard match.id != me else { throw SocialBackendError.cannotAddYourself }
        friendships.append(Friendship(id: UUID(), requesterID: me, addresseeID: match.id, status: .pending, createdAt: Date()))
        return match
    }

    public func respondToRequest(friendshipID: UUID, accept: Bool) async throws {
        guard let index = friendships.firstIndex(where: { $0.id == friendshipID }) else { return }
        if accept {
            friendships[index].status = .accepted
        } else {
            friendships.remove(at: index)
        }
        notify()
    }

    public func removeFriend(userID: UUID) async throws {
        guard let me else { return }
        friendships.removeAll {
            ($0.requesterID == me && $0.addresseeID == userID) || ($0.requesterID == userID && $0.addresseeID == me)
        }
        notify()
    }

    public func block(userID: UUID) async throws {
        blocked.insert(userID)
        try await removeFriend(userID: userID)
    }

    public func unblock(userID: UUID) async throws { blocked.remove(userID) }

    public func blockedProfiles() async throws -> [Profile] {
        blocked.compactMap { profiles[$0] }
    }

    // MARK: Pings

    public func livePings() async throws -> [FriendPing] {
        guard let me else { return [] }
        let friendIDs = Set(
            friendships
                .filter { $0.status == .accepted && ($0.requesterID == me || $0.addresseeID == me) }
                .map { $0.otherSide(from: me) }
        )
        return pings.values
            .filter { friendIDs.contains($0.userID) && $0.isLive() && !blocked.contains($0.userID) }
            .compactMap { ping in
                guard let profile = profiles[ping.userID] else { return nil }
                return FriendPing(ping: ping, profile: profile)
            }
            .sorted { $0.ping.createdAt > $1.ping.createdAt }
    }

    public func sendPing(location: PingLocation, note: PingNote?, expiresAt: Date) async throws {
        guard let me else { throw SocialBackendError.notSignedIn }
        pings[me] = Ping(userID: me, locationKey: location, noteKey: note, createdAt: Date(), expiresAt: expiresAt)
        notify()
    }

    public func clearMyPings() async throws {
        guard let me else { return }
        pings[me] = nil
        notify()
    }

    public nonisolated func observePings() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.register(continuation, id: id) }
            continuation.onTermination = { _ in
                Task { await self.unregister(id: id) }
            }
        }
    }

    private func register(_ continuation: AsyncStream<Void>.Continuation, id: UUID) {
        continuations[id] = continuation
    }

    private func unregister(id: UUID) {
        continuations[id] = nil
    }

    private func notify() {
        for continuation in continuations.values { continuation.yield(()) }
    }

    // MARK: Devices, rotation, import

    public func registerDeviceToken(_ token: String) async throws {}
    public func unregisterDeviceToken(_ token: String) async throws {}

    public func fetchRotationFile() async throws -> SignedRotationFile {
        throw SocialBackendError.notConfigured
    }

    public func parseSchedule(text: String?, imageData: Data?) async throws -> String {
        throw SocialBackendError.notConfigured
    }
}
