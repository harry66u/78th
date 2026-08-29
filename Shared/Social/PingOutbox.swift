import Foundation

/// A one-slot outbox in the App Group, so a ping tapped from the widget is not
/// lost when the network is not there.
///
/// It holds one pending ping, never a history: replacing it is the correct
/// behaviour, and nothing accumulates that could be read later.
public final class PingOutbox: @unchecked Sendable {

    public static let shared = PingOutbox()

    private let defaults: UserDefaults?
    private let pendingKey = "pingOutbox.pending"
    private let confirmedKey = "pingOutbox.confirmed"
    private let lock = NSLock()

    public init(defaults: UserDefaults? = AppIdentifiers.sharedDefaults) {
        self.defaults = defaults
    }

    public struct Entry: Codable, Hashable, Sendable {
        public var location: PingLocation
        public var note: PingNote?
        public var createdAt: Date
        public var expiresAt: Date

        public init(location: PingLocation, note: PingNote? = nil, createdAt: Date, expiresAt: Date) {
            self.location = location
            self.note = note
            self.createdAt = createdAt
            self.expiresAt = expiresAt
        }
    }

    // MARK: Pending

    public func enqueue(_ entry: Entry) {
        write(entry, forKey: pendingKey)
    }

    public func pending() -> Entry? {
        guard let entry: Entry = read(forKey: pendingKey) else { return nil }
        // A ping that expired while it sat in the outbox is not worth sending.
        guard entry.expiresAt > Date() else {
            clearPending()
            return nil
        }
        return entry
    }

    public func clearPending() {
        lock.lock(); defer { lock.unlock() }
        defaults?.removeObject(forKey: pendingKey)
    }

    // MARK: Confirmed

    /// Recorded after a successful send so the widget can show "Sent, Library"
    /// without querying anything.
    public func confirm(_ entry: Entry) {
        write(entry, forKey: confirmedKey)
        clearPending()
    }

    public func lastConfirmed() -> (location: PingLocation, sentAt: Date)? {
        guard let entry: Entry = read(forKey: confirmedKey) else { return nil }
        return (entry.location, entry.createdAt)
    }

    public func clearConfirmed() {
        lock.lock(); defer { lock.unlock() }
        defaults?.removeObject(forKey: confirmedKey)
    }

    // MARK: Storage

    private func write<T: Encodable>(_ value: T, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults?.set(data, forKey: key)
    }

    private func read<T: Decodable>(forKey key: String) -> T? {
        lock.lock(); defer { lock.unlock() }
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
