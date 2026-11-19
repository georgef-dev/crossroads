"""Gherkin scenarios for specs/Settings.tla, tagged by property."""

import json

import pytest
from pytest_bdd import given, parsers, scenarios, then, when

from crossroads import config
from crossroads.config import set_tag

scenarios("settings.feature")


def rows(datatable):
    header, *body = datatable
    return [dict(zip(header, row)) for row in body]


@pytest.fixture
def outcome():
    return {}


@given(parsers.parse('a config where "{account}" has these calendars:'), target_fixture="path")
def a_config(tmp_path, account, datatable):
    path = tmp_path / "config.json"
    path.write_text(json.dumps({"icloud": [{"account": account, "calendars": rows(datatable)}]}))
    return path


@given("the disk fails while saving")
def the_disk_fails(monkeypatch):
    def crash(*args, **kwargs):
        raise OSError("disk went away")

    monkeypatch.setattr(config.os, "replace", crash)


def tag(path, outcome, calendar, choice, account="me@icloud.com", name=""):
    outcome["before"] = path.read_bytes()
    try:
        set_tag(path, "icloud", account, calendar, choice, name)
    except (config.ConfigError, OSError) as error:
        outcome["error"] = str(error)


@when(parsers.parse('I tag "{calendar}" as "{choice}"'))
def tag_calendar(path, outcome, calendar, choice):
    tag(path, outcome, calendar, choice)


@when(parsers.parse('I tag "{calendar}" named "{name}" as "{choice}"'))
def tag_named_calendar(path, outcome, calendar, name, choice):
    tag(path, outcome, calendar, choice, name=name)


@when(parsers.parse('I tag "{calendar}" on "{account}" as "{choice}"'))
def tag_on_account(path, outcome, calendar, account, choice):
    tag(path, outcome, calendar, choice, account=account)


@then(parsers.parse('"{account}" has these calendars:'))
def has_calendars(path, account, datatable):
    [entry] = [e for e in json.loads(path.read_text())["icloud"] if e["account"] == account]
    assert entry["calendars"] == rows(datatable)


@then(parsers.parse('the change fails with "{text}"'))
def change_fails(outcome, text):
    assert text in outcome.get("error", "")


@then("config.json is unchanged")
def unchanged(path, outcome):
    assert path.read_bytes() == outcome["before"]
