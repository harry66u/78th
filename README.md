# 78th

A class schedule app for Ramaz, built around a home screen widget, plus a
lightweight location ping so friends can find each other during frees.

The whole product is one sentence: **you should know what class you have next,
and where, without unlocking your phone.** Everything else is in service of that.

- Enter your schedule once, in about two minutes.
- The widget shows minutes remaining, the course, and the room, with the app
  closed and no network.
- On a free, tap a spot and your friends see where you are. No GPS, no
  background tracking, no history.

It is a school utility, not a way around a phone policy. There is no chat, no
direct messages, and no free text anywhere between users.

---

## Repository layout

```
Packages/ScheduleEngine/   The pure schedule engine, plus its tests. No network,
                           no persistence, no UI. Everything else calls this.
Shared/                    Compiled into both the app and the widget: SwiftData
                           models, the App Group container, the ping vocabulary,
                           the theme.
App/SeventyEighth/         The app: stores, screens, services.
Widget/                    The WidgetKit extension: four surfaces plus the
                           one-tap ping widget.
Supabase/                  Schema with row level security, and two Edge
                           Functions.
Tools/                     Signing the shared rotation file.
docs/                      Architecture, open questions, privacy policy.
```

## Getting started

```bash
# The schedule engine needs nothing but a Swift toolchain.
make engine-test

# The app needs Xcode 16 and XcodeGen (brew install xcodegen).
make open
```

`78th.xcodeproj` is generated from `project.yml` rather than committed, so adding
a file never produces a merge conflict in a pbxproj.

### Backend configuration

The schedule half of the app works with no server at all. To turn on pings:

1. Create a Supabase project and run `Supabase/migrations/0001_init.sql`.
2. Deploy the Edge Functions:
   ```bash
   supabase functions deploy parse-schedule
   supabase functions deploy notify-ping
   supabase secrets set ANTHROPIC_API_KEY=...
   ```
3. Copy `Config/Example.xcconfig` to `Config/Local.xcconfig` and fill in the
   project URL and the anon key. Both are publishable; row level security is
   what decides who can read what. A service-role key never belongs in the app.

## Architecture in one paragraph

The schedule engine is a pure function: given a configuration and an instant, it
returns the current period, the next one, and the seconds remaining. It has no
network dependency and no persistence dependency, so the app, the widget, and any
future watch app all get the same answer from the same code. SwiftData is the
device's source of truth and lives in an App Group, which is how the widget reads
a schedule without waking the app. Supabase holds only the social half: profiles,
friendships, and one live ping per person. **The class schedule never leaves the
device** — there is no table for it, because nothing on the server needs it.

More detail in [`docs/architecture.md`](docs/architecture.md).

## Milestones

The build order from the spec, and where this repository stands:

| | Scope | State |
|---|---|---|
| M1 | Schedule engine with unit tests | Built. 60+ tests covering day types, half days, dropped periods, no-school days, passing time, time zones, and the widget timeline. |
| M2 | Manual entry plus the Today screen | Built. Manual grid, bell time editor, live countdown. |
| M3 | Widget, all four sizes | Built. Small, medium, lock screen rectangular and circular, plus inline. |
| M4 | Paste and parse with a review screen | Built. Paste and photo both route through the same review screen; nothing saves without confirmation. |
| M5 | Auth, profiles, friend requests | Built. Sign in with Apple, add by code, row level security. |
| M6 | Pings with expiry and realtime | Built. |
| M7 | Calendar overrides and the shared rotation file | Built, signed with Ed25519. |
| M8 | TestFlight with about twenty students | Not started. Needs a paid Apple Developer account. |

The spec says to ship M1 through M3 before writing a line of social code, and
that ordering still holds for release: a schedule app that is always right is
useful on its own. The social code exists here so the shape of the whole thing is
visible, but the first TestFlight build should have the Pings tab hidden.

## Before this ships

Three things in this repository are placeholders, and all three are flagged in
the code where they live:

1. **The bell times in `DefaultBellSchedule.swift` are made up.** They are
   plausible, not real. The app shows a banner until a student confirms them.
2. **The ping locations have not been checked against the building.**
3. **The day rotation is a Monday-to-Friday guess.** The real rotation belongs
   in the shared rotation file.

See [`docs/open-questions.md`](docs/open-questions.md).

## Verification status

`swift test` and `xcodebuild` both run in CI on macOS, on every push. The engine
tests are the meaningful gate: they encode M1's acceptance criterion, which is
that the engine returns the correct current and next period for any date and
time across every day type.
