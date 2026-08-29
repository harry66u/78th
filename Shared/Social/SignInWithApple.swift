import AuthenticationServices
import CryptoKit
import Foundation
// SecRandomCopyBytes. Imported by name rather than leaning on what
// AuthenticationServices happens to re-export, since this file is now compiled
// for watchOS too.
import Security

/// Sign in with Apple, with the nonce handling the identity provider requires.
///
/// No passwords exist anywhere in this system, which removes a whole category of
/// support and a whole category of breach.
///
/// Shared by the phone and the watch. Each device signs in for itself and gets
/// its own session for the same account: Supabase rotates refresh tokens, so two
/// devices sharing one session would spend their time invalidating each other.
@MainActor
@Observable
final class SignInWithAppleCoordinator {

    private(set) var rawNonce: String?
    var errorMessage: String?

    /// Called from `SignInWithAppleButton`'s request handler.
    func configure(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        rawNonce = nonce
        request.requestedScopes = [.fullName]
        request.nonce = Self.sha256(nonce)
    }

    /// Returns the identity token and the raw nonce to hand to the backend.
    func credentials(from result: Result<ASAuthorization, any Error>) -> (idToken: String, nonce: String)? {
        switch result {
        case .failure(let error):
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                errorMessage = error.localizedDescription
            }
            return nil

        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  let nonce = rawNonce
            else {
                errorMessage = "Apple did not return a usable sign-in token."
                return nil
            }
            return (token, nonce)
        }
    }

    /// A suggested display name from Apple, used only to prefill the field.
    func suggestedName(from result: Result<ASAuthorization, any Error>) -> String? {
        guard case .success(let authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let given = credential.fullName?.givenName
        else { return nil }
        return given
    }

    // MARK: - Nonce

    static func randomNonceString(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length

        while remaining > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            guard status == errSecSuccess else { continue }
            // Reject values that would bias the distribution.
            if random < 252 {
                result.append(characters[Int(random) % characters.count])
                remaining -= 1
            }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
