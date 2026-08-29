# Open questions

The build spec lists four things to resolve before the import milestone, and the
watch has since added a fifth. None of them block writing code, and all of them
block being *correct*. Each one is marked in the source where it lives, so fixing
it is a single edit.

## 1. The bell times are placeholders

`Packages/ScheduleEngine/Sources/ScheduleEngine/DefaultBellSchedule.swift` ships
a plausible set of times. They were not taken from Ramaz.

The app is honest about this rather than quietly wrong: `timesAreConfirmed` is
`false`, and the Today screen shows a banner until a student either confirms the
times or edits them.

**To fix:** replace the times in that file, set `timesAreConfirmed = true`, and
bump `DefaultBellSchedule.version`.

**Still to answer:** how many distinct day types exist across the year, and
whether the rotation is by weekday or by letter. The code supports both;
`DefaultBellSchedule.rotationTemplates(letters:basedOn:)` builds a lettered
rotation over one set of bells, which is the usual shape.

## 2. The ping locations have not been checked against the building

`Shared/Social/PingVocabulary.swift` uses the starting list from the spec: Lobby,
3rd / 4th / 6th floor lounges, Library, Cafeteria, Gym, Beit Midrash, Outside.

**To fix:** edit the enum, and edit the matching `check` constraint on
`public.pings.location_key` in a new migration. Both sides are deliberately
closed — the constraint is in the database so a modified client cannot invent a
location.

## 3. What format does the school distribute schedules in?

The paste-and-parse path is built to be format-agnostic, which is a way of saying
nobody has looked at the real input yet. If there is a machine-readable export,
that is a fourth import path worth more than all the parsing work.

**Until then:** the review screen is the safety net, and the manual grid is the
guaranteed path.

## 4. Does the administration want to review this first?

Worth more than a fast release. The design already answers the questions an
administrator would ask — no chat, no free text, no tracking, no way to see
anyone who has not accepted you, schedules never leave the phone — and
`docs/privacy-policy.md` is written to be read by an adult, not a lawyer.

The first TestFlight build should ship with the Pings tab hidden. A schedule app
that is always right is useful on its own, and it is a much easier thing to get
permission for.

## 5. The watch's Sign in with Apple grouping is unverified

The watch signs in for itself rather than borrowing the phone's session, which
means Apple has to issue the *same* user identifier on both devices. That is only
true when the watch App ID is grouped with the phone's App ID for Sign in with
Apple, and when Supabase's Apple provider lists
`com.seventyeighth.app.watchkitapp` among its client IDs. Both steps are in the
README's backend configuration section.

Neither can be exercised without a paid Apple Developer account, so neither has
been. **The failure mode is quiet**, which is what makes this worth writing down:
if the grouping is missing, the watch signs into a second Supabase account
belonging to the same person, and the student sees a working app with no friends
in it rather than an error.

**To check, once there is an account:** sign in on both devices and confirm
`auth.users` has one row, not two.
