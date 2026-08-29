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
        /// The watch face complication.
        public static let watchSchedule = "SeventyEighthWatchScheduleComplication"
    }

    /// Shared defaults, for the handful of flags the widget needs to read.
    public static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    /// "Invisible for the day", or nil once it has expired.
    ///
    /// Three places need this rule — the store that sets it, the payload that
    /// carries it to the watch, and anything that checks before sending — so it
    /// is written once here rather than three times slightly differently.
    public static func invisibleUntil(now: Date = Date()) -> Date? {
        let stored = sharedDefaults?.double(forKey: DefaultsKey.invisibleUntil) ?? 0
        guard stored > now.timeIntervalSince1970 else { return nil }
        return Date(timeIntervalSince1970: stored)
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
