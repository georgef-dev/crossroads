# Crossroads for macOS: plan

The goal is a native Mac app that does what Crossroads does on Omarchy. A menu bar icon and a hotkey panel bring the conflicts and whatever needs your attention right now into focus, across every calendar on the Mac, Apple Reminders, and Gmail.

This plan is the starting point for work on the Mac, on the `macos` branch. It was written on Linux, so every macOS-specific fact is either documented Apple behavior or marked **verify on the Mac**. Check those before building on them.

## Where this stands

Steps 1 to 3 are done and green. Step 4 is written but not compiled.

| Step | State |
| --- | --- |
| 1. Conformance cases | Done. Ten JSON cases in [`conformance/`](../conformance), read by both platforms. |
| 2. `CrossroadsCore`: conflicts | Done. `classify` and `overlaps` ported, ten properties, conformance runner, CI job. |
| 3. `CrossroadsCore`: view logic | Done. Ranges, sections, keys, settings, shortcut. 73 Swift tests. |
| 4. App shell | Written, **not compiled**: it needs a full Xcode. See [Toolchain](#toolchain). |
| 5 to 10 | Not started. All need Xcode. |

Two things went differently from the plan below:

- **Everything is on the `macos` branch,** with one local commit per step, rather than landing the shared files on `main` first. The shared changes are kept in their own commits, so they can still be cherry-picked to `main`.
- **A snapshot builder was added to the core** ([`Snapshot.swift`](Sources/CrossroadsCore/Snapshot.swift)), ported from `omarchy/src/crossroads/snapshot.py`. Step 4's sample data needed it, and steps 5 to 7 need it too.

## Toolchain

**A full Xcode is required.** This was not in the plan, and Command Line Tools alone is not enough:

- `xcodebuild` does not exist, so the app target cannot be built at all.
- `XCTest` does not ship with Command Line Tools.
- `swift-testing` ships, but SwiftPM does not reliably hand the compiler its
  macro plugin. [`macos/Makefile`](Makefile) passes `-plugin-path` when the
  plugin is there, which fixes it. Xcode needs none of this, and the flag is
  harmless with it.

Decided: **macOS 26** is the floor, XcodeGen is required (`brew install xcodegen`),
and the hotkey is our own Carbon wrapper ([`App/Hotkey.swift`](App/Hotkey.swift))
with no dependency.

## Decisions already made

These come from [BRIEF.md](../BRIEF.md):

- **A native Swift app.** It reuses no Python and is not a wrapper.
- **Calendars and Reminders come from macOS, through EventKit.** All your calendars are already in Calendar, so the Mac version needs no Google Calendar OAuth and no iCloud app password.
- **Gmail still uses OAuth,** since you read mail in the Gmail app, not in Mail. It uses the same Google Cloud app as Omarchy, with a desktop client.
- **Just you for now.** The build is unsigned and local, with no Developer ID and no notarizing.
- **Older macOS is fine.** You run the latest.
- **Same repository.** Mac code lives in `macos/`, and anything shared stays at the root.

## Scope

**In:**
- A menu bar icon, with the count of flagged items, like the Omarchy bar icon.
- A floating panel on a global hotkey, Super+Alt+C's equivalent, defaulting to ⌥⌘C. It has the same sections as the Omarchy modal: overlap cards, today's strip, unread mail, search, the range picker, and the default and vim keys.
- **New on the Mac: reminders that need attention.** See [open question 1](#open-questions).
- Settings: refresh interval, key preset, default range, the shortcut, and Off / Personal / Work for each calendar.
- Launch at login.

**Out, for now:**
- Signing, notarizing, the App Store, and Homebrew.
- Actions on your data: no rescheduling, no completing reminders. Opening an item in its app is fine.
- Work email. Folding the work double-bookings, which is tracked separately for both platforms.

## What carries over, and what doesn't

| Area | Omarchy | macOS |
| --- | --- | --- |
| Rules | `specs/ConflictFlags.tla` | The same spec, unchanged. It's the source of truth. |
| Settings rules | `specs/Settings.tla` | Mostly applies. See [Settings on the Mac](#settings-on-the-mac). |
| Fetching | Python `crossroads fetch` | Swift: EventKit plus the Gmail REST API |
| Conflict logic | `omarchy/src/crossroads/conflicts.py` | Ported to Swift, checked against the shared conformance cases |
| View logic (ranges, search, keys, settings rows) | `omarchy/plugin/Model.js` | Ported to Swift, with the same tests |
| UI | QML in the Omarchy shell | SwiftUI: a `MenuBarExtra` plus a floating `NSPanel` |
| Secrets | gnome-keyring | Keychain |
| Settings storage | `shell.json` and `config.json` | `UserDefaults` |
| Shortcut | `crossroads.lua` in Hyprland | A global hotkey registered by the app |
| Design | Cards, colors, logo | The same. The menu bar icon is the one-color mark as a template image. |

## Shared conformance cases

Two implementations of the same rules will drift unless something pins them together. The specs say what must be true. **Conformance cases** are concrete examples that both implementations must pass.

- A new `conformance/` folder at the root holds JSON cases, each tagged with the spec property it exercises:

  ```json
  {
    "property": "ConflictFlags.CrossTagShowsMixed",
    "name": "Kids pickup overlaps a work busy block",
    "events": [
      { "id": "pickup", "calendar": "family", "tag": "personal", "start": "15:00", "end": "15:30", "allDay": false, "status": "accepted" },
      { "id": "busy", "calendar": "work", "tag": "work", "start": "15:15", "end": "16:00", "allDay": false, "status": "accepted" }
    ],
    "kinds": { "pickup@family": "mixed", "busy@work": "mixed" },
    "overlaps": [{ "ids": ["busy", "pickup"], "start": "15:15", "end": "15:30" }]
  }
  ```

- The first cases are today's Gherkin scenarios in `omarchy/tests/features/conflict_flags.feature`, converted.
- The Python tests read them on Omarchy, and the Swift tests read them on the Mac. A case either implementation fails is a bug in that implementation, or a missing spec property.
- Property tests stay per platform: Hypothesis in Python, and generated inputs in Swift.

This touches shared files and the Omarchy tests, so it **lands on `main` first** (step 1). The branch then rebases onto it.

## Proposed layout

```
macos/
├── PLAN.md              this file
├── README.md            install and setup, written in step 10
├── Package.swift        CrossroadsCore: the rules and view logic, no Apple frameworks
├── Sources/CrossroadsCore/
│   ├── Conflicts.swift  kinds and overlap cards (ConflictFlags)
│   ├── Snapshot.swift   the model the UI draws
│   ├── Ranges.swift     ranges, grouping by day, timelines
│   ├── Sections.swift   quick view, search, keyboard selection
│   ├── Keys.swift       default and vim keys, gg and G
│   └── Settings.swift   reading and changing settings, tags, shortcut checks
├── Tests/CrossroadsCoreTests/
├── project.yml          the app target, generated with XcodeGen
└── App/
    ├── CrossroadsApp.swift   MenuBarExtra and launch at login
    ├── Panel/               the floating panel and its SwiftUI views
    ├── Sources/             EventKit, Gmail, OAuth, Keychain
    ├── Hotkey.swift
    └── Resources/           Info.plist, the menu bar template image, assets
```

**Why it splits into two parts:**
- **`CrossroadsCore`** is a plain Swift package with no Apple frameworks. `swift test` runs it on the Mac and in CI, and probably on Linux too (to verify). All the rules live there, so they're tested without a UI or real accounts.
- **The app** is everything that needs macOS. It's generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen), so there's no hand-edited `.xcodeproj`. That avoids merge conflicts on rebase and keeps changes reviewable. See [open question 4](#open-questions).

## Research basis

### Known

These come from Apple's documented APIs:

- **EventKit** reads every calendar in Calendar (iCloud, Google, Exchange) through `EKEventStore`, and Reminders through the same store.
  - macOS 14 changed the permission model to `requestFullAccessToEvents` / `requestFullAccessToReminders`, with the `NSCalendarsFullAccessUsageDescription` and `NSRemindersFullAccessUsageDescription` Info.plist keys.
  - Older versions use `requestAccess(to:)` with `NSCalendarsUsageDescription` and `NSRemindersUsageDescription`.
- **Events:**
  - `EKEvent` has `isAllDay`, `status` (`.tentative`, `.canceled`), and `attendees`, where your own participant carries `participantStatus` (`.declined`, `.tentative`).
  - `calendarItemExternalIdentifier` is the iCalendar UID. `occurrenceDate` tells instances of a recurring event apart.
- **Reminders:** `predicateForIncompleteReminders(withDueDateStarting:ending:calendars:)` fetches open reminders by due date.
- **Menu bar:** `MenuBarExtra` (macOS 13+) gives the menu bar icon. A floating, non-activating `NSPanel` hosting SwiftUI gives a Spotlight-style panel.
- **Global hotkey:** Carbon's `RegisterEventHotKey` registers one without Accessibility permission, and fails when another app already holds the combination.
- **Launch at login:** `SMAppService.mainApp` (macOS 13+).
- **Gmail:** Google's desktop OAuth flow with a loopback redirect works the same as on Omarchy. Tokens go into the Keychain through `SecItem`.

### Verify on the Mac before building on it

1. **A calendar shared as free/busy only** (your work calendar): does it show up in EventKit, and as one `EKEvent` per busy block, never merged, or not at all? This decides whether work conflicts work on the Mac exactly as on Omarchy.
2. **The same meeting on two calendars:** do both copies share `calendarItemExternalIdentifier`? The rule that copies never conflict depends on it.
3. **Your own response** on Google-synced events: is it available through `attendees`, so declined events can be skipped?
4. **Running `CrossroadsCore` tests on Linux** (`swift test` in a Swift container): if that works, CI can also run them on Linux. That's cheaper, and Omarchy contributors could run them.
5. **⌥⌘C:** is it free on your Mac?

**What has been checked so far:**

| # | Finding |
| --- | --- |
| 1. Free/busy calendar | **Open.** Needs the app to build. |
| 2. Shared `calendarItemExternalIdentifier` | **Open.** Needs the app to build. |
| 3. Your own response via `attendees` | **Open.** Needs the app to build. |
| 4. `CrossroadsCore` on Linux | **Not checked.** No container runtime was running, and nothing depends on it: the CI job runs on `macos-latest`, as step 2 says. Worth retrying later only to make CI cheaper. |
| 5. ⌥⌘C | **Free.** No macOS system shortcut uses it (`com.apple.symbolichotkeys` has nothing on keycode 8 with Command+Option). A third-party app could still hold it; `RegisterEventHotKey` refuses in that case, and the app keeps the old shortcut and logs it. |

Items 1 to 3 all need a working build, so they are the first thing to do in step 5.

If any answer contradicts the plan, stop and replan before going further.

## Settings on the Mac

`specs/Settings.tla` was written around files. On the Mac:

| Property | On the Mac |
| --- | --- |
| `OtherSettingsSurvive` | Applies. Each setting is its own `UserDefaults` key, so this should hold naturally, but test it anyway. |
| `OneTagPerCalendar`, `TagIsApplied`, `OtherCalendarsSurvive` | Apply. Tags are a dictionary from the calendar's `calendarIdentifier` to `personal` or `work`. A missing calendar means off. |
| `ConfigIsAlwaysWhole` | Becomes "a dictionary is saved in one write". `UserDefaults` does that, so there's no file to corrupt. |
| `ShortcutNeverConflicts` | Applies. `RegisterEventHotKey` refuses a taken combination. Keep the old shortcut when it does. |
| `OneShortcut`, `ShortcutIsApplied` | Apply: unregister the old hotkey only after the new one registers. |
| `ShortcutFileIsAlwaysWhole` | No file on the Mac. Covered by the step above. |

If the Mac needs a property the spec doesn't have, stop and go through Specify first. Don't let the Mac version quietly redefine a rule.

## Steps

Each step ends green before the next starts. Commit after each one.

1. **Conformance cases (on `main`, not this branch).** Convert the `ConflictFlags` Gherkin scenarios into `conformance/*.json`, and make the Python tests read them.
   - *Exit:* Omarchy tests and CI green on `main`, then `macos` rebased onto it.
2. **`CrossroadsCore`: conflicts.** Port `classify` and `overlaps`. Add a property test per `ConflictFlags` invariant, plus the conformance runner.
   - Add a `macos` CI job (`swift test` on `macos-latest`), and add `macos` to the root Makefile's `PLATFORMS`.
   - *Exit:* every conformance case passes, the property tests pass, and CI is green.
3. **`CrossroadsCore`: view logic.** Port ranges, grouping, timelines, sections, search, keys (vim modes, `gg` and `G`, grid moves), settings rows and cycling, and shortcut validation.
   - Port the node tests in `omarchy/plugin/tests/` alongside.
   - *Exit:* the same cases pass in Swift.
4. **App shell.** Generate the project from `project.yml`: the menu bar icon (the one-color mark as a template image), and the panel opening on the hotkey, with sample data.
   - *Exit:* the panel opens and closes from the hotkey and the menu bar, and keys work on sample data.
5. **Calendars and Reminders through EventKit.** Ask for permission, list calendars, and map events to the snapshot model (all-day, status, your response, ids) and reminders to the attention list.
   - Answer the [verify](#verify-on-the-mac-before-building-on-it) questions first.
   - *Exit:* mapping tests against recorded `EKEvent`-shaped fixtures pass, and real calendars show up.
6. **Gmail.** OAuth sign-in through the browser with a loopback redirect, the token in the Keychain, and unread messages via `labelIds=INBOX,UNREAD` (the same as Omarchy's `google.py`).
   - *Exit:* mapping tests pass, and your unread mail shows up.
7. **Refreshing.** A timer, a refresh on wake, keeping the last good data, and errors per source, so one broken source doesn't hide the others.
   - *Exit:* the same behavior as the Omarchy service, tested in core.
8. **Settings.** The settings view in the panel, `UserDefaults`, calendar tags, shortcut capture with conflict refusal, the key preset, and the default range.
   - *Exit:* the Settings properties above hold in tests, and changes apply live.
9. **For you to use daily.** `make install` builds a Release app into `/Applications`, plus launch at login.
   - *Exit:* it survives a reboot, and opens with ⌥⌘C.
10. **Docs.** Write `macos/README.md`, covering install, the permissions it asks for, and Gmail sign-in (linking the Google app steps in [`omarchy/docs/accounts.md`](../omarchy/docs/accounts.md)), and update the platform table in the root README.
    - *Exit:* a fresh read of the README is enough to install it.

## Keeping the branch easy to rebase

- Keep changes inside `macos/`. The only shared files this branch should touch are:
  - the root `Makefile` (one word in `PLATFORMS`)
  - the CI workflow (one new job)
  - the root README (one row)
- Anything shared, like conformance cases or spec changes, lands on `main` first, then rebase.
- Rebase onto `main` often: `git fetch && git rebase origin/main`.

## Open questions

Answer these before the step that needs them:

1. **Reminders (before step 5):**
   - Which reminders need attention? I'd suggest overdue ones, plus anything due today.
   - Should a reminder with a time take part in conflicts, for example "Call the school at 3:00" against a meeting?

   Either answer touches the rules, so it goes through Specify first.
2. ~~**Lowest macOS**~~ **Answered: macOS 26.** One permission path for EventKit, no fallbacks, and every current SwiftUI API.
3. ~~**Hotkey**~~ **Answered: our own Carbon wrapper,** in [`App/Hotkey.swift`](App/Hotkey.swift). No dependency.
4. ~~**XcodeGen**~~ **Answered: yes, required.** `brew install xcodegen`. `make app` regenerates the project, so no `.xcodeproj` is in the repository.
5. **Work calendar on the Mac (step 5):** is your work account on the Mac's Calendar with full details, or only the free/busy share? It changes nothing in the code, but changes what you'll see.
