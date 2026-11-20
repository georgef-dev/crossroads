"""`crossroads setup shortcut`: bind Crossroads in Hyprland in one step, safely and only once."""

import pytest

from crossroads import files
from crossroads.shortcut import DEFAULT, ShortcutError, set_shortcut, setup, show

HYPRLAND = 'require("hypr.bindings")\n\n-- Add any other personal Hyprland configuration below.\n'


def hypr(tmp_path, text=HYPRLAND):
    (tmp_path / "hyprland.lua").write_text(text)
    return tmp_path


class Reloads:
    def __init__(self):
        self.count = 0

    def __call__(self):
        self.count += 1


def test_fresh_setup_writes_the_shortcut_then_loads_it(tmp_path):
    directory = hypr(tmp_path)
    reload = Reloads()

    setup(directory, lambda: [], reload)

    assert show(directory) == DEFAULT
    hyprland = (directory / "hyprland.lua").read_text()
    assert hyprland.startswith(HYPRLAND)
    assert hyprland.count('require("hypr.crossroads")') == 1
    assert reload.count == 1


def test_running_setup_again_changes_nothing(tmp_path):
    directory = hypr(tmp_path)
    setup(directory, lambda: [], lambda: None)
    before = {p.name: p.read_bytes() for p in directory.iterdir()}
    reload = Reloads()

    setup(directory, lambda: [], reload)

    assert {p.name: p.read_bytes() for p in directory.iterdir()} == before
    assert reload.count == 0


def test_a_shortcut_already_chosen_is_kept(tmp_path):
    directory = hypr(tmp_path, HYPRLAND + 'require("hypr.crossroads")\n')
    set_shortcut("SUPER + ALT + X", directory, lambda: [], lambda: None)

    setup(directory, lambda: [], lambda: None)

    assert show(directory) == "SUPER + ALT + X"


def test_a_taken_default_is_refused_and_nothing_changes(tmp_path):
    directory = hypr(tmp_path)
    taken = [{"modmask": 72, "key": "C", "description": "Calculator", "submap": ""}]

    with pytest.raises(ShortcutError, match="Calculator"):
        setup(directory, lambda: taken, lambda: None)

    assert sorted(p.name for p in directory.iterdir()) == ["hyprland.lua"]
    assert (directory / "hyprland.lua").read_text() == HYPRLAND


def test_without_hyprland_lua_nothing_is_written(tmp_path):
    with pytest.raises(ShortcutError, match="hyprland.lua"):
        setup(tmp_path, lambda: [], lambda: None)

    assert list(tmp_path.iterdir()) == []


def test_a_failed_write_keeps_hyprland_lua_whole(tmp_path, monkeypatch):
    directory = hypr(tmp_path)
    real_replace = files.os.replace

    def fail_for_hyprland(source, target):
        if str(target).endswith("hyprland.lua"):
            raise OSError("disk went away")
        real_replace(source, target)

    monkeypatch.setattr(files.os, "replace", fail_for_hyprland)
    with pytest.raises(OSError):
        setup(directory, lambda: [], lambda: None)

    assert (directory / "hyprland.lua").read_text() == HYPRLAND
    # The shortcut file may already exist; nothing loads it yet, so Hyprland is unaffected.
    assert sorted(p.name for p in directory.iterdir()) in (["hyprland.lua"], ["crossroads.lua", "hyprland.lua"])
