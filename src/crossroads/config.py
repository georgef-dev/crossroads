"""Accounts and calendar tags from ~/.config/crossroads/config.json. Never holds secrets.

Example:
    {
      "google": [
        {"account": "me@gmail.com", "mail": true,
         "calendars": [{"id": "primary", "tag": "personal"},
                       {"id": "me@work.com", "tag": "work", "name": "Work"}]}
      ],
      "icloud": [
        {"account": "me@icloud.com",
         "calendars": [{"id": "/123/calendars/home/", "tag": "personal"}]}
      ]
    }
"""

import json
import os
from dataclasses import dataclass
from pathlib import Path

from crossroads.conflicts import TAGS

PROVIDERS = ("google", "icloud")


class ConfigError(Exception):
    pass


@dataclass(frozen=True)
class Calendar:
    id: str
    tag: str
    name: str = ""  # shown in the view; the id is used when it's empty


@dataclass(frozen=True)
class Account:
    provider: str
    account: str
    mail: bool
    calendars: tuple[Calendar, ...]


def default_path() -> Path:
    config_home = os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config"
    return Path(config_home) / "crossroads" / "config.json"


def load(path: Path | None = None) -> list[Account]:
    path = path or default_path()
    return _accounts(_read(path), path)


def set_tag(path: Path, provider: str, account: str, calendar_id: str, choice: str, name: str = "") -> None:
    """Tag a calendar personal or work, or remove it with "off". Spec: specs/Settings.tla.

    Everything else in the file stays as it is. The new file is validated, then
    written to a temp file and renamed over the old one, so a failure at any
    point leaves the old config in place.
    """
    if choice not in (*TAGS, "off"):
        raise ConfigError(f"{calendar_id} needs a tag of {', '.join((*TAGS, 'off'))}, got {choice!r}")

    data = _read(path)
    _accounts(data, path)
    entry = next((e for e in data.get(provider, []) if e.get("account") == account), None)
    if entry is None:
        raise ConfigError(f"{account} is not a configured {provider} account")

    calendars = entry.get("calendars", [])
    previous = next((c for c in calendars if c.get("id") == calendar_id), {})
    if choice == "off":
        entry["calendars"] = [c for c in calendars if c.get("id") != calendar_id]
    elif previous:
        entry["calendars"] = [{**c, "tag": choice} if c is previous else c for c in calendars]
    else:
        added = {"id": calendar_id, "tag": choice}
        if name:
            added["name"] = name
        entry["calendars"] = [*calendars, added]

    _accounts(data, path)
    _replace(path, json.dumps(data, indent=2) + "\n")


def _read(path: Path):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        raise ConfigError(f"no config at {path}") from None
    except json.JSONDecodeError as error:
        raise ConfigError(f"{path} is not valid JSON: {error}") from None


def _replace(path: Path, text: str) -> None:
    temp = path.with_name(f".{path.name}.tmp")
    try:
        with open(temp, "w") as file:
            file.write(text)
            file.flush()
            os.fsync(file.fileno())
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)


def _accounts(data, path: Path) -> list[Account]:
    if not isinstance(data, dict):
        raise ConfigError(f"{path} must hold a JSON object")
    unknown = set(data) - set(PROVIDERS)
    if unknown:
        raise ConfigError(f"unknown providers: {', '.join(sorted(unknown))}")

    return [
        _account(provider, entry)
        for provider in PROVIDERS
        for entry in data.get(provider, [])
    ]


def _account(provider: str, entry: dict) -> Account:
    account = entry.get("account")
    if not isinstance(account, str) or not account:
        raise ConfigError(f"a {provider} entry is missing its account")

    calendars = tuple(_calendar(account, item) for item in entry.get("calendars", []))
    ids = [calendar.id for calendar in calendars]
    duplicates = sorted({id for id in ids if ids.count(id) > 1})
    if duplicates:
        raise ConfigError(f"{account}: each calendar is tagged once, but these repeat: {', '.join(duplicates)}")

    mail = entry.get("mail", False)
    if provider == "icloud" and mail:
        raise ConfigError(f"{account}: mail is only read from Gmail")

    return Account(provider, account, bool(mail), calendars)


def _calendar(account: str, item: dict) -> Calendar:
    calendar_id = item.get("id")
    if not isinstance(calendar_id, str) or not calendar_id:
        raise ConfigError(f"{account}: a calendar is missing its id")
    tag = item.get("tag")
    if tag not in TAGS:
        raise ConfigError(f"{account}: calendar {calendar_id} needs a tag of {' or '.join(TAGS)}, got {tag!r}")
    name = item.get("name", "")
    if not isinstance(name, str):
        raise ConfigError(f"{account}: calendar {calendar_id} has a name that isn't text")
    return Calendar(calendar_id, tag, name)
