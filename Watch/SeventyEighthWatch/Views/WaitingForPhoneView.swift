import SwiftUI
import ScheduleEngine

/// What the watch shows before the first sync.
///
/// The watch has no way to get a schedule by itself — there is no schedule on
/// any server to fetch, by design — so the only useful thing this screen can do
/// is say where the schedule comes from and offer to ask again.
struct WaitingForPhoneView: View {

    @Environment(WatchScheduleStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                Text("Waiting for your iPhone")
                    .font(.headline)

                Text("Open 78th on your iPhone once. Your schedule copies over and stays on the watch after that, with no phone needed.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button {
                    store.requestRefresh()
                } label: {
                    Label(
                        store.isRequesting ? "Checking\u{2026}" : "Check again",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(.footnote)
                }
                .disabled(store.isRequesting)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("78th")
    }
}
