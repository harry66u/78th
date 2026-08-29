import Foundation
import ScheduleEngine

/// Everything the app asks the server for.
///
/// The whole Supabase surface sits behind this protocol for two reasons: the
/// previews and tests run against an in-memory implementation, and if the client
/// SDK changes shape there is exactly one file to fix.
///
/// Note what is absent: nothing here uploads a schedule. The class schedule
/// never leaves the device.
public protocol SocialBackend: Sendable {

    // MARK: Identity
    func currentUserID() async -> UUID?
    /// Sign in with Apple only. No passwords exist in this system.
    @discardableResult
    func signInWithApple(idToken: String, nonce: String) async throws -> UUID
    func signOut() async throws
    func currentProfile() async throws -> Profile?
    @discardableResult
    func saveProfile(displayName: String, grade: Int?, avatarEmoji: String) async throws -> Profile
    /// Full deletion, not deactivation: profile, friendships, pings, tokens.
    func deleteAccount() async throws

    // MARK: Friends
    func friends() async throws -> [Profile]
    func pendingRequests() async throws -> [FriendRequest]
    /// Adding is by short code only, never by contacts or the school directory.
    @discardableResult
    func sendFriendRequest(code: String) async throws -> Profile
    func respondToRequest(friendshipID: UUID, accept: Bool) async throws
    func removeFriend(userID: UUID) async throws
    func block(userID: UUID) async throws
    func unblock(userID: UUID) async throws
    func blockedProfiles() async throws -> [Profile]

    // MARK: Pings
    /// Live pings from accepted friends. Row level security, not this call, is
    /// what guarantees nobody else's rows come back.
    func livePings() async throws -> [FriendPing]
    func sendPing(location: PingLocation, note: PingNote?, expiresAt: Date) async throws
    /// Used by "go invisible" and by leaving a spot early.
    func clearMyPings() async throws
    /// Fires whenever a friend's ping changes while the app is open.
    func observePings() -> AsyncStream<Void>

    // MARK: Devices
    func registerDeviceToken(_ token: String) async throws
    func unregisterDeviceToken(_ token: String) async throws

    // MARK: Shared rotation and import
    func fetchRotationFile() async throws -> SignedRotationFile
    /// Returns the raw model response. Decoding and review happen on device.
    func parseSchedule(text: String?, imageData: Data?) async throws -> String
}

public enum SocialBackendError: LocalizedError, Equatable {
    case notSignedIn
    case notConfigured
    case unknownFriendCode
    case cannotAddYourself
    case alreadyFriends
    case rateLimited
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in to use pings."
        case .notConfigured: return "This build has no backend configured."
        case .unknownFriendCode: return "No one has that code."
        case .cannotAddYourself: return "That is your own code."
        case .alreadyFriends: return "You are already friends."
        case .rateLimited: return "Too many requests. Try again in a minute."
        case .server(let message): return message
        }
    }
}
