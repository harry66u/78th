# Architecture

## The rule that shapes everything

> The schedule engine must be a pure Swift module with no network dependency.
> Given a date and time, it returns the current period, the next period, and
> seconds remaining. The app, the widget, and any future watch app all call the
> same function.

`Packages/ScheduleEngine` imports nothing but Foundation. It has no notion of
SwiftData, no notion of SwiftUI, and no notion of Supabase. Its entire input is a
`ScheduleConfiguration` value and its entire output is a `ScheduleSnapshot`
value. That is why the number on the home screen and the number in the app can
never disagree: there is one implementation, and it is a pure function of time.

```
                        ┌──────────────────────────┐
                        │      ScheduleEngine      │
                        │  (Foundation only, pure) │
                        └────────────┬─────────────┘
                                     │
        ┌────────────────────────────┼───────────────────────────────┐
        │                            │                               │
┌───────▼───────┐          ┌─────────▼───────┐           ┌───────────▼──────────┐
│   The app     │          │  Widget ext.    │           │  Watch app + face    │
│ ScheduleStore │          │ ScheduleProvider│           │ WatchScheduleStore   │
└───────┬───────┘          └────────┬────────┘           └───────────┬──────────┘
        │                           │                                │
        └────────────┬──────────────┘                                │
                     │  reads and writes                             │ reads
         ┌───────────▼────────────┐                    ┌─────────────▼───────────┐
         │  SwiftData, App Group  │                    │  ScheduleMirror, JSON   │
         │  group.com.seventy...  │                    │  App Group, on watch    │
         └───────────┬────────────┘                    └─────────────▲───────────┘
                     │                                               │
                     └───────────────────────────────────────────────┘
                          WatchConnectivity application context
                        (phone writes, watch mirrors, never back)
```

## Layers

**`Packages/ScheduleEngine`** — value types (`TimeOfDay`, `YearMonthDay`,
`PeriodSlot`, `DayTemplate`, `CourseAssignment`, `CalendarDay`), the engine, the
import contract, the rotation-file format and merge, and formatting. All of it is
unit tested, and none of it can be broken by a UI change.

**`Shared/`** — compiled into the app and the extensions. The SwiftData
`@Model` classes, the App Group container, the ping vocabulary, the theme, the
`SendPingIntent`, and the Supabase client. Nothing here makes a scheduling
decision; it converts and stores.

Two subfolders are cross-platform on purpose and are the only part of `Shared/`
the watch targets compile:

- **`Shared/Glance/`** — `GlanceContent`, which reduces a snapshot to the
  handful of strings and one colour a small surface can hold; `ScheduleEntry`
  and `GlanceTimeline`, the WidgetKit timeline both extensions build; and the
  accessory renderers. The iPhone lock screen and the watch face ask for the same
  families and now get the same code, so they cannot drift.
- **`Shared/Sync/`** — `ScheduleSyncPayload`, the value that crosses the pairing,
  and `ScheduleMirror`, the watch's on-disk copy of it.
- **`Shared/Social/`** — all of it except `SendPingIntent`, which reads the
  phone's SwiftData store. The watch compiles the same `SocialBackend` protocol,
  the same Supabase implementation, and the same ping vocabulary the phone does,
  so there is one definition of what a ping is and one client that sends it.

**`App/SeventyEighth/`** — two observable stores own all mutation.
`ScheduleStore` is the only thing that writes the schedule and the only thing
that calls `WidgetCenter.reloadAllTimelines()`, so a schedule edit that does not
reach the home screen is a one-line bug rather than a hunt. `SocialStore` owns
identity, friends, and the live ping list.

**`Widget/`** — a `TimelineProvider` that reads the App Group container, asks
the engine for entry dates, and precomputes an entry for each. It never makes a
network call and never wakes the app.

**`Watch/`** — the watch app and its complication extension. The *schedule* half
is read-only, which is what makes it small: no editing on the wrist means nothing
to save and no way for two devices to disagree about who won. The *social* half
is not a mirror at all — see "Pings on the watch" below.

## Why the widget timeline looks the way it does

Period boundaries alone are not enough. Between two bells the countdown would sit
frozen on whatever minute the last entry was built at. So
`timelineEntryDates(from:)` emits an entry every minute while there is something
to count down to, and falls back to bells-only when there is not — a Sunday gets
a handful of entries, not ninety. Timeline entries are cheap; widget *reloads*
are the budgeted resource, and this design needs almost none.

## How the schedule reaches the watch

An App Group is a per-device container, not an iCloud one, so the watch cannot
read the phone's SwiftData store. The schedule has to cross the pairing as a
value — and it already is one. `ScheduleConfiguration` is `Codable` and is the
engine's entire input, so the transfer format is that value plus the two flags
the wrist needs to be honest: whether the bell times have been confirmed, and
which rotation version this is.

The transport is `WCSession`'s **application context**, and the choice matters:

- It is a single latest-state slot rather than a queue, so a student who edits
  five periods in a row does not send five transfers the watch has to replay.
