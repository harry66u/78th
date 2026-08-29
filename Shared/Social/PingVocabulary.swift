import Foundation

/// The complete vocabulary of the ping feature.
///
/// Both lists are closed enums, not text fields. That is the design decision
/// that keeps this out of messaging territory: there is no way to send an
/// arbitrary string to another student, so there is nothing to moderate and
/// nothing that looks like a chat app to an adult who opens the phone.
///
/// The build spec flags confirming these names against the actual building as
/// an open question. Changing one is a one-line edit here plus a migration of
/// the `location_key` check constraint in the database.
public enum PingLocation: String, CaseIterable, Codable, Identifiable, Sendable {

    case lobby
    case lounge3
    case lounge4
    case lounge6
    case library
    case cafeteria
    case gym
    case beitMidrash
    case outside

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .lobby: return "Lobby"
        case .lounge3: return "3rd Floor Lounge"
        case .lounge4: return "4th Floor Lounge"
        case .lounge6: return "6th Floor Lounge"
        case .library: return "Library"
        case .cafeteria: return "Cafeteria"
        case .gym: return "Gym"
        case .beitMidrash: return "Beit Midrash"
        case .outside: return "Outside"
        }
    }

    /// Short enough for a widget button and a grouped list header.
    public var shortName: String {
        switch self {
        case .lounge3: return "3rd Lounge"
        case .lounge4: return "4th Lounge"
        case .lounge6: return "6th Lounge"
        default: return displayName
        }
    }

    public var symbolName: String {
        switch self {
        case .lobby: return "door.left.hand.open"
        case .lounge3, .lounge4, .lounge6: return "sofa"
        case .library: return "books.vertical"
        case .cafeteria: return "fork.knife"
        case .gym: return "figure.basketball"
        case .beitMidrash: return "book.closed"
        case .outside: return "sun.max"
        }
    }
}

/// The optional tag on a ping. Also a closed list, for the same reason.
public enum PingNote: String, CaseIterable, Codable, Identifiable, Sendable {

    case freeNow
    case studying
    case eating
    case comeThrough
    case leavingSoon

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .freeNow: return "Free now"
        case .studying: return "Studying"
        case .eating: return "Eating"
        case .comeThrough: return "Come through"
        case .leavingSoon: return "Leaving soon"
        }
    }

    public var symbolName: String {
        switch self {
        case .freeNow: return "checkmark.circle"
        case .studying: return "pencil.and.list.clipboard"
        case .eating: return "takeoutbag.and.cup.and.straw"
        case .comeThrough: return "hand.wave"
        case .leavingSoon: return "figure.walk.departure"
        }
    }
}

public enum PingPolicy {
    /// A ping lives for 45 minutes, or until the end of the current period,
    /// whichever comes first.
    public static let maximumLifetime: TimeInterval = 45 * 60

    /// Given the end of the current period, when this ping should expire.
    public static func expiry(from now: Date, currentPeriodEnd: Date?) -> Date {
        let cap = now.addingTimeInterval(maximumLifetime)
        guard let end = currentPeriodEnd, end > now else { return cap }
        return min(cap, end)
    }
}
