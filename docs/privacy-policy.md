# 78th — Privacy

Written to be read, not to be agreed to. If anything below stops being true, the
app is wrong and should be fixed.

## Your schedule stays on your phone

Your courses, your rooms, your teachers, your day rotation: all of it is stored
on the device and nowhere else. It is not uploaded, not backed up to us, and not
used for anything on the server. If you delete the app, it is gone.

The one exception is the import: if you paste or photograph a schedule, that text
or image is sent once to a parser so it can be turned into periods. It is not
stored, and the result comes straight back to you to check before anything is
saved. If you would rather not do that, fill in the grid instead — it does the
same job and never leaves the phone.

## What we store about you

- Your display name, your grade, and the emoji you picked.
- Your friend code.
- Who your friends are, once you have both agreed.
- Your current ping, if you have one: one of nine named spots in the building, an
  optional tag from a list of five, and the time it expires.
- A push token, only if you turned notifications on.

That is the whole list.

## What we do not store

- **Where you actually are.** The app has no access to location services. There
  is no GPS in it and nothing runs in the background. A ping is you pressing a
  button that says "Library", nothing more.
- **Where you have been.** Pings expire after 45 minutes or at the end of the
  period, whichever is sooner, and are then deleted. Not hidden, not archived:
  deleted. There is no history for anyone to look at, including us.
- **What your schedule is.**

## Who can see your ping

Only people you have accepted as friends. Both sides have to agree before either
one sees anything about the other. You add someone by typing their short code —
the app never reads your contacts and there is no directory to browse.

This is enforced by the database, not by the app. Someone running a modified copy
of 78th still cannot see anyone who has not accepted them.

## What you can do, any time, from Settings

- Remove a friend.
- Block someone. They cannot request you again and cannot tell they were blocked.
- Go invisible for the day. Your current ping is cleared and you stop sending.
- Delete your account. That removes your profile, your friendships, your pings,
  and your push tokens. It is a delete, not a deactivate. Your schedule stays on
  your phone until you erase it separately, which is also one button.

## No messaging

There is no chat, no direct messages, and no free text of any kind between users.
Everything you can say through this app comes from two fixed lists: nine
locations and five tags. That is deliberate. It keeps this a utility, and it
means there is nothing here to moderate.

## Contact

Questions, or something that looks wrong: open an issue on the repository.
