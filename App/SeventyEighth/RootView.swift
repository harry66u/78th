import SwiftUI
import ScheduleEngine

struct RootView: View {

    @AppStorage(AppIdentifiers.DefaultsKey.hasCompletedSetup) private var hasCompletedSetup = false

    var body: some View {
        Group {
            if hasCompletedSetup {
                MainTabs()
            } else {
                OnboardingView(onFinished: { hasCompletedSetup = true })
            }
        }
        .tint(Theme.courseColor(0))
    }
}

struct MainTabs: View {

    @Environment(SocialStore.self) private var social

    var body: some View {
        TabView {
            NavigationStack { TodayView() }
                .tabItem { Label("Today", systemImage: "clock") }

            NavigationStack { WeekView() }
                .tabItem { Label("Week", systemImage: "calendar.day.timeline.left") }

            NavigationStack { PingsView() }
                .tabItem { Label("Pings", systemImage: "mappin.and.ellipse") }
                .badge(social.requests.filter { !$0.isOutgoing }.count)

            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

#Preview {
    RootView()
        .environment(PreviewSupport.store())
        .environment(PreviewSupport.social())
}
