"""Property-based tests derived from the invariants in specs/Settings.tla, for
`crossroads tag` (config.set_tag). The properties are restated from the spec's
English lines and read the file back, so they don't share the code under test.
"""

import json
import tempfile
from pathlib import Path

import pytest
from hypothesis import given
from hypothesis import strategies as st

from crossroads import config
from crossroads.config import ConfigError, set_tag

ACCOUNT = "me@icloud.com"
CALENDARS = ["home", "family", "work"]
CHOICES = ["personal", "work", "off"]


def write_config(directory: Path, tags: dict) -> Path:
    path = directory / "config.json"
    path.write_text(json.dumps({
        "google": [{"account": "me@gmail.com", "mail": True, "calendars": [{"id": "primary", "tag": "personal"}]}],
        "icloud": [{"account": ACCOUNT, "calendars": [
            {"id": calendar, "tag": tag, "name": calendar.title()} for calendar, tag in tags.items()
        ]}],
    }))
    return path


def icloud_calendars(path: Path) -> list[dict]:
    return json.loads(path.read_text())["icloud"][0]["calendars"]


starting_tags = st.dictionaries(st.sampled_from(CALENDARS), st.sampled_from(["personal", "work"]))
changes = st.lists(st.tuples(st.sampled_from(CALENDARS), st.sampled_from(CHOICES)), max_size=6)


@given(starting_tags, changes)
def test_Settings_tag_changes(tags, steps):
    with tempfile.TemporaryDirectory() as directory:
        path = write_config(Path(directory), tags)
        for calendar, choice in steps:
            before = icloud_calendars(path)
            set_tag(path, "icloud", ACCOUNT, calendar, choice)
            after = icloud_calendars(path)

            # Settings.OneTagPerCalendar: each calendar has at most one tag.
            ids = [entry["id"] for entry in after]
            assert len(ids) == len(set(ids))

            # Settings.TagIsApplied: the calendar gets exactly that tag, and "off" removes it.
            mine = [entry for entry in after if entry["id"] == calendar]
            if choice == "off":
                assert mine == []
            else:
                assert [entry["tag"] for entry in mine] == [choice]

            # Settings.OtherCalendarsSurvive: every other calendar stays as it was.
            assert [e for e in after if e["id"] != calendar] == [e for e in before if e["id"] != calendar]

            # Settings.TypeOK: config.json only holds calendar tags, and stays loadable.
            assert all(entry["tag"] in ("personal", "work") for entry in after)
            config.load(path)


@given(starting_tags, st.sampled_from(CALENDARS), st.sampled_from(CHOICES))
def test_Settings_tag_changes_leave_other_accounts_and_fields_alone(tags, calendar, choice):
    with tempfile.TemporaryDirectory() as directory:
        path = write_config(Path(directory), tags)
        google_before = json.loads(path.read_text())["google"]

        set_tag(path, "icloud", ACCOUNT, calendar, choice)

        assert json.loads(path.read_text())["google"] == google_before


def test_Settings_TypeOK_rejects_a_bad_tag(tmp_path):
    path = write_config(tmp_path, {"home": "personal"})
    before = path.read_bytes()

    with pytest.raises(ConfigError, match="tag"):
        set_tag(path, "icloud", ACCOUNT, "home", "family")

    assert path.read_bytes() == before


@pytest.mark.parametrize("failing", ["fsync", "replace"])
def test_Settings_ConfigIsAlwaysWhole_a_failed_write_keeps_the_old_file(tmp_path, monkeypatch, failing):
    path = write_config(tmp_path, {"home": "personal", "family": "work"})
    before = path.read_bytes()

    def crash(*args, **kwargs):
        raise OSError("disk went away")

    monkeypatch.setattr(config.os, failing, crash)
    with pytest.raises(OSError):
        set_tag(path, "icloud", ACCOUNT, "home", "work")

    assert path.read_bytes() == before
    assert [p.name for p in tmp_path.iterdir()] == ["config.json"]
