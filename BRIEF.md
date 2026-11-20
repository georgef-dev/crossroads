# Brief

## Goals

- Crossroads: one place that summarizes everything, starting with a bridge between personal and work life.
- Bring calendars, email, and later todos into a single view.
- Surface conflicts early so I can reschedule proactively, e.g. kids pickup overlapping a work meeting.
- Later, phase 2: flag buffers between nearby events.
- Later: filters and parameters that control what Crossroads shows.
- Next: an omacast-style modal I open from a keybinding, with a quick view of everything and a search bar.
- After the modal: a settings page.
- Later: bring in agent statuses and other sources.
- Next: a native macOS app, with Apple Reminders as its todo source.
- Later, in no particular order: the Debian VM and a phone view. Each needs its own UI, since a shell plugin only runs on Omarchy.
- Later: work email.
- More phases may come up.

## Success criteria

- I open Crossroads in the morning and see every overlap between personal and work events for the selected range.
- I don't need to open Google Calendar or iCloud to spot those conflicts.
- The view lives in the Omarchy shell.
- Conflicts are flagged with simple color coding in the view.
- All-day events are never flagged as conflicts.
- Unread mail from my personal-domain inbox shows as a simple list.
- Work events show as separate busy blocks. Consecutive blocks are never merged into one.
- Time range can be switched between today, today + 1, today + 3, today + 7, and today + 14 days.
- Data refreshes every hour by default, and the interval is a configuration option.

## Constraints

- Work calendar: Google Workspace behind company SSO sign-in, shared to my personal-domain Google account as free/busy only. Work events have no titles.
- Personal calendars: mostly iCloud (several family and personal calendars), plus my personal-domain Google calendar.
- Google access goes through an Internal OAuth app on my personal-domain Workspace. No privacy policy, verification, or publishing.
- About 5 calendars in total.
- Email: my personal-domain inbox in v1.
- v1 runs on Omarchy as an Omarchy shell plugin, with both a bar widget and a panel.
- Everything stays local. Using the Google and iCloud services is fine, but Crossroads and my data stay on my machine.
- The code is public on GitHub (georgef-dev/crossroads), with no personal data in the repository.

## Non-goals

- v1 takes no actions. Rescheduling happens in the source calendar. Opening an event or email in the browser is fine.
- No todos in v1.
- No work email in v1.
- No buffer or travel-time warnings in v1.
- No user-defined filters or parameters in v1.
- No email smarts in v1, like extracting dates or commitments.
- No symlink into `~/Work`.

## Preferences

- macOS: a native Swift app. Calendars and Apple Reminders come through macOS (all my calendars are already in Calendar). Gmail still goes through OAuth, since I use the Gmail app, not Mail.
- macOS: just me for now, so no signing or notarizing yet. Older macOS versions are fine to support; I run the latest.
- One repository, with a folder per platform and the shared specs at the root. Platform work happens on a branch that rebases cleanly on main.
- Start simple and add features in later phases.
- Crossroads: an OS-agnostic name, since a Mac version is a goal. Omarchy ships its own Omaview.
- Capture the conflict rules in a TLA+ spec.

## Open questions

- Does "stays local" also rule out any self-hosted sync between my devices once more platforms land?
- My @gmail.com inbox: a privacy page so it can use an External app, IMAP with an app password, or leave it out.
