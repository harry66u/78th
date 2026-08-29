import Foundation
import Supabase
import ScheduleEngine

/// The Supabase implementation of `SocialBackend`.
///
/// Pinned to supabase-swift 2.x (see `project.yml`). This is the only file that
/// imports `Supabase`, so an SDK change is contained here.
public actor SupabaseSocialBackend: SocialBackend {

    private let client: SupabaseClient
    private var pingChannel: RealtimeChannelV2?

    public init(configuration: SupabaseConfiguration) {
        self.client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.anonKey
        )
    }

    // MARK: - Identity

    public func currentUserID() async -> UUID? {
        try? await client.auth.session.user.id
    }

    @discardableResult
    public func signInWithApple(idToken: String, nonce: String) async throws -> UUID {
        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        )
        return session.user.id
    }

    public func signOut() async throws {
        try await client.auth.signOut()
    }

    public func currentProfile() async throws -> Profile? {
        guard let id = await currentUserID() else { throw SocialBackendError.notSignedIn }
        let profiles: [Profile] = try await client
            .from("profiles")
            .select()
            .eq("id", value: id.uuidString)
            .limit(1)
            .execute()
            .value
        return profiles.first
    }

    @discardableResult
    public func saveProfile(displayName: String, grade: Int?, avatarEmoji: String) async throws -> Profile {
        guard let id = await currentUserID() else { throw SocialBackendError.notSignedIn }

        struct Upsert: Encodable {
            let id: UUID
            let display_name: String
            let grade: Int?
            let avatar_emoji: String
        }

        let saved: [Profile] = try await client
            .from("profiles")
            .upsert(Upsert(id: id, display_name: displayName, grade: grade, avatar_emoji: avatarEmoji))
            .select()
            .execute()
            .value

        guard let profile = saved.first else {
            throw SocialBackendError.server("The profile did not save.")
        }
        return profile
    }

    public func deleteAccount() async throws {
        // A single server-side function so deletion is atomic and covers rows
        // the client cannot reach: auth user, profile, friendships, pings, and
        // device tokens.
        _ = try await client.rpc("delete_my_account").execute()
        try? await client.auth.signOut()
    }

    // MARK: - Friends

    public func friends() async throws -> [Profile] {
        try await client
            .rpc("my_friends")
            .execute()
            .value
    }

    public func pendingRequests() async throws -> [FriendRequest] {
        guard let me = await currentUserID() else { throw SocialBackendError.notSignedIn }

        let friendships: [Friendship] = try await client
            .from("friendships")
            .select()
            .eq("status", value: FriendshipStatus.pending.rawValue)
            .or("requester_id.eq.\(me.uuidString),addressee_id.eq.\(me.uuidString)")
            .execute()
            .value

        guard !friendships.isEmpty else { return [] }

        let otherIDs = friendships.map { $0.otherSide(from: me) }
        let profiles: [Profile] = try await client
            .from("profiles")
            .select()
            .in("id", values: otherIDs.map(\.uuidString))
            .execute()
            .value
        let profilesByID = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return friendships.compactMap { friendship in
            guard let profile = profilesByID[friendship.otherSide(from: me)] else { return nil }
            return FriendRequest(
                friendship: friendship,
                profile: profile,
                isOutgoing: friendship.requesterID == me
            )
        }
    }

    @discardableResult
    public func sendFriendRequest(code: String) async throws -> Profile {
        // A security-definer function, not a select: a student must not be able
        // to enumerate profiles by guessing codes.
        struct Params: Encodable { let code: String }
        do {
            return try await client
                .rpc("request_friend_by_code", params: Params(code: normalize(code)))
                .execute()
                .value
        } catch {
            throw mapped(error)
        }
    }

    public func respondToRequest(friendshipID: UUID, accept: Bool) async throws {
        if accept {
            struct Params: Encodable { let friendship_id: UUID }
            _ = try await client.rpc("accept_friend_request", params: Params(friendship_id: friendshipID)).execute()
        } else {
            _ = try await client.from("friendships").delete().eq("id", value: friendshipID.uuidString).execute()
        }
    }

    public func removeFriend(userID: UUID) async throws {
        struct Params: Encodable { let other_id: UUID }
        _ = try await client.rpc("remove_friend", params: Params(other_id: userID)).execute()
    }

    public func block(userID: UUID) async throws {
        struct Params: Encodable { let other_id: UUID }
        _ = try await client.rpc("block_user", params: Params(other_id: userID)).execute()
    }

    public func unblock(userID: UUID) async throws {
        struct Params: Encodable { let other_id: UUID }
        _ = try await client.rpc("unblock_user", params: Params(other_id: userID)).execute()
    }

    public func blockedProfiles() async throws -> [Profile] {
        try await client.rpc("my_blocked_users").execute().value
    }

    // MARK: - Pings

    /// One row of `friend_pings`, a security-invoker view that joins live pings
    /// to their author's profile.
    private struct FriendPingRow: Decodable {
        let id: UUID
        let user_id: UUID
        let location_key: PingLocation
        let note_key: PingNote?
        let created_at: Date
        let expires_at: Date
        let display_name: String
        let grade: Int?
        let avatar_emoji: String
    }

    public func livePings() async throws -> [FriendPing] {
        let rows: [FriendPingRow] = try await client
            .from("friend_pings")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value

        return rows.map { row in
            FriendPing(
                ping: Ping(
                    id: row.id,
                    userID: row.user_id,
                    locationKey: row.location_key,
                    noteKey: row.note_key,
                    createdAt: row.created_at,
                    expiresAt: row.expires_at
                ),
                profile: Profile(
                    id: row.user_id,
                    displayName: row.display_name,
                    grade: row.grade,
                    avatarEmoji: row.avatar_emoji
                )
            )
        }
    }

    public func sendPing(location: PingLocation, note: PingNote?, expiresAt: Date) async throws {
        guard let me = await currentUserID() else { throw SocialBackendError.notSignedIn }

        struct Insert: Encodable {
            let user_id: UUID
            let location_key: String
            let note_key: String?
            let expires_at: Date
        }

        // One live ping per student: a new ping replaces the old one rather than
        // appending, so there is never a trail to read.
        _ = try await client
            .from("pings")
            .upsert(
                Insert(
                    user_id: me,
                    location_key: location.rawValue,
                    note_key: note?.rawValue,
                    expires_at: expiresAt
                ),
                onConflict: "user_id"
            )
            .execute()
    }

    public func clearMyPings() async throws {
        guard let me = await currentUserID() else { throw SocialBackendError.notSignedIn }
        _ = try await client.from("pings").delete().eq("user_id", value: me.uuidString).execute()
    }

    public nonisolated func observePings() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else { return }
                await self.startPingChannel(continuation: continuation)
            }
            continuation.onTermination = { _ in
                task.cancel()
                Task { [weak self] in await self?.stopPingChannel() }
            }
        }
    }

    private func startPingChannel(continuation: AsyncStream<Void>.Continuation) async {
        let channel = client.channel("public:pings")
        pingChannel = channel

        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "pings")
        await channel.subscribe()

        for await _ in changes {
            // The payload is deliberately ignored. Row level security governs
            // what a re-fetch returns; a realtime payload is only a hint that
            // something moved.
            continuation.yield(())
        }
        continuation.finish()
    }

    private func stopPingChannel() async {
        guard let channel = pingChannel else { return }
        await channel.unsubscribe()
        pingChannel = nil
    }

    // MARK: - Devices

    public func registerDeviceToken(_ token: String) async throws {
        guard let me = await currentUserID() else { throw SocialBackendError.notSignedIn }
        struct Insert: Encodable {
            let user_id: UUID
            let apns_token: String
            let updated_at: Date
        }
        _ = try await client
            .from("device_tokens")
            .upsert(Insert(user_id: me, apns_token: token, updated_at: Date()), onConflict: "apns_token")
            .execute()
    }

    public func unregisterDeviceToken(_ token: String) async throws {
        _ = try await client.from("device_tokens").delete().eq("apns_token", value: token).execute()
    }

    // MARK: - Rotation and import

    public func fetchRotationFile() async throws -> SignedRotationFile {
        let data = try await client.storage
            .from("public-rotation")
            .download(path: "rotation.json")
        return try JSONDecoder().decode(SignedRotationFile.self, from: data)
    }

    public func parseSchedule(text: String?, imageData: Data?) async throws -> String {
        struct Request: Encodable {
            let text: String?
            let image_base64: String?
        }
        struct Response: Decodable {
            let raw: String
        }

        let response: Response = try await client.functions.invoke(
            "parse-schedule",
            options: FunctionInvokeOptions(
                body: Request(text: text, image_base64: imageData?.base64EncodedString())
            )
        )
        return response.raw
    }

    // MARK: - Helpers

    private nonisolated func normalize(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    /// Turns the server's error strings into something a student can act on.
    private nonisolated func mapped(_ error: any Error) -> any Error {
        let message = String(describing: error).lowercased()
        if message.contains("unknown_code") { return SocialBackendError.unknownFriendCode }
        if message.contains("self_request") { return SocialBackendError.cannotAddYourself }
        if message.contains("already_friends") { return SocialBackendError.alreadyFriends }
        if message.contains("rate_limit") || message.contains("429") { return SocialBackendError.rateLimited }
        return error
    }
}
