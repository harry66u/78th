import Foundation
import UIKit
import UserNotifications

/// APNs registration, kept small on purpose.
///
/// Notifications are off by default and the student turns them on explicitly.
/// The muting rule lives on the server, which cannot see the schedule, so the
/// app sends nothing but the token: the Edge Function's job is to respect the
/// preference, and the app's job is to not ask for permission it does not need.
@MainActor
final class PushRegistration {

    static let shared = PushRegistration()

    private var pendingToken: String?

    func setEnabled(_ enabled: Bool, social: SocialStore) async {
        guard enabled else {
            if let token = pendingToken {
                await social.unregisterDeviceToken(token)
            }
            return
        }

        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        UIApplication.shared.registerForRemoteNotifications()
        if let token = pendingToken {
            await social.registerDeviceToken(token)
        }
    }

    /// Called from the app delegate adaptor once APNs hands over a token.
    func receive(deviceToken: Data, social: SocialStore) async {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        pendingToken = token
        await social.registerDeviceToken(token)
    }
}
