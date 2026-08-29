import SwiftUI
import ScheduleEngine

/// Two pages, swiped vertically, and nothing else.
///
/// The phone has four tabs because it is where a schedule is entered, friends
/// are managed, and settings live. None of that belongs on a wrist. The watch
/// answers one question — what is next and where — and offers the rest of the
/// day underneath it for the times that is not enough.
struct WatchRootView: View {

    @Environment(WatchScheduleStore.self) private var store

    var body: some View {
        if store.hasSchedule {
            TabView {
                NavigationStack { NowView() }
                NavigationStack { DayListView() }
            }
            .tabViewStyle(.verticalPage)
            .tint(Theme.courseColor(0))
        } else {
            NavigationStack { WaitingForPhoneView() }
                .tint(Theme.courseColor(0))
        }
    }
}
