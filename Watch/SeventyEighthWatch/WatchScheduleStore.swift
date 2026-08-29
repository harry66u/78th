import Foundation
import Observation
import WidgetKit
import ScheduleEngine
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// The watch's owner of the schedule.
///
/// It is deliberately much smaller than the phone's `ScheduleStore`, because the
/// watch is read-only: there is no editing on the wrist, so there is nothing to
/// save, nothing to validate, and no way for the two devices to disagree about
/// who won. The phone writes, the watch mirrors.
///
/// The engine underneath is the same engine the phone and the widget run, which
/// is the whole reason the countdown on the wrist matches the one on the home
/// screen to the second.
@MainActor
@Observable
final class WatchScheduleStore {

    private(set) var engine: ScheduleEngine
    /// When the phone built the copy we are showing. Nil before the first sync.
    private(set) var syncedAt: Date?
    /// Carried across from the phone so the wrist is as honest about the
    /// placeholder bell times as the phone is.
    private(set) var bellTimesConfirmed: Bool
    private(set) var isRequesting = false

    private let receiver = WatchScheduleReceiver()

    init() {
        let payload = ScheduleMirror.load()
        engine = ScheduleEngine(configuration: payload?.configuration ?? ScheduleConfiguration())
        syncedAt = payload?.generatedAt
        bellTimesConfirmed = payload?.bellTimesConfirmed ?? false

        // The receiver writes the mirror from a background queue and announces
        // it; this is what turns a phone edit into a redraw. The store lives for
        // the life of the process, so the observer is never torn down.
        _ = NotificationCenter.default.addObserver(
            forName: .scheduleMirrorDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }

        receiver.activate()
    }

    var hasSchedule: Bool { !engine.configuration.isEmpty }
    var timeZone: TimeZone { engine.configuration.timeZone }

    func snapshot(at date: Date = Date()) -> ScheduleSnapshot {
        engine.snapshot(at: date)
    }

    func reload() {
        let payload = ScheduleMirror.load()
        engine = ScheduleEngine(configuration: payload?.configuration ?? ScheduleConfiguration())
        syncedAt = payload?.generatedAt
        bellTimesConfirmed = payload?.bellTimesConfirmed ?? false
    }

    /// Ask the phone for a copy now, rather than waiting for the background
    /// transfer. Quietly does nothing when the phone is out of range, which is
    /// the honest outcome: the watch has no other way to get a schedule, and the
    /// copy already on screen is still the best answer available.
    func requestRefresh() {
        guard !isRequesting else { return }
        isRequesting = true
        receiver.requestSchedule { [weak self] in
            Task { @MainActor in self?.isRequesting = false }
        }
    }
}

/// The `WCSession` delegate.
///
/// Kept separate from the store because session callbacks arrive on a background
/// queue and the store is main-actor. Everything this receives goes straight to
/// disk, and the store learns about it the same way the complication does — by
/// reading the mirror. One path in, so a value the screen shows is always a
/// value the complication would show too.
private final class WatchScheduleReceiver: NSObject, @unchecked Sendable {

    func activate() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        #endif
    }

    func requestSchedule(completion: @escaping () -> Void) {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else {
            completion()
            return
        }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            completion()
            return
        }
        session.sendMessage(
            [ScheduleSyncPayload.requestKey: true],
            replyHandler: { reply in
                WatchScheduleReceiver.store(reply)
                completion()
            },
            errorHandler: { _ in completion() }
        )
        #else
        completion()
        #endif
    }

    /// Decode, write, and tell the complications. A payload that does not decode
    /// is dropped: the mirror we already have is better than a half-written one.
    static func store(_ contents: [String: Any]) {
        guard let data = contents[ScheduleSyncPayload.transferKey] as? Data,
              let payload = try? ScheduleSyncPayload.decoded(from: data)
        else { return }

        guard ScheduleMirror.save(payload) else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

#if canImport(WatchConnectivity)

extension WatchScheduleReceiver: WCSessionDelegate {

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard activationState == .activated else { return }
        // Whatever arrived while this app was not running is waiting here.
        WatchScheduleReceiver.store(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        WatchScheduleReceiver.store(applicationContext)
    }
}

#endif
