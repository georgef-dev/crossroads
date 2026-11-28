# Crossroads for macOS

Crossroads runs on the Mac as a menu bar app: the mark in the bar with a count, and the panel on **⌥⌘C**. Calendars and reminders come straight from macOS, so there is no Google sign-in for calendars and no iCloud password. Gmail still signs in, because mail has nowhere else to come from.

See the [main README](../README.md) for what Crossroads is and why it exists.

## Install

You need a full **Xcode** (Command Line Tools alone is not enough: it has no `xcodebuild`), [XcodeGen](https://github.com/yonaskolb/XcodeGen), and macOS 26 or newer.

```bash
brew install --cask xcode   # or the App Store
brew install xcodegen
sudo xcode-select -s /Applications/Xcode.app

git clone https://github.com/georgef-dev/crossroads.git
cd crossroads/macos
make install
```

`make install` builds a Release app into `/Applications` and opens it. The mark appears in your menu bar; there is no Dock icon and no window until you ask for one.

To have it start with your Mac, tick **Open at login** in the menu bar menu.

The build is signed only ad-hoc: it is for your own machine, with no Developer ID and no notarizing. macOS may ask you to confirm the first launch.

## First run

**Calendars and reminders.** The first launch asks for access to Calendars and to Reminders, separately. Say yes to both, or Crossroads has nothing to read. If you miss the prompts, turn them on in System Settings, Privacy & Security.

**Pick your calendars.** Every calendar starts **Off**. Open the panel with ⌥⌘C, press `⌃,` for settings, and set each one to **Personal** or **Work** with `←` and `→`. A calendar left off is never read.

The tag is what makes a conflict mean something: a personal event against a work event is the thing Crossroads is for, and it cannot tell them apart until you say which is which. Reminder lists are tagged the same way.

**Gmail (optional).** Pick **Connect Gmail…** from the menu bar menu. The first time it asks for the OAuth client you made in Google Cloud, which is the same `client_secret.json` Omarchy uses: follow [the account setup guide](../omarchy/docs/accounts.md), which walks through making one. After that it asks which address, opens your browser for consent, and keeps the refresh token in your Keychain.

Crossroads asks only for `gmail.metadata`, so it reads the sender, subject and time of unread mail and has no way to read a message body. Until an account is connected, the panel leaves the unread section out.

## Using it

| Key | What it does |
| --- | --- |
| ⌥⌘C | Open and close the panel |
| Type | Search events, reminders and mail |
| ↑ ↓ ← → | Move about |
| Tab, Shift+Tab | Change the range: today, +1, +3, +7, +14 |
| Return | Open the event, reminder or mail where it lives |
| ⌃R | Fetch now |
| ⌃, | Settings |
| Esc | Clear the search, then close |

Switch **Keys** to **vim** in settings for `h j k l`, `gg`, `G`, `i` and `/`. The panel then opens in normal mode.

## Settings

| Setting | What it does |
| --- | --- |
| Refresh | How often to fetch. **Manual** fetches only on ⌃R. It also fetches when your Mac wakes. |
| Keys | Arrows only, or vim keys as well. |
| Range on open | Which range the panel starts on. |
| Shortcut | Press `→`, then the keys you want. A combination another app already holds is refused, and the old one stays. |
| Each calendar | Off, Personal or Work. |

Settings are kept in `UserDefaults`, one key each. Nothing secret goes in them.

## What it reads

- **Calendars and reminders** through EventKit, which is whatever is already in Calendar and Reminders, including the Google and iCloud accounts you have set up there.
- **Unread mail** through the Gmail API, metadata only.
- Reminders that are overdue or due today need attention. A reminder with a time of day also takes part in conflicts: one due during a meeting flags both.

Crossroads never writes to any of them. It is read-only everywhere.

## Working on it

```bash
make test        # CrossroadsCore, no UI and no account needed
make app         # build
make run         # build and restart
make demo        # the real app on made-up data, for a screenshot
make screenshot  # draw the panel to ../assets, no screen recording needed
```

The code is in two parts:

- **`Sources/CrossroadsCore`** is a plain Swift package with no Apple framework beyond Foundation: the conflict rules, the view logic and the panel's state machine. `swift test` runs it, and CI does too.
- **`App/`** is everything that needs macOS: SwiftUI, EventKit, the Keychain, the Carbon hotkey. It is kept thin on purpose.

The project is generated from `project.yml` by XcodeGen, so there is no `.xcodeproj` in the repository and `make` regenerates it whenever the file list changes.

The rules themselves are the TLA+ specs in [`specs/`](../specs), shared with Omarchy, and the cases in [`conformance/`](../conformance) are read by both platforms' tests so the two cannot drift apart.

## Known gaps

- Work email is out of scope for now, as on Omarchy.
- Nothing is signed for distribution, so this builds from source and runs on your Mac only.
- The drawing has no tests. Everything underneath it does.
