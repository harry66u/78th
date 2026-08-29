import SwiftUI
import ScheduleEngine

/// Pages, swiped vertically, and nothing else.
///
/// The phone has four tabs because it is where a schedule is entered, friends
/// are managed, and settings live. Most of that does not belong on a wrist. The
/// watch answers one question — what is next and where — offers the rest of the
/// day underneath it, and then the one social thing that is genuinely better on
/// a wrist than in a pocket: saying where you are during a free.
///
/// The pings page is absent entirely in a build with no backend, rather than
/// present and dead. A page that can never do anything still costs a swipe every
/// time you look at your wrist.
struct WatchRootView: View {

    @Environment(WatchScheduleStore.self) private var schedule
    @Environment(WatchSocialStore.self) private var social

    var body: some View {
        Group {
            if schedule.hasSchedule {
                TabView {
                    NavigationStack { NowView() }
                    NavigationStack { DayListView() }
                    if social.isConfigured {
                        NavigationStack { WatchPingsView() }
                    }
                }
                .tabViewStyle(.verticalPage)
            } else {
                NavigationStack { WaitingForPhoneView() }
            }
        }
        .tint(Theme.courseColor(0))
    }
}
