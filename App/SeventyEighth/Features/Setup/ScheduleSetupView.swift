import SwiftUI
import PhotosUI
import ScheduleEngine

/// The highest risk screen in the product. If this takes more than about five
/// minutes, students abandon the app before they ever see the widget, so the
/// three paths are offered in the order that finishes fastest.
struct ScheduleSetupView: View {

    @Environment(ScheduleStore.self) private var schedule
    @Environment(\.dismiss) private var dismiss

    /// False when this screen is a step inside onboarding rather than a sheet,
    /// so onboarding's own Continue button is the only one on screen.
    var showsDoneButton = true

    var body: some View {
        List {
            Section {
                NavigationLink {
                    PasteImportView()
                } label: {
                    SetupOptionRow(
                        title: "Paste your schedule",
                        detail: "Copy it from anywhere, paste it here, check what came back.",
                        systemImage: "doc.on.clipboard",
                        isRecommended: true
                    )
                }

                NavigationLink {
                    PhotoImportView()
                } label: {
                    SetupOptionRow(
                        title: "Photograph it",
                        detail: "Works on a printed schedule or a picture of a screen.",
                        systemImage: "camera"
                    )
                }

                NavigationLink {
                    ManualGridView()
                } label: {
                    SetupOptionRow(
                        title: "Fill in the grid",
                        detail: "Type it yourself. Course names autocomplete after the first time.",
                        systemImage: "square.grid.3x3"
                    )
                }
            } header: {
                Text("Add your courses")
            } footer: {
                Text("Your schedule stays on this phone. It is never uploaded, not even to use pings.")
            }

            Section("Bell times and calendar") {
                NavigationLink("Bell times") { BellTimesEditorView() }
                NavigationLink("Day rotation") { RotationCalendarView() }
            }
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct SetupOptionRow: View {

    let title: String
    let detail: String
    let systemImage: String
    var isRecommended: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(Theme.courseColor(0))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    if isRecommended {
                        Text("FASTEST")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Theme.courseColor(0).opacity(0.15), in: Capsule())
                            .foregroundStyle(Theme.courseColor(0))
                    }
                }
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack { ScheduleSetupView() }
        .environment(PreviewSupport.store())
}
