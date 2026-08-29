import Foundation

/// A student's public identity. The only fields anyone else can see, and only
/// once a friendship is mutual.
public struct Profile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var displayName: String
    public var grade: Int?
    public var avatarEmoji: String
    /// The short code another student types to send a friend request. Never a
    /// contacts scan and never the school directory.
    public var friendCode: String?
    public var createdAt: Date?

    public init(
        id: UUID,
        displayName: String,
        grade: Int? = nil,
        avatarEmoji: String = "\u{1F642}",
        friendCode: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.grade = grade
        self.avatarEmoji = avatarEmoji
        self.friendCode = friendCode
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case grade
        case avatarEmoji = "avatar_emoji"
        case friendCode = "friend_code"
        case createdAt = "created_at"
    }
}

public enum FriendshipStatus: String, Codable, Sendable {
    case pending
    case accepted
    case blocked
}

public struct Friendship: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var requesterID: UUID
    public var addresseeID: UUID
    public var status: FriendshipStatus
    public var createdAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case requesterID = "requester_id"
        case addresseeID = "addressee_id"
        case status
        case createdAt = "created_at"
    }

    public func otherSide(from me: UUID) -> UUID {
        requesterID == me ? addresseeID : requesterID
    }
}

/// A friend request waiting on the current user.
public struct FriendRequest: Hashable, Identifiable, Sendable {
    public var id: UUID { friendship.id }
    public var friendship: Friendship
    public var profile: Profile
    /// True when the current user sent it and is waiting on the other side.
    public var isOutgoing: Bool

    public init(friendship: Friendship, profile: Profile, isOutgoing: Bool) {
        self.friendship = friendship
        self.profile = profile
        self.isOutgoing = isOutgoing
    }
}

/// A declared location. Never GPS, never background, never historical.
public struct Ping: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var userID: UUID
    public var locationKey: PingLocation
    public var noteKey: PingNote?
    public var createdAt: Date
    public var expiresAt: Date

    public init(
        id: UUID = UUID(),
        userID: UUID,
        locationKey: PingLocation,
        noteKey: PingNote? = nil,
        createdAt: Date = Date(),
        expiresAt: Date
    ) {
        self.id = id
        self.userID = userID
        self.locationKey = locationKey
        self.noteKey = noteKey
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case locationKey = "location_key"
        case noteKey = "note_key"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }

    public func isLive(at date: Date = Date()) -> Bool { expiresAt > date }
}

/// A ping joined to the friend who sent it, which is the only shape the Pings
/// screen ever renders.
public struct FriendPing: Hashable, Identifiable, Sendable {
    public var id: UUID { ping.id }
    public var ping: Ping
    public var profile: Profile

    public init(ping: Ping, profile: Profile) {
        self.ping = ping
        self.profile = profile
    }
}

/// Friends grouped under a location, sorted most recent first. The whole Pings
/// screen is a list of these.
public struct LocationGroup: Hashable, Identifiable, Sendable {
    public var id: String { location.rawValue }
    public var location: PingLocation
    public var pings: [FriendPing]

    public init(location: PingLocation, pings: [FriendPing]) {
        self.location = location
        self.pings = pings
    }

    /// Groups live pings by location. Expired pings are dropped here as well as
    /// on the server, so a stale cache can never show someone who has left.
    public static func group(_ pings: [FriendPing], at now: Date = Date()) -> [LocationGroup] {
        let live = pings.filter { $0.ping.isLive(at: now) }
        let byLocation = Dictionary(grouping: live) { $0.ping.locationKey }
        return PingLocation.allCases.compactMap { location in
            guard let group = byLocation[location], !group.isEmpty else { return nil }
            return LocationGroup(
                location: location,
                pings: group.sorted { $0.ping.createdAt > $1.ping.createdAt }
            )
        }
    }
}
