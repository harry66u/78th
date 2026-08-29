import SwiftUI
import ScheduleEngine

@main
struct SeventyEighthWatchApp: App {

    @State private var schedule: WatchScheduleStore
    @State private var social: WatchSocialStore
    @Environment(\.scenePhase) private var scenePhase

    @MainActor
    init() {
        _schedule = State(initialValue: WatchScheduleStore())
        _social = State(initialValue: WatchSocialStore())
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(schedule)
                .environment(social)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                schedule.reload()
                Task {
                    await social.restore()
                    // A tap that failed while the watch was off the network gets
                    // its second chance here rather than being lost.
                    await social.flushOutbox()
                }
            case .background, .inactive:
                // Realtime is a screen-open feature on the watch exactly as it is
                // on the phone. Nothing subscribes while the wrist is down.
                social.stopRealtime()
            @unknown default:
                break
            }
        }
    }
}
