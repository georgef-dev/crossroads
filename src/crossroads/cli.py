"""crossroads: sign in to accounts, list their calendars, and fetch a snapshot for the plugin."""

import argparse
import getpass
import json
import sys
from datetime import datetime

from crossroads import calendars as calendar_listing
from crossroads import config, google, icloud, shortcut, snapshot


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="crossroads")
    commands = parser.add_subparsers(dest="command", required=True)

    auth = commands.add_parser("auth", help="sign in to an account").add_subparsers(dest="provider", required=True)
    auth.add_parser("google-client", help="store the Google OAuth client").add_argument("client_file")
    auth.add_parser("google", help="sign in to a Google account").add_argument("account")
    auth.add_parser("icloud", help="store an iCloud app-specific password").add_argument("account")

    calendars = commands.add_parser("calendars", help="list an account's calendars, to tag them in the config")
    calendars.add_argument("provider", nargs="?", choices=config.PROVIDERS)
    calendars.add_argument("account", nargs="?")
    calendars.add_argument("--json", action="store_true", help="every configured account, with tags, as JSON")

    tag = commands.add_parser("tag", help="tag a calendar personal or work, or remove it with off")
    tag.add_argument("provider", choices=config.PROVIDERS)
    tag.add_argument("account")
    tag.add_argument("calendar")
    tag.add_argument("choice", choices=("personal", "work", "off"))
    tag.add_argument("--name", default="", help="name shown in the view")

    keys = commands.add_parser("shortcut", help="show or change the Hyprland shortcut that opens Crossroads")
    keys.add_argument("action", nargs="?", choices=("show", "set", "reset"), default="show")
    keys.add_argument("combo", nargs="?", help='for set, like "SUPER + ALT + C"')

    commands.add_parser("fetch", help="print a JSON snapshot for the plugin")

    args = parser.parse_args(argv)
    if args.command == "fetch":
        return _fetch()
    try:
        if args.command == "auth":
            return _auth(args)
        if args.command == "shortcut":
            return _shortcut(args.action, args.combo, parser)
        if args.command == "tag":
            config.set_tag(config.default_path(), args.provider, args.account, args.calendar, args.choice, args.name)
            return 0
        if args.json:
            print(json.dumps(calendar_listing.listing(config.load())))
            return 0
        if not (args.provider and args.account):
            parser.error("calendars needs a provider and an account, or --json")
        return _calendars(args.provider, args.account)
    except (config.ConfigError, google.GoogleError, icloud.ICloudError, shortcut.ShortcutError, OSError) as error:
        print(f"crossroads: {error}", file=sys.stderr)
        return 1


def _auth(args) -> int:
    if args.provider == "google-client":
        google.save_client(args.client_file)
        print("Stored the Google OAuth client in the keyring.")
    elif args.provider == "google":
        google.sign_in(args.account)
        print(f"Signed in {args.account}.")
    else:
        icloud.save_password(args.account, getpass.getpass(f"App-specific password for {args.account}: "))
        print(f"Stored the password for {args.account}.")
    return 0


def _calendars(provider: str, account: str) -> int:
    if provider == "google":
        for calendar in google.list_calendars(account):
            print(f"{calendar['id']}  {calendar.get('summary', '')}  ({calendar.get('accessRole', '')})")
    else:
        for href, name in icloud.list_calendars(account):
            print(f"{href}  {name}")
    return 0


def _shortcut(action: str, combo: str | None, parser) -> int:
    if action == "set" and not combo:
        parser.error('shortcut set needs a combination, like "SUPER + ALT + C"')
    if action == "set":
        shortcut.set_shortcut(combo)
    elif action == "reset":
        shortcut.set_shortcut(shortcut.DEFAULT)
    print(shortcut.show())
    return 0


def _fetch() -> int:
    # Always print a snapshot, so the plugin can show what went wrong.
    now = datetime.now().astimezone()
    try:
        result = snapshot.build(config.load(), now)
    except config.ConfigError as error:
        result = snapshot.failed(now, "config", error)
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
