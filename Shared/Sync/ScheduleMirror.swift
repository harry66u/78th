import Foundation
import ScheduleEngine

public extension Notification.Name {
    /// Posted whenever a newly received schedule lands on disk. The watch app
    /// listens so the screen updates the moment the phone pushes an edit.
    static let scheduleMirrorDidChange = Notification.Name("com.seventyeighth.scheduleMirrorDidChange")
}

/// The watch's copy of the schedule, on disk in the App Group.
///
/// This is the watch-side counterpart of the phone's SwiftData store, and it
/// exists for the same reason: the complication has to answer "what class is
/// next" with the watch app not running, no network, and no phone in range.
/// A single JSON file is enough, because the engine's whole input is one value.
///
/// It is a cache and it is treated like one. Losing it costs a sync, not a
/// schedule.
public enum ScheduleMirror {

    public static let filename = "ScheduleMirror.json"

    private static let lock = NSLock()

    /// The App Group container, shared by the watch app and its complication
    /// extension. Falls back to Application Support so a build without the
    /// entitlement still works, just without the complication seeing it.
    public static var directoryURL: URL? {
        if let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroup
        ) {
            return group
        }
        return try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    public static var fileURL: URL? {
        directoryURL?.appendingPathComponent(filename, isDirectory: false)
    }

    // MARK: - Reading

    public static func load() -> ScheduleSyncPayload? {
        lock.lock()
        defer { lock.unlock() }
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? ScheduleSyncPayload.decoded(from: data)
    }

    /// What the complication provider calls. Nil means nothing has synced yet,
    /// which is a state the surfaces already know how to draw.
    public static func engine() -> ScheduleEngine? {
        guard let payload = load(), !payload.isEmpty else { return nil }
        return payload.engine
    }

    // MARK: - Writing

    /// Writes the payload and announces it. Returns false only when the
    /// container is unavailable or the write fails, in which case the caller
    /// still has the value in memory and the next sync will try again.
    @discardableResult
    public static func save(_ payload: ScheduleSyncPayload) -> Bool {
        lock.lock()
        guard let url = fileURL, let data = try? payload.encoded() else {
            lock.unlock()
            return false
        }
        // Atomic: a complication reading mid-write must never see half a file.
        var wrote = false
        do {
            try data.write(to: url, options: .atomic)
            wrote = true
        } catch {
            wrote = false
        }
        lock.unlock()

        if wrote {
            NotificationCenter.default.post(name: .scheduleMirrorDidChange, object: nil)
        }
        return wrote
    }

    public static func clear() {
        lock.lock()
        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        lock.unlock()
        NotificationCenter.default.post(name: .scheduleMirrorDidChange, object: nil)
    }
}
