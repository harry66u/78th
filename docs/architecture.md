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
              ┌──────────────────────┼──────────────────────┐
              │                      │                      │
      ┌───────▼───────┐     ┌────────▼────────┐    ┌────────▼────────┐
      │   The app     │     │  Widget ext.    │    │  watchOS (v2)   │
      │ ScheduleStore │     │ ScheduleProvider│    │                 │
      └───────┬───────┘     └────────┬────────┘    └─────────────────┘
              │                      │
              └──────────┬───────────┘
                         │  reads and writes
             ┌───────────▼────────────┐
             │  SwiftData, App Group  │
             │  group.com.seventy...  │
             └────────────────────────┘
```

## Layers

**`Packages/ScheduleEngine`** — value types (`TimeOfDay`, `YearMonthDay`,
`PeriodSlot`, `DayTemplate`, `CourseAssignment`, `CalendarDay`), the engine, the
import contract, the rotation-file format and merge, and formatting. All of it is
unit tested, and none of it can be broken by a UI change.

**`Shared/`** — compiled into both the app and the widget. The SwiftData
`@Model` classes, the App Group container, the ping vocabulary, the theme, the
`SendPingIntent`, and the Supabase client. Nothing here makes a scheduling
decision; it converts and stores.

**`App/SeventyEighth/`** — two observable stores own all mutation.
`ScheduleStore` is the only thing that writes the schedule and the only thing
that calls `WidgetCenter.reloadAllTimelines()`, so a schedule edit that does not
reach the home screen is a one-line bug rather than a hunt. `SocialStore` owns
identity, friends, and the live ping list.

**`Widget/`** — a `TimelineProvider` that reads the App Group container, asks
the engine for entry dates, and precomputes an entry for each. It never makes a
network call and never wakes the app.

## Why the widget timeline looks the way it does

Period boundaries alone are not enough. Between two bells the countdown would sit
frozen on whatever minute the last entry was built at. So
`timelineEntryDates(from:)` emits an entry every minute while there is something
to count down to, and falls back to bells-only when there is not — a Sunday gets
a handful of entries, not ninety. Timeline entries are cheap; widget *reloads*
are the budgeted resource, and this design needs almost none.

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
