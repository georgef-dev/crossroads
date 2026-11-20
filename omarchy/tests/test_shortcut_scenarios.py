"""Gherkin scenarios for the shortcut properties in specs/Settings.tla."""

import pytest
from pytest_bdd import given, parsers, scenarios, then, when

from crossroads import files
from crossroads.shortcut import DEFAULT, ShortcutError, set_shortcut, show

scenarios("shortcut.feature")


@pytest.fixture
def hypr(tmp_path):
    return {"dir": tmp_path, "binds": [], "reloads": 0, "error": ""}


def change(hypr, combo):
    def reload():
        hypr["reloads"] += 1

    try:
        set_shortcut(combo, hypr["dir"], lambda: hypr["binds"], reload)
    except (ShortcutError, OSError) as error:
        hypr["error"] = str(error)


@given("Hyprland loads crossroads.lua")
def loads(hypr):
    (hypr["dir"] / "hyprland.lua").write_text('require("hypr.crossroads")\n')


@given(parsers.parse('"{combo}" is bound to "{description}"'))
def bound_elsewhere(hypr, combo, description):
    *modifiers, key = combo.split(" + ")
    masks = {"SUPER": 64, "CTRL": 4, "ALT": 8, "SHIFT": 1}
    hypr["binds"].append({"modmask": sum(masks[m] for m in modifiers), "key": key, "dispatcher": "__lua",
                          "arg": "31", "description": description, "submap": ""})


@given(parsers.parse('the shortcut is "{combo}"'))
def starting_shortcut(hypr, combo):
    set_shortcut(combo, hypr["dir"], lambda: [], lambda: None)


@given("the disk fails while saving")
def disk_fails(monkeypatch):
    def crash(*args, **kwargs):
        raise OSError("disk went away")

    monkeypatch.setattr(files.os, "replace", crash)


@when(parsers.parse('I change the shortcut to "{combo}"'))
def change_to(hypr, combo):
    change(hypr, combo)


@when("I reset the shortcut")
def reset(hypr):
    change(hypr, DEFAULT)


@then(parsers.parse('the shortcut is "{combo}"'))
def shortcut_is(hypr, combo):
    assert show(hypr["dir"]) == combo


@then(parsers.parse('the change fails with "{text}"'))
def fails_with(hypr, text):
    assert text in hypr["error"]


@then("Hyprland was reloaded")
def reloaded(hypr):
    assert hypr["reloads"] == 1


@then("Hyprland was not reloaded")
def not_reloaded(hypr):
    assert hypr["reloads"] == 0
