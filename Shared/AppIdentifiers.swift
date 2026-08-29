import Foundation

/// Identifiers shared by the app and the widget extension.
///
/// The App Group is what lets the widget read the schedule without a network
/// call, so these strings have to match the entitlements on both targets.
/// `project.yml` is the single place they are configured.
public enum AppIdentifiers {

    public static let appBundleID = "com.seventyeighth.app"
    public static let widgetBundleID = "com.seventyeighth.app.widget"

    /// Must match `com.apple.security.application-groups` on both targets.
    public static let appGroup = "group.com.seventyeighth.app"

    /// The SwiftData store file inside the App Group container.
    public static let storeFilename = "Schedule.store"

    public enum WidgetKind {
        public static let schedule = "SeventyEighthScheduleWidget"
        public static let lockScreen = "SeventyEighthLockScreenWidget"
    }

    /// Shared defaults, for the handful of flags the widget needs to read.
    public static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    public enum DefaultsKey {
        /// Set by the app once the student confirms their bell times.
        public static let bellTimesConfirmed = "bellTimesConfirmed"
        /// Last applied shared-rotation version.
        public static let rotationVersion = "rotationVersion"
        /// Student has finished onboarding at least once.
        public static let hasCompletedSetup = "hasCompletedSetup"
        /// "Invisible for the day" expiry, as a time interval since 1970.
        public static let invisibleUntil = "invisibleUntil"
    }
}