- It is delivered in the background, waking the watch app to write its mirror
  without anybody raising a wrist.
- It is capped at roughly a quarter of a megabyte, which is why the payload is
  trimmed to the dated overrides a given moment can still reach. That window is
  `ScheduleConfiguration.trimmingCalendarDays(around:)`, and it lives in the
  engine package because *how far ahead an answer can depend on the rotation* is
  a fact about the engine. It is tested there.

What is deliberately **not** sent is a transfer per tick. The complication's
timeline is precomputed a day ahead from the schedule the watch already holds, so
minute-to-minute freshness costs no radio at all. A transfer is only needed when
the schedule itself changes, which is a handful of times a year.

Everything the watch receives goes to disk first, and both the watch app and the
complication read it back from there. One path in means a value on the screen is
always a value the face would show too. The mirror is a cache and is treated like
one: losing it costs a sync, not a schedule.

`ScheduleStore.reload()` is the single place the phone feeds it, for the same
reason it is the single place that reloads widget timelines. Every write path in
that class ends in `reload()`, so a schedule edit that reaches the app but not
the wrist is not a state the store can get into.

## Pings on the watch

The schedule mirrors from the phone. Pings do not: the watch holds its own
Supabase session and talks to the server itself.

That is a deliberate asymmetry, and the reason is the same reason the watch app
exists at all. The schedule can mirror because it is a value that changes a few
times a year; a ping is live, and it is wanted precisely when the phone is in a
locker. Relaying a ping through the phone would put the feature's availability
on the one link that is missing at the moment it matters.

**Each device signs in separately.** The watch does not borrow the phone's
session. Supabase rotates refresh tokens, so two devices driving one session
spend their time invalidating each other; two Sign in with Apple flows give two
token chains for the same account, and neither can knock the other out. It also
means no refresh token ever crosses the pairing.

The consequences are worth stating plainly:

| | Phone | Watch |
|---|---|---|
| Sign in with Apple | Yes | Yes, separately |
| See friends' live pings | Yes | Yes |
| Send a ping | Yes | Yes |
| Ping expiry computed from the local schedule | Yes | Yes, from the mirror |
| Make a profile, add a friend by code, block someone | Yes | No — needs a keyboard |
| Set "invisible for the day" | Yes | No — honours the phone's switch |

**Invisibility is the one flag that had to cross.** It is a privacy promise, and
the watch now talks to the server on its own, so a watch that had not heard about
the switch would keep telling friends where the student is. It rides in
`ScheduleSyncPayload` — not schedule data, and there anyway, because there is
already exactly one phone-to-watch channel and a second one would be a second
thing to keep in sync. `SocialStore.setInvisibleForToday` pushes it immediately
rather than waiting for the next schedule edit.

There is deliberately **no ping complication**. The iOS ping widget is
send-only, on the reasoning that a tile on a visible home screen must never leak
who is where. A watch face is more visible than a home screen, not less, so the
same reasoning says the watch face shows the schedule and nothing social.

### What is still phone-only

Everything with a text field. Making a profile, adding a friend by code,
blocking, unblocking, and account deletion all stay on the phone: they are rare,
they need typing, and a wrist is a bad place to do any of them. The watch says so
and points at the phone rather than offering a degraded version.

## What the server knows

There is no schedule table. There is no location table. There is no history
table. The database holds:

| Table | Rows |
|---|---|
| `profiles` | Display name, grade, an emoji, a friend code. |
| `friendships` | Who is friends with whom, or has requested, or is blocked. |
| `pings` | **One live row per student**, with an expiry. Replaced, never appended. |
| `device_tokens` | APNs tokens, for the notification that is off by default. |

Visibility is enforced by row level security, not by the client. The policy that
matters is one line:

```sql
using (
  user_id = (select auth.uid())
  or (public.are_friends((select auth.uid()), user_id) and expires_at > now())
)
```

A modified client cannot see more than the real one, because the filtering does
not happen in the client.

## Two decisions worth writing down

**One live ping per student, enforced by a unique constraint on `user_id`.** The
spec calls for no history. A table that appends rows and hides the old ones still
has the old ones in it. A table that can only ever hold your current ping cannot
be mined for where you have been, by anyone, including whoever runs the server.

**Notification muting is enforced on the device.** The spec says ping alerts are
muted during any period the student marked instructional. The server cannot do
that: it does not know anyone's schedule, and the whole design depends on it
never knowing. So the push is delivered and the device decides, which is the only
arrangement consistent with keeping the schedule local.

## The shared rotation file

The rotation — which day type falls on which date, plus holidays — is published
centrally as a signed JSON blob and merged into each device. Course assignments
stay local and survive the merge: templates are matched by name and slots by
label, so changing a bell time keeps the same slot identity and the courses
sitting in it stay put. An unsigned or badly signed file is discarded rather than
applied with a warning.

This is what keeps the app correct after whoever built it graduates. Someone with
the signing key and `Tools/sign_rotation.py` can push next year's calendar
without an App Store release.
