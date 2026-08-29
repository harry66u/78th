import Foundation
import ScheduleEngine

/// What the phone sends the watch.
///
/// The watch cannot read the phone's App Group container — an App Group is a
/// per-device container, not an iCloud one — so the schedule has to cross the
/// pairing as a value. `ScheduleConfiguration` is already `Codable` and already
/// the engine's entire input, so the transfer format is that value plus the two
/// flags the wrist needs to be honest about what it is showing.
///
/// Nothing here is a new source of truth. The phone's SwiftData store remains
/// the one place a schedule is edited; this is a copy, and the watch never
/// writes back.
public struct ScheduleSyncPayload: Codable, Hashable, Sendable {

    /// Bumped if the shape of this value ever changes, so an old watch paired
    /// with a new phone can say "update the app" instead of showing nonsense.
    public static let currentFormat = 1

    public var format: Int
    public var configuration: ScheduleConfiguration
    /// The placeholder bell times are a guess until a student says otherwise,
    /// and the watch says so too rather than quietly being wrong.
    public var bellTimesConfirmed: Bool
    public var rotationVersion: Int
    /// "Invisible for the day", nil when it is off or has expired.
    ///
    /// Not schedule data, and it is here anyway. The watch talks to the ping
    /// backend on its own, so a privacy switch the wrist has not heard about is
    /// a switch that lies on one of the two devices. The phone owns it; this is
    /// how the watch is told.
    public var invisibleUntil: Date?
    /// When the phone built this. Shown on the watch as "synced 4 min ago".
    public var generatedAt: Date

    public init(
        configuration: ScheduleConfiguration,
        bellTimesConfirmed: Bool = false,
        rotationVersion: Int = 0,
        invisibleUntil: Date? = nil,
        generatedAt: Date = Date(),
        format: Int = ScheduleSyncPayload.currentFormat
    ) {
        self.format = format
        self.configuration = configuration
        self.bellTimesConfirmed = bellTimesConfirmed
        self.rotationVersion = rotationVersion
        self.invisibleUntil = invisibleUntil
        self.generatedAt = generatedAt
    }

    /// True while the student has asked not to be visible to friends.
    public func isInvisible(at date: Date = Date()) -> Bool {
        guard let invisibleUntil else { return false }
        return invisibleUntil > date
    }

    public var engine: ScheduleEngine {
        ScheduleEngine(configuration: configuration)
    }

    public var isEmpty: Bool { configuration.isEmpty }

    // MARK: - Coding

    /// One encoder and one decoder, so the two sides of the pairing cannot
    /// disagree about how a `Date` is written.
    public static func encoder() -> JSONEncoder { JSONEncoder() }
    public static func decoder() -> JSONDecoder { JSONDecoder() }

    public func encoded() throws -> Data {
        try Self.encoder().encode(self)
    }

    public static func decoded(from data: Data) throws -> ScheduleSyncPayload {
        try decoder().decode(ScheduleSyncPayload.self, from: data)
    }

    // MARK: - Transfer

    /// The key the payload travels under in a `WCSession` application context
    /// or message.
    public static let transferKey = "schedulePayload"

    /// The key the watch sends to ask the phone for a fresh copy, used when a
    /// student opens the watch app and the phone is in range.
    public static let requestKey = "scheduleRequest"

    /// A copy trimmed to what will fit, and to what the watch can actually use.
    ///
    /// `WCSession`'s application context is capped at roughly a quarter of a
    /// megabyte, and a full school year of dated overrides is the only part of
    /// the configuration that grows without bound. The window itself is the
    /// engine's to decide, and it is tested there.
    public func trimmedForTransfer(now: Date = Date()) -> ScheduleSyncPayload {
        var trimmed = self
        trimmed.configuration = configuration.trimmingCalendarDays(around: now)
        return trimmed
    }
}
