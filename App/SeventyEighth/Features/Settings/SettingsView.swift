import SwiftUI
import ScheduleEngine

/// Edit schedule, notification controls, invisible mode, privacy, delete
/// account.
///
/// The four things every user must be able to do, per the spec, are block,
/// remove a friend, go invisible, and delete their account with full data
/// deletion. All four are on this screen, none of them nested.
struct SettingsView: View {

    @Environment(ScheduleStore.self) private var schedule
    @Environment(SocialStore.self) private var social

    @AppStorage("pingNotificationsEnabled") private var pingNotifications = false
    @State private var isPresentingDelete = false
    @State private var isPresentingEraseSchedule = false

    var body: some View {
        List {
            Section("Schedule") {
                NavigationLink("Courses and day types") { ScheduleSetupView() }
                NavigationLink("Bell times") { BellTimesEditorView() }
                NavigationLink("Day rotation") { RotationCalendarView() }
            }

            Section {
                Toggle("Tell me when a friend pings", isOn: $pingNotifications)
                    .onChange(of: pingNotifications) { _, enabled in
                        Task { await PushRegistration.shared.setEnabled(enabled, social: social) }
                    }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Off by default. Always muted during any period you have marked as class time.")
            }

            Section {
                Toggle("Invisible for today", isOn: Binding(
                    get: { social.isInvisible },
                    set: { invisible in
                        Task { await social.setInvisibleForToday(invisible, until: endOfToday) }
                    }
                ))
            } header: {
                Text("Visibility")
            } footer: {
                Text("Clears your current ping and stops you sending until tomorrow. You can still see your friends.")
            }

            Section("Friends") {
                NavigationLink {
                    FriendsView()
                } label: {
                    HStack {
                        Text("Friends and blocking")
                        Spacer()
                        Text("\(social.friends.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                NavigationLink("Privacy, in plain language") { PrivacyView() }
            } header: {
                Text("Privacy")
            } footer: {
                Text("Your class schedule never leaves this phone. Not for pings, not for anything.")
            }

            if let profile = social.profile {
                Section("Account") {
                    LabeledContent("Name", value: profile.displayName)
                    if let grade = profile.grade {
                        LabeledContent("Grade", value: "\(grade)")
                    }
                    if let code = profile.friendCode {
                        LabeledContent("Your code", value: code)
                    }
                    Button("Sign out") { Task { await social.signOut() } }
                }
            }

            Section {
                Button("Erase my schedule", role: .destructive) { isPresentingEraseSchedule = true }
                if social.isSignedIn {
                    Button("Delete my account", role: .destructive) { isPresentingDelete = true }
                }
            } footer: {
                Text("Deleting your account removes your profile, your friendships, your pings, and your device tokens. There is nothing archived to keep.")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Delete your account?",
            isPresented: $isPresentingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete everything", role: .destructive) {
                Task { await social.deleteAccount() }
            }
        } message: {
            Text("This cannot be undone. Your schedule stays on this phone until you erase it separately.")
        }
        .confirmationDialog(
            "Erase your schedule?",
            isPresented: $isPresentingEraseSchedule,
            titleVisibility: .visible
        ) {
            Button("Erase", role: .destructive) { schedule.eraseSchedule() }
        } message: {
            Text("Your courses and day types are removed from this phone and the default bell times come back.")
        }
    }

    private var endOfToday: Date {
        let calendar = schedule.configuration.calendar
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.startOfDay(for: tomorrow)
    }
}

/// The privacy policy, written for the person it applies to.
struct PrivacyView: View {

    var body: some View {
        List {
            Section("What stays on your phone") {
                Text("Your class schedule, your courses, your rooms, your teachers, and your day rotation. None of it is uploaded. If you delete the app it is gone.")
            }

            Section("What the server knows") {
                Text("Your name, your grade, an emoji, and your friend code.")
                Text("Who your friends are, once you both agree.")
                Text("Your current ping: one of nine spots, an optional tag from a list of five, and when it expires.")
            }

            Section("What the server does not know") {
                Text("Where you actually are. There is no GPS in this app and nothing runs in the background.")
                Text("Where you have been. Expired pings are deleted, not archived. There is no history to look at, for you or for anyone else.")
                Text("What your schedule is, or which class you are in right now.")
            }

            Section("Who can see you") {
                Text("Only people you have accepted as friends. That is enforced in the database, not in the app, so a modified app cannot see more than the real one.")
                Text("You can remove a friend, block someone, or go invisible for the day at any time, from Settings.")
            }

            Section("Getting out") {
                Text("Delete my account removes your profile, your friendships, your pings, and your device tokens. It is a delete, not a deactivate.")
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environment(PreviewSupport.store())
        .environment(PreviewSupport.social())
}
