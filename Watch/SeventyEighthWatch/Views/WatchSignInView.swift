import AuthenticationServices
import SwiftUI

/// Signing in on the wrist.
///
/// The watch signs in for itself rather than borrowing the phone's session.
/// Supabase rotates refresh tokens, so two devices sharing one session spend
/// their time invalidating each other; two sign-ins give two token chains for
/// the same account and no fight. Sign in with Apple asks for nothing to type,
/// which is what makes it viable on a screen this size.
struct WatchSignInView: View {

    @Environment(WatchSocialStore.self) private var social
    @State private var coordinator = SignInWithAppleCoordinator()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Text("Pings need an account")
                    .font(.headline)

                Text("Your schedule works without one. This is only so friends can find you during frees.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                SignInWithAppleButton(.signIn) { request in
                    coordinator.configure(request)
                } onCompletion: { result in
                    guard let credentials = coordinator.credentials(from: result) else { return }
                    Task {
                        await social.signInWithApple(
                            idToken: credentials.idToken,
                            nonce: credentials.nonce
                        )
                    }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 40)
                .padding(.top, 4)

                if let message = coordinator.errorMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
