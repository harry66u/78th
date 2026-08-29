import Foundation
import Observation
import ScheduleEngine

/// The app's owner of everything social: identity, friends, and live pings.
///
/// Nothing here caches a location to disk. The ping list exists while the app is
/// open and is thrown away when it closes, which is the in-memory half of "no
/// history".
@MainActor
@Observable
public final class SocialStore {

    public enum SignInState: Equatable {
        case unknown
        case signedOut
        /// Signed in but no profile yet: onboarding is not finished.
        case needsProfile
        case ready(Profile)
    }

    public private(set) var state: SignInState = .unknown
    public private(set) var friends: [Profile] = []
    public private(set) var requests: [FriendRequest] = []
    public private(set) var blocked: [Profile] = []
    public private(set) var groups: [LocationGroup] = []
    public private(set) var myPing: Ping?
    public private(set) var isLoading = false
    public var lastError: String?

    /// "Invisible for the day": stops sending and clears anything already out
    /// there. Reading is unaffected, because hiding from your friends while
    /// still watching them would be the creepy version of this feature.
    public private(set) var invisibleUntil: Date?

    private let backend: any SocialBackend
    private var realtimeTask: Task<Void, Never>?

    public init(backend: any SocialBackend) {
        self.backend = backend
        invisibleUntil = AppIdentifiers.invisibleUntil()
    }

    public var isInvisible: Bool {
        guard let invisibleUntil else { return false }
        return invisibleUntil > Date()
    }

    public var profile: Profile? {
        if case .ready(let profile) = state { return profile }
        return nil
    }

    public var isSignedIn: Bool {
        switch state {
        case .ready, .needsProfile: return true
        case .signedOut, .unknown: return false
        }
    }

    // MARK: - Session

    public func restore() async {
        guard await backend.currentUserID() != nil else {
            state = .signedOut
            return
        }
        do {
            if let profile = try await backend.currentProfile() {
                state = .ready(profile)
                await refreshAll()
                startRealtime()
            } else {
                state = .needsProfile
            }
        } catch {
            report(error)
            state = .needsProfile
        }
    }

    public func signInWithApple(idToken: String, nonce: String) async {
        do {
            _ = try await backend.signInWithApple(idToken: idToken, nonce: nonce)
            await restore()
        } catch {
            report(error)
        }
    }

    public func completeProfile(displayName: String, grade: Int?, avatarEmoji: String) async {
        do {
            let profile = try await backend.saveProfile(
                displayName: displayName,
                grade: grade,
                avatarEmoji: avatarEmoji
            )
            state = .ready(profile)
            await refreshAll()
            startRealtime()
        } catch {
            report(error)
        }
    }

    public func signOut() async {
        stopRealtime()
        try? await backend.clearMyPings()
        try? await backend.signOut()
        friends = []
        requests = []
        groups = []
        myPing = nil
        state = .signedOut
    }

    public func deleteAccount() async {
        stopRealtime()
        do {
            try await backend.deleteAccount()
            friends = []
            requests = []
            groups = []
            myPing = nil
            state = .signedOut
        } catch {
            report(error)
        }
    }

    // MARK: - Refresh

    public func refreshAll() async {
        isLoading = true
        defer { isLoading = false }
        friends = await tryFetch { try await self.backend.friends() } ?? friends
        requests = await tryFetch { try await self.backend.pendingRequests() } ?? requests
        applyPings(await tryFetch { try await self.backend.livePings() } ?? [])
    }

    public func refreshPings() async {
        guard let pings = await tryFetch({ try await self.backend.livePings() }) else { return }
        applyPings(pings)
    }

    private func applyPings(_ pings: [FriendPing]) {
        groups = LocationGroup.group(pings)
    }

    // MARK: - Realtime

    /// Live updates only while the app is open, per the spec. There is no
    /// background subscription and nothing arrives while the phone is away.
    public func startRealtime() {
        guard realtimeTask == nil else { return }
        realtimeTask = Task { [weak self] in
            guard let self else { return }
            for await _ in self.backend.observePings() {
                if Task.isCancelled { return }
                await self.refreshPings()
            }
        }
    }

