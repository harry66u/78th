import Foundation
import Observation
import ScheduleEngine

/// The watch's owner of identity and pings.
///
/// Unlike the schedule, this does **not** mirror the phone. The watch holds its
/// own Supabase session and talks to the server itself, because the whole reason
/// the watch app exists is that the phone is in a locker — and a ping that needs
/// the phone in range would fail at exactly the moment it is wanted.
///
/// Its own session, not a copy of the phone's: Supabase rotates refresh tokens,
/// so two devices sharing one session would keep invalidating each other. Each
/// device signs in with Apple separately and gets its own token chain for the
/// same account.
///
/// What it deliberately cannot do is anything that needs a keyboard — making a
/// profile, adding a friend by code, blocking someone. Those stay on the phone,
/// where they are rare and where there is somewhere to type.
@MainActor
@Observable
final class WatchSocialStore {

    enum State: Equatable {
        /// This build has no backend at all, which is a supported build: the
        /// schedule half of the app needs no server.
        case unconfigured
        /// Before the first `restore()`. Distinct from `signedOut` so that a
        /// student who *is* signed in does not watch the sign-in screen flash
        /// past every time they raise their wrist.
        case unknown
        case signedOut
        /// Signed in, but the account has no profile yet. Making one needs a
        /// keyboard, so the watch sends the student to their phone.
        case needsProfileOnPhone
        case ready(Profile)
    }

    private(set) var state: State = .unknown
    private(set) var groups: [LocationGroup] = []
    private(set) var friendCount = 0
    /// Where this device last said the student was, read back from the outbox
    /// so it survives the app being suspended between two wrist raises. It is
    /// the outbox entry rather than a `Ping` because the server never hands back
    /// your own row, and a `Ping` here would need a user id nobody has.
    private(set) var myPing: PingOutbox.Entry?
    private(set) var isLoading = false
    private(set) var isSending = false
    var lastError: String?

    /// Set by the phone and carried in the schedule payload. The watch honours
    /// it and does not offer a second switch, because two switches for one
    /// privacy promise is how the promise gets broken.
    private(set) var invisibleUntil: Date?

    private let backend: (any SocialBackend)?
    private var realtimeTask: Task<Void, Never>?

    init(backend: (any SocialBackend)? = nil) {
        if let backend {
            self.backend = backend
        } else if let configuration = SupabaseConfiguration.fromBundle() {
            self.backend = SupabaseSocialBackend(configuration: configuration)
        } else {
            self.backend = nil
        }

        state = self.backend == nil ? .unconfigured : .unknown
        myPing = PingOutbox.shared.lastConfirmedEntry().flatMap { $0.isLive() ? $0 : nil }
        invisibleUntil = ScheduleMirror.load()?.invisibleUntil

        // Both stores watch the mirror independently rather than one calling the
        // other, so neither has to know the other exists.
        _ = NotificationCenter.default.addObserver(
            forName: .scheduleMirrorDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.invisibleUntil = ScheduleMirror.load()?.invisibleUntil
            }
        }
    }

    // MARK: - Derived state

    var isConfigured: Bool { backend != nil }

    var isSignedIn: Bool {
        switch state {
        case .ready, .needsProfileOnPhone: return true
        case .signedOut, .unconfigured, .unknown: return false
        }
    }

    var profile: Profile? {
        if case .ready(let profile) = state { return profile }
        return nil
    }

    var isInvisible: Bool {
        guard let invisibleUntil else { return false }
        return invisibleUntil > Date()
    }

    var hasFriends: Bool { friendCount > 0 }

    // MARK: - Session

    func restore() async {
        guard let backend else { return }
        guard await backend.currentUserID() != nil else {
            state = .signedOut
            return
        }
        do {
            if let profile = try await backend.currentProfile() {
                state = .ready(profile)
                await refresh()
            } else {
                state = .needsProfileOnPhone
            }
        } catch {
            report(error)
            state = .needsProfileOnPhone
        }
    }

    func signInWithApple(idToken: String, nonce: String) async {
        guard let backend else { return }
        do {
            _ = try await backend.signInWithApple(idToken: idToken, nonce: nonce)
            await restore()
        } catch {
            report(error)
        }
    }

    // MARK: - Refresh

    func refresh() async {
        guard let backend, isSignedIn else { return }
        isLoading = true
        defer { isLoading = false }

        if let friends = try? await backend.friends() {
            friendCount = friends.count
        }
        await refreshPings()
    }

    func refreshPings() async {
        guard let backend, isSignedIn else { return }
        guard let pings = try? await backend.livePings() else { return }
        groups = LocationGroup.group(pings)
    }

    // MARK: - Realtime

    /// Live only while the pings page is on screen, which is the same rule the
    /// phone follows. watchOS suspends the app when the wrist drops, so the
    /// subscription is naturally short-lived rather than a background drain.
    func startRealtime() {
        guard realtimeTask == nil, let backend, isSignedIn else { return }
        realtimeTask = Task { [weak self] in
            for await _ in backend.observePings() {
                if Task.isCancelled { return }
                await self?.refreshPings()
            }
        }
    }

    func stopRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil
    }

    // MARK: - Pings

    /// The whole feature, from the wrist: one tap.
    ///
    /// `currentPeriodEnd` comes from the watch's own copy of the schedule, so
    /// the expiry is computed on the device exactly as it is on the phone. The
    /// server is told an instant and never a schedule.
    func ping(_ location: PingLocation, note: PingNote?, currentPeriodEnd: Date?) async {
        guard let backend else { return }
        guard !isInvisible else {
            lastError = "You are invisible for the day. Turn it off on your iPhone."
            return
        }

        // Cleared up front so the caller can use it to tell this send apart
        // from one that failed earlier.
        lastError = nil
        isSending = true
        defer { isSending = false }

        let now = Date()
        let expiry = PingPolicy.expiry(from: now, currentPeriodEnd: currentPeriodEnd)
        let entry = PingOutbox.Entry(location: location, note: note, createdAt: now, expiresAt: expiry)

        do {
            try await backend.sendPing(location: location, note: note, expiresAt: expiry)
            PingOutbox.shared.confirm(entry)
            myPing = entry
            await refreshPings()
        } catch {
            // Held rather than dropped: a tap that the watch accepted should not
            // vanish because the lift went through a stairwell.
            PingOutbox.shared.enqueue(entry)
            report(error)
        }
    }

    /// Sends anything a failed tap left queued on this watch.
    func flushOutbox() async {
        guard let backend, !isInvisible, let entry = PingOutbox.shared.pending() else { return }
        do {
            try await backend.sendPing(
                location: entry.location,
                note: entry.note,
                expiresAt: entry.expiresAt
            )
            PingOutbox.shared.confirm(entry)
            myPing = entry
            await refreshPings()
        } catch {
            // Still queued. A failed flush is not worth interrupting anyone.
        }
    }

    func clearMyPing() async {
        guard let backend else { return }
        do {
            try await backend.clearMyPings()
            myPing = nil
            PingOutbox.shared.clearConfirmed()
            await refreshPings()
        } catch {
            report(error)
        }
    }

    func dismissError() { lastError = nil }

    // MARK: - Helpers

    private func report(_ error: any Error) {
        if let backendError = error as? SocialBackendError {
            lastError = backendError.errorDescription
        } else {
            lastError = error.localizedDescription
        }
    }
}
