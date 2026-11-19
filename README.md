<p align="center">
  <img src="assets/lockup.png" alt="Crossroads, where your personal and work days meet" width="640">
</p>

# Crossroads

I run my life across too many systems: a family calendar, a work calendar, a couple of inboxes, todos somewhere else. Answering something as simple as "can I take that 3pm call?" means opening four apps and stitching the answer together in my head.

Crossroads brings them into one place, so I can see everything at a glance and make a well-informed call in a fraction of the time. It starts with calendars and mail, and it's built to take in more.

## What it does

Crossroads brings into focus what needs your attention right now.

- **Conflicts.** A meeting that lands on school pickup shows up before it bites, along with exactly how long the two overlap. A personal event against a work event stands out from a double-booked work slot.
- **Today.** Your day as one strip, with a marker for now.
- **Unread mail.** What just came in, next to your day.

Everything is searchable, and one keypress opens the event or email where it lives.

## Status

- Runs on [Omarchy](https://omarchy.org) as a shell plugin: an icon in the bar, and a full view on **Super+Alt+C**. A Mac version is planned.
- Reads Google Calendar, Gmail and iCloud Calendar. Apple Reminders is planned.
- Read-only and local. Crossroads never changes your calendars or mail, and it only talks to Google and iCloud.
- CI checks the specs and runs the tests on every push. There are no releases yet, so install from source.
- Early, and built for my own use first. Expect rough edges.

## Install

You need Omarchy, Python 3.12 or newer, `make` and `rsync`.

```bash
git clone https://github.com/georgef-dev/crossroads.git
cd crossroads
make install
omarchy restart shell
omarchy plugin enable georgef.crossroads
```

`make install` puts the `crossroads` command in `~/.local/share/crossroads/` and copies the plugin into `~/.config/omarchy/plugins/georgef.crossroads/`. The first time, the shell only finds the new plugin after a restart, and enabling it adds the icon to your bar. Later installs do both on their own.

Put the command on your `PATH`, then bind the shortcut:

```bash
ln -s ~/.local/share/crossroads/venv/bin/crossroads ~/.local/bin/crossroads
crossroads setup shortcut
```

`setup shortcut` binds Super+Alt+C in `~/.config/hypr/crossroads.lua` and loads it from your `hyprland.lua`. It never touches your own bindings, it refuses a combination something else already uses, and running it again changes nothing.

## Connect your accounts

Google needs an OAuth app of your own, iCloud needs an app-specific password, and a work calendar behind company SSO can come in as free/busy. **[docs/accounts.md](docs/accounts.md)** walks through each one, step by step.

## Using it

Open Crossroads with **Super+Alt+C**, or click its bar icon for a compact view.

| | Default keys | Vim keys |
| --- | --- | --- |
| Move | ↑ ↓ ← → | h j k l, `gg` first, `G` last |
| Search | Just type | `i` or `/`, then type. Esc goes back to moving |
| Open the selected event or email | Enter | Enter |
| Change the range (today, +1, +3, +7, +14 days) | Tab, Shift+Tab | Tab, Shift+Tab |
| Refresh now | Ctrl+R | Ctrl+R |
| Settings | Ctrl+, | Ctrl+, |
| Close | Esc (clears the search first) | Esc |

With vim keys, Crossroads opens ready to move. With default keys, it opens ready to search.

**Settings** (Ctrl+,) has:

- how often to refresh (off, or every 15 to 120 minutes)
- default or vim keys
- the range it opens on
- the shortcut that opens it. Press Enter, then the new combination. Backspace resets it to Super+Alt+C.
- Off / Personal / Work for every calendar your accounts can see

The command line covers the same ground:

| Command | What it does |
| --- | --- |
| `crossroads fetch` | Prints the snapshot the plugin shows, as JSON |
| `crossroads calendars <google\|icloud> <account>` | Lists an account's calendars |
| `crossroads calendars --json` | Every configured account's calendars, with their tags |
| `crossroads tag <provider> <account> <calendar> personal\|work\|off` | Tags a calendar |
| `crossroads shortcut [set "SUPER + ALT + X" \| reset]` | Shows or changes the shortcut |
| `crossroads setup shortcut` | Binds the shortcut in Hyprland the first time |
| `crossroads auth …` | Signs in to an account ([docs/accounts.md](docs/accounts.md)) |

## How it's built

- A Python command, `crossroads fetch`, does all the fetching and works out every conflict. The Omarchy plugin, written in QML, only draws what it gets back.
- The rules live in [TLA+](https://lamport.azurewebsites.net/tla/tla.html) specs in [`specs/`](specs), and the specs are the source of truth:
  - **`ConflictFlags`** covers what counts as a conflict and which overlaps get a card.
  - **`Settings`** covers saving settings, calendar tags and the shortcut without ever corrupting a file or stealing another binding.

  The TLC model checker checks both specs. Every property has tests named after it: Hypothesis property tests, Gherkin scenarios, and node tests for the plugin's logic.
- To work on it:
  - `make check` model-checks the specs. It needs `tlc`, or set `TLC` to a `java -cp tla2tools.jar tlc2.TLC` command.
  - `make test` runs the Python and node tests.
  - `make validate` checks the plugin against Omarchy's manifest rules. It needs Omarchy, so it isn't part of CI.
- After `make install`, changes to the bar widget reload live. Changes to the modal, the service, or new files need `omarchy restart shell`.

## Privacy

- Passwords and tokens live in your desktop keyring (gnome-keyring), under the service `crossroads`. They never go into config files, logs or snapshots.
- `~/.config/crossroads/config.json` holds only your accounts and how each calendar is tagged.
- Google access is read-only. Crossroads reads calendars, and the sender and subject of unread mail. It never reads message bodies.
- iCloud access uses an app-specific password over read-only CalDAV.
- There is no Crossroads server, no telemetry and no analytics.

## License

[MIT](LICENSE)