    public func stopRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil
    }

    // MARK: - Pings

    /// The main loop: one tap. `currentPeriodEnd` comes from the local schedule
    /// engine, so a ping never outlives the period it was sent in.
    public func ping(_ location: PingLocation, note: PingNote? = nil, currentPeriodEnd: Date?) async {
        guard !isInvisible else {
            lastError = "You are invisible for the day. Turn it off to ping."
            return
        }
        let now = Date()
        let expiry = PingPolicy.expiry(from: now, currentPeriodEnd: currentPeriodEnd)
        do {
            try await backend.sendPing(location: location, note: note, expiresAt: expiry)
            if let id = await backend.currentUserID() {
                myPing = Ping(userID: id, locationKey: location, noteKey: note, createdAt: now, expiresAt: expiry)
            }
            PingOutbox.shared.confirm(
                PingOutbox.Entry(location: location, note: note, createdAt: now, expiresAt: expiry)
            )
            await refreshPings()
        } catch {
            report(error)
        }
    }

    /// Sends anything the widget queued while offline.
    public func flushOutbox() async {
        guard let entry = PingOutbox.shared.pending(), !isInvisible else { return }
        do {
            try await backend.sendPing(location: entry.location, note: entry.note, expiresAt: entry.expiresAt)
            PingOutbox.shared.confirm(entry)
            await refreshPings()
        } catch {
            // Left queued. A failed flush is not worth an alert.
        }
    }

    public func clearMyPing() async {
        do {
            try await backend.clearMyPings()
            myPing = nil
            await refreshPings()
        } catch {
            report(error)
        }
    }

    public func setInvisibleForToday(_ invisible: Bool, until endOfDay: Date) async {
        if invisible {
            invisibleUntil = endOfDay
            AppIdentifiers.sharedDefaults?.set(
                endOfDay.timeIntervalSince1970,
                forKey: AppIdentifiers.DefaultsKey.invisibleUntil
            )
            await clearMyPing()
        } else {
            invisibleUntil = nil
            AppIdentifiers.sharedDefaults?.removeObject(forKey: AppIdentifiers.DefaultsKey.invisibleUntil)
        }
        // The watch pings the server on its own, so it has to be told at once
        // rather than at the next schedule edit.
        WatchSyncService.shared.setInvisible(until: invisibleUntil)
    }

    // MARK: - Friends

    public func addFriend(code: String) async -> Profile? {
        do {
            let profile = try await backend.sendFriendRequest(code: code)
            await refreshAll()
            return profile
        } catch {
            report(error)
            return nil
        }
    }

    public func respond(to request: FriendRequest, accept: Bool) async {
        do {
            try await backend.respondToRequest(friendshipID: request.friendship.id, accept: accept)
            await refreshAll()
        } catch {
            report(error)
        }
    }

    public func removeFriend(_ profile: Profile) async {
        do {
            try await backend.removeFriend(userID: profile.id)
            await refreshAll()
        } catch {
            report(error)
        }
    }

    public func block(_ profile: Profile) async {
        do {
            try await backend.block(userID: profile.id)
            await refreshBlocked()
            await refreshAll()
        } catch {
            report(error)
        }
    }

    public func unblock(_ profile: Profile) async {
        do {
            try await backend.unblock(userID: profile.id)
            await refreshBlocked()
        } catch {
            report(error)
        }
    }

    public func refreshBlocked() async {
        blocked = await tryFetch { try await self.backend.blockedProfiles() } ?? blocked
    }

    // MARK: - Schedule import

    /// Runs the paste or photo through the backend's parser function.
    ///
    /// The parse is the one time schedule text leaves the phone, and it leaves
    /// as anonymous text: the function stores nothing and the result comes
    /// straight back for the student to confirm.
    public func parseSchedule(text: String?, imageData: Data?) async throws -> String {
        try await backend.parseSchedule(text: text, imageData: imageData)
    }

    /// The signed shared rotation, if this build has a backend.
    public func fetchRotationFile() async throws -> SignedRotationFile {
        try await backend.fetchRotationFile()
    }

    // MARK: - Devices

    public func registerDeviceToken(_ token: String) async {
        try? await backend.registerDeviceToken(token)
    }

    public func unregisterDeviceToken(_ token: String) async {
        try? await backend.unregisterDeviceToken(token)
    }

    // MARK: - Errors

    private func tryFetch<T>(_ work: () async throws -> T) async -> T? {
        do {
            return try await work()
        } catch {
            report(error)
            return nil
        }
    }

    private func report(_ error: any Error) {
        if let backendError = error as? SocialBackendError {
            lastError = backendError.errorDescription
        } else {
            lastError = error.localizedDescription
        }
    }
}
