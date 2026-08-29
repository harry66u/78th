import Foundation

/// Backend configuration, read from the app's Info.plist so that the URL and
/// the publishable key are set per build configuration rather than typed into
/// source.
///
/// The anon key is a publishable key: it is safe in the client precisely because
/// row level security decides what it can read. No service-role key ever ships
/// in the app.
public struct SupabaseConfiguration: Sendable {

    public let url: URL
    public let anonKey: String

    public init(url: URL, anonKey: String) {
        self.url = url
        self.anonKey = anonKey
    }

    /// Nil in a build with no backend configured, which is a legitimate state:
    /// M1 through M3 are a working schedule app with no server at all.
    public static func fromBundle(_ bundle: Bundle = .main) -> SupabaseConfiguration? {
        guard let urlString = bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String,
              let key = bundle.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
              !urlString.isEmpty, !key.isEmpty,
              let url = URL(string: urlString)
        else { return nil }
        return SupabaseConfiguration(url: url, anonKey: key)
    }

    /// The Ed25519 public key that signs the shared rotation file, base64. The
    /// device refuses any rotation file that does not verify against it.
    public static func rotationPublicKey(_ bundle: Bundle = .main) -> Data? {
        guard let encoded = bundle.object(forInfoDictionaryKey: "RotationPublicKey") as? String,
              !encoded.isEmpty
        else { return nil }
        return Data(base64Encoded: encoded)
    }
}
