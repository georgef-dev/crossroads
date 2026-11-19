# Brief

## Goals

- Omaview: one place that summarizes everything, starting with a bridge between personal and work life.
- Bring calendars, email, and later todos into a single view.
- Surface conflicts early so I can reschedule proactively, e.g. kids pickup overlapping a work meeting.
- Later, phase 2: flag buffers between nearby events.
- Later: filters and parameters that control what Omaview shows.
- Next: an omacast-style modal I open from a keybinding, with a quick view of everything and a search bar.
- After the modal: a settings page.
- Later: bring in agent statuses and other sources.
- Later, in no particular order: run on the Debian VM, the MacBook, and a phone view. Each needs its own UI, since a shell plugin only runs on Omarchy.
- Later: Apple Reminders, possibly through a future native iOS app.
- Later: work email.
- More phases may come up.

## Success criteria

- I open Omaview in the morning and see every overlap between personal and work events for the selected range.
- I don't need to open Google Calendar or iCloud to spot those conflicts.
- The view lives in the Omarchy shell.
- Conflicts are flagged with simple color coding in the view.
- All-day events are never flagged as conflicts.
- Unread mail from the example.com inbox shows as a simple list.
- Work events show as separate busy blocks. Consecutive blocks are never merged into one.
- Time range can be switched between today, today + 1, today + 3, today + 7, and today + 14 days.
- Data refreshes every hour by default, and the interval is a configuration option.

## Constraints

- Work calendar: Google Workspace behind company SSO sign-in, shared to you@example.com as free/busy only. Work events have no titles.
- Personal calendars: mostly iCloud (George, Private, Family, Partner, School), plus you@example.com on Google.
- Google access goes through an Internal OAuth app on my example.com Workspace. No privacy policy, verification, or publishing.
- About 5 calendars in total.
- Email: the you@example.com inbox in v1.
- v1 runs on Omarchy as an Omarchy shell plugin, with both a bar widget and a panel.
- Everything stays local. Using the Google and iCloud services is fine, but Omaview itself stays on my machine.
- Don't publish Omaview to GitHub yet.

## Non-goals

- v1 takes no actions. Rescheduling happens in the source calendar. Opening an event or email in the browser is fine.
- No todos in v1.
- No work email in v1.
- No buffer or travel-time warnings in v1.
- No user-defined filters or parameters in v1.
- No email smarts in v1, like extracting dates or commitments.
- No symlink into `~/Work`.

## Preferences

- Start simple and add features in later phases.
- The name Omaview can change later.
- Capture the conflict rules in a TLA+ spec.

## Open questions

- Does "stays local" also rule out any self-hosted sync between my devices once more platforms land?
- The you@icloud.com inbox: a privacy page so it can use an External app, IMAP with an app password, or leave it out.
