import SwiftUI
import SwiftData
import WidgetKit
import ScheduleEngine

@main
struct SeventyEighthApp: App {

    @State private var scheduleStore: ScheduleStore
    @State private var socialStore: SocialStore
    @Environment(\.scenePhase) private var scenePhase

    private let container: ModelContainer

    // SwiftUI creates the App on the main actor; saying so lets the two
    // main-actor stores be built here rather than lazily on first render.
    @MainActor
    init() {
        let container = ScheduleContainer.shared
        self.container = container
        let context = ModelContext(container)
        _scheduleStore = State(initialValue: ScheduleStore(context: context))

        // No backend configured is a supported build: milestones 1 through 3 are
        // a complete schedule app with no server at all.
        let backend: any SocialBackend
        if let configuration = SupabaseConfiguration.fromBundle() {
            backend = SupabaseSocialBackend(configuration: configuration)
        } else {
            backend = InMemorySocialBackend()
        }
        _socialStore = State(initialValue: SocialStore(backend: backend))

        let dispatcherBackend = backend
        Task { await PingDispatcher.shared.use(dispatcherBackend) }

        // The store's first reload has already handed the service a payload;
        // activating now means it goes out as soon as the session is up.
        WatchSyncService.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(scheduleStore)
                .environment(socialStore)
                .modelContainer(container)
                .task {
                    await socialStore.restore()
                    await socialStore.flushOutbox()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                scheduleStore.reload()
                WidgetCenter.shared.reloadAllTimelines()
                Task {
                    await socialStore.flushOutbox()
                    await socialStore.refreshPings()
                    socialStore.startRealtime()
                }
            case .background, .inactive:
                // Realtime is an app-open feature. Nothing subscribes in the
                // background, and nothing tracks anyone while the phone is away.
                socialStore.stopRealtime()
            @unknown default:
                break
            }
        }
    }
}
