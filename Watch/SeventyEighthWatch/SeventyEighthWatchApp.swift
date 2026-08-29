import SwiftUI
import ScheduleEngine

@main
struct SeventyEighthWatchApp: App {

    @State private var store: WatchScheduleStore

    @MainActor
    init() {
        _store = State(initialValue: WatchScheduleStore())
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(store)
        }
    }
}
