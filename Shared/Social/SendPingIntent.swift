import AppIntents
import Foundation
import SwiftData
import WidgetKit
import ScheduleEngine

/// Sending a ping from a widget button, without launching the app.
///
/// The expiry is computed on the device from the student's own schedule, which
/// is the only place that knows when the current period ends. The schedule
/// never leaves the phone, so the server is told only an instant.
public struct SendPingIntent: AppIntent {

    public static var title: LocalizedStringResource = "Send a ping"
    public static var description = IntentDescription("Tell your friends which spot you are at.")
    /// The widget button should not bounce the student into the app.
    public static var openAppWhenRun: Bool = false

    @Parameter(title: "Location")
    public var location: PingLocationEntity

    public init() {
        self.location = PingLocationEntity(.lobby)
    }

    public init(location: PingLocation) {
        self.location = PingLocationEntity(location)
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        let value = location.location
        let now = Date()

        // The spec's rule: 45 minutes, or the end of the current period,
        // whichever comes first.
        let periodEnd = currentPeriodEnd(at: now)
        let entry = PingOutbox.Entry(
            location: value,
            note: nil,
            createdAt: now,
            expiresAt: PingPolicy.expiry(from: now, currentPeriodEnd: periodEnd)
        )

        do {
            try await PingDispatcher.shared.send(entry)
            PingOutbox.shared.confirm(entry)
        } catch {
            // Held for the app to flush on next launch rather than dropped.
            PingOutbox.shared.enqueue(entry)
        }

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }

    private func currentPeriodEnd(at now: Date) -> Date? {
        guard let container = ScheduleContainer.attempt() else { return nil }
        let engine = ScheduleConfigurationLoader.engine(from: ModelContext(container))
        return engine.snapshot(at: now).current?.end
    }
}

/// The fixed location list, exposed to App Intents and Shortcuts.
public struct PingLocationEntity: AppEntity, Identifiable, Sendable {

    public static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Location")
    public static var defaultQuery = PingLocationQuery()

    public var id: String
    public var location: PingLocation {
        PingLocation(rawValue: id) ?? .lobby
    }

    public init(_ location: PingLocation) {
        self.id = location.rawValue
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(location.displayName)")
    }
}

public struct PingLocationQuery: EntityQuery {

    public init() {}

    public func entities(for identifiers: [String]) async throws -> [PingLocationEntity] {
        identifiers.compactMap { PingLocation(rawValue: $0).map(PingLocationEntity.init) }
    }

    public func suggestedEntities() async throws -> [PingLocationEntity] {
        PingLocation.allCases.map(PingLocationEntity.init)
    }
}

/// Whoever can actually talk to the backend registers here at launch. The intent
/// runs in the widget extension, where the app's service graph does not exist.
public actor PingDispatcher {

    public static let shared = PingDispatcher()

    private var backend: (any SocialBackend)?

    public func use(_ backend: any SocialBackend) {
        self.backend = backend
    }

    /// Builds a backend on demand from the bundle configuration, which is what
    /// happens inside the widget extension.
    private func resolvedBackend() -> (any SocialBackend)? {
        if let backend { return backend }
        guard let configuration = SupabaseConfiguration.fromBundle() else { return nil }
        let created = SupabaseSocialBackend(configuration: configuration)
        backend = created
        return created
    }

    public func send(_ entry: PingOutbox.Entry) async throws {
        guard let backend = resolvedBackend() else { throw SocialBackendError.notConfigured }
        try await backend.sendPing(
            location: entry.location,
            note: entry.note,
            expiresAt: entry.expiresAt
        )
    }
}
