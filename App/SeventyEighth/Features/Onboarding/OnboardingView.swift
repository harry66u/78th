import SwiftUI
import ScheduleEngine

/// Sign in, name and grade, then straight into schedule setup.
///
/// Signing in is optional and skippable: milestones 1 through 3 are a complete,
/// useful app with no account at all, and a student who only wants the widget
/// should never be blocked by a login.
struct OnboardingView: View {

    @Environment(ScheduleStore.self) private var schedule
    @Environment(SocialStore.self) private var social

    let onFinished: () -> Void

    @State private var step: Step = .welcome
    @State private var displayName = ""
    @State private var grade: Int = 11
    @State private var avatar = "\u{1F642}"
    @State private var coordinator = SignInWithAppleCoordinator()

    enum Step {
        case welcome
        case profile
        case schedule
    }

    private let avatars = ["\u{1F642}", "\u{1F9E0}", "\u{1F3C0}", "\u{1F4DA}", "\u{1F3B8}", "\u{1F3AF}", "\u{1F680}", "\u{1F9C3}"]

    var body: some View {
        NavigationStack {
            switch step {
            case .welcome: welcome
            case .profile: profile
            case .schedule: scheduleStep
            }
        }
    }

    // MARK: Welcome

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 12) {
                Text("78th")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                Text("Your schedule, on your home screen.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                FeatureLine(
                    symbol: "clock",
                    title: "Know what is next",
                    detail: "Minutes left, the room, and what is after it, without unlocking your phone."
                )
                FeatureLine(
                    symbol: "mappin.and.ellipse",
                    title: "Find your friends on a free",
                    detail: "Tap a spot. Friends see where you are. Nothing tracks you and nothing is kept."
                )
                FeatureLine(
                    symbol: "iphone.slash",
                    title: "Built for a school with phone rules",
                    detail: "No chat, no messages, no feed. Glance and put it away."
                )
            }
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 10) {
                AppleSignInButton(coordinator: coordinator) { suggestedName in
                    if let suggestedName { displayName = suggestedName }
                    step = .profile
                }
                .frame(height: 48)

                Button("Set up my schedule without an account") {
                    step = .schedule
                }
                .font(.subheadline)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 32)
        }
    }

    // MARK: Profile

    private var profile: some View {
        Form {
            Section {
                TextField("What people call you", text: $displayName)
                    .textInputAutocapitalization(.words)
                Picker("Grade", selection: $grade) {
                    ForEach(9...12, id: \.self) { Text("\($0)").tag($0) }
                }
            } header: {
                Text("Your profile")
            } footer: {
                Text("This is everything friends can see about you, plus whichever spot you are at right now.")
            }

            Section("Pick an emoji") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    ForEach(avatars, id: \.self) { emoji in
                        Button { avatar = emoji } label: {
                            Text(emoji)
                                .font(.title)
                                .frame(width: 46, height: 46)
                                .background(
                                    avatar == emoji ? Theme.courseColor(0).opacity(0.2) : Color.secondary.opacity(0.1),
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Button("Continue") {
                    Task {
                        await social.completeProfile(
                            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                            grade: grade,
                            avatarEmoji: avatar
                        )
                        step = .schedule
                    }
                }
                .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle("About you")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Schedule

    private var scheduleStep: some View {
        ScheduleSetupView(showsDoneButton: false)
            .navigationTitle("Your schedule")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(schedule.hasAnyCourses ? "Done" : "Later") { onFinished() }
                }
            }
    }
}

private struct FeatureLine: View {

    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(Theme.courseColor(0))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    OnboardingView(onFinished: {})
        .environment(PreviewSupport.store())
        .environment(PreviewSupport.social())
}
