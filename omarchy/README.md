# Crossroads for Omarchy

Crossroads runs on [Omarchy](https://omarchy.org) as a shell plugin: an icon in the bar, and a full view on **Super+Alt+C**. A Python command, `crossroads fetch`, does the fetching and works out every conflict; the plugin, written in QML, only draws what it gets back.

See the [main README](../README.md) for what Crossroads is and why it exists.

## Install

You need Omarchy, Python 3.12 or newer, `make` and `rsync`.

```bash
git clone https://github.com/georgef-dev/crossroads.git
cd crossroads/omarchy
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

## Development

From this folder:

- `make test` runs the Python and node tests.
- `make validate` checks the plugin against Omarchy's manifest rules. It needs Omarchy, so it isn't part of CI.
- `make install` installs your working copy. Changes to the bar widget reload live. Changes to the modal, the service, or new files need `omarchy restart shell`.

The specs these tests are derived from live in [`specs/`](../specs) at the repository root, and `make check` there model-checks them.

## Privacy

- Passwords and tokens live in your desktop keyring (gnome-keyring), under the service `crossroads`. They never go into config files, logs or snapshots.
- `~/.config/crossroads/config.json` holds only your accounts and how each calendar is tagged.
