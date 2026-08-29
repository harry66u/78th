import Foundation
import ScheduleEngine
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// The phone's half of the pairing.
///
/// One job: keep the watch's copy of the schedule current. It sends the whole
/// configuration as a `WCSession` *application context*, which is the right
/// primitive here for two reasons. It is a single latest-state slot rather than
/// a queue, so a student who edits five periods in a row does not send five
/// transfers the watch has to replay. And it is delivered in the background,
/// waking the watch app to write its mirror even when nobody has raised their
/// wrist.
///
/// What it deliberately does *not* do is push a transfer every time the
/// countdown changes. The complication's timeline is precomputed a day ahead
/// from the schedule it already has, so minute-to-minute freshness costs no
/// radio at all. A transfer is only needed when the schedule itself changes,
/// which is a handful of times a year.
final class WatchSyncService: NSObject, @unchecked Sendable {

    static let shared = WatchSyncService()

    private let lock = NSLock()
    /// The most recent payload, kept so a watch that pairs, installs, or comes
    /// back in range later can be caught up without waiting for an edit.
    private var latest: ScheduleSyncPayload?
    /// Fingerprint of the last payload that actually went out, so repeated
    /// reloads of an unchanged schedule are free.
    private var lastSentFingerprint: Int?

    private override init() {
        super.init()
    }

    // MARK: - Lifecycle

    func activate() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        #endif
    }

    // MARK: - Sending

    /// Called by `ScheduleStore` after every reload. Cheap when nothing changed.
    func send(_ payload: ScheduleSyncPayload) {
        let trimmed = payload.trimmedForTransfer()
        let fingerprint = Self.fingerprint(of: trimmed)

        lock.lock()
        let alreadySent = fingerprint == lastSentFingerprint
        latest = trimmed
        lock.unlock()

        guard !alreadySent else { return }

        if push(trimmed) {
            lock.lock()
            lastSentFingerprint = fingerprint
            lock.unlock()
        }
        // A failed push leaves the fingerprint unset on purpose: the next
        // reload, activation, or watch-state change tries again.
    }

    /// Re-sends whatever the phone last had, without the change check. Used when
    /// the far side has just become able to receive.
    private func resend() {
        lock.lock()
        let payload = latest
        lock.unlock()
        guard let payload else { return }
        if push(payload) {
            let fingerprint = Self.fingerprint(of: payload)
            lock.lock()
            lastSentFingerprint = fingerprint
            lock.unlock()
        }
    }

    /// `generatedAt` moves on every build, so it is left out: two payloads that
    /// would draw the same watch face are the same payload.
    private static func fingerprint(of payload: ScheduleSyncPayload) -> Int {
        var hasher = Hasher()
        hasher.combine(payload.configuration)
        hasher.combine(payload.bellTimesConfirmed)
        hasher.combine(payload.rotationVersion)
        return hasher.finalize()
    }

    @discardableResult
    private func push(_ payload: ScheduleSyncPayload) -> Bool {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        guard session.activationState == .activated else { return false }
        #if os(iOS)
        // No watch, or the watch app not installed, is the common case. It is
        // not an error and it is not worth retrying until that changes.
        guard session.isPaired, session.isWatchAppInstalled else { return false }
        #endif
        guard let data = try? payload.encoded() else { return false }
        do {
            try session.updateApplicationContext([ScheduleSyncPayload.transferKey: data])
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }
}

#if canImport(WatchConnectivity)

extension WatchSyncService: WCSessionDelegate {

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard activationState == .activated else { return }
        resend()
    }

    /// The watch asking for a fresh copy, which is what happens when a student
    /// opens the watch app with the phone in range.
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard message[ScheduleSyncPayload.requestKey] != nil else {
            replyHandler([:])
            return
        }
        lock.lock()
        let payload = latest
        lock.unlock()

        guard let payload, let data = try? payload.encoded() else {
            replyHandler([:])
            return
        }
        replyHandler([ScheduleSyncPayload.transferKey: data])
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        resend()
    }

    #if os(iOS)
    /// A watch was paired, or the watch app was installed. Either way the far
    /// side has nothing yet.
    func sessionWatchStateDidChange(_ session: WCSession) {
        lock.lock()
        lastSentFingerprint = nil
        lock.unlock()
        resend()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The student switched to a different watch. Activate again so the new one
    /// gets the schedule.
    func sessionDidDeactivate(_ session: WCSession) {
        lock.lock()
        lastSentFingerprint = nil
        lock.unlock()
        WCSession.default.activate()
    }
    #endif
}

#endif
