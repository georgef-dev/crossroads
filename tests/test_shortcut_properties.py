"""Property-based tests derived from the shortcut invariants in specs/Settings.tla,
for `crossroads shortcut` (shortcut.set_shortcut), against a fake hyprctl.
"""

import tempfile
from pathlib import Path

import pytest
from hypothesis import given
from hypothesis import strategies as st

from crossroads import files, shortcut
from crossroads.shortcut import DEFAULT, ShortcutError, set_shortcut, show

COMBOS = ["SUPER + ALT + C", "SUPER + ALT + X", "SUPER + ALT + Y", "CTRL + ALT + J", "SUPER + F5"]
MASKS = {"SUPER": 64, "CTRL": 4, "ALT": 8, "SHIFT": 1}


def bind(combo, description="Something else", submap=""):
    *mods, key = [part.strip() for part in combo.split("+")]
    return {"modmask": sum(MASKS[m] for m in mods), "key": key, "dispatcher": "__lua", "arg": "1",
            "description": description, "submap": submap}


def hypr_dir(directory: Path) -> Path:
    (directory / "hyprland.lua").write_text('require("hypr.bindings")\nrequire("hypr.crossroads")\n')
    return directory


def bound_combos(directory: Path) -> list[str]:
    """Every combination crossroads.lua binds, read straight from the file."""
    text = (directory / "crossroads.lua").read_text()
    return [line.split('"')[1] for line in text.splitlines() if line.startswith("o.bind(")]


@given(st.sets(st.sampled_from(COMBOS[1:])), st.lists(st.sampled_from(COMBOS + ["reset"]), max_size=5))
def test_Settings_shortcut_changes(taken, steps):
    with tempfile.TemporaryDirectory() as directory:
        directory = hypr_dir(Path(directory))
        binds = [bind(c) for c in taken] + [bind("SUPER + ALT + T")]
        for step in steps:
            before = (directory / "crossroads.lua").read_text() if (directory / "crossroads.lua").exists() else None
            combo = DEFAULT if step == "reset" else step
            try:
                set_shortcut(combo, directory, lambda: binds, lambda: None)
                refused = False
            except ShortcutError:
                refused = True

            # Settings.OneShortcut: there is always exactly one Crossroads shortcut.
            if (directory / "crossroads.lua").exists():
                assert len(bound_combos(directory)) == 1

            # Settings.ShortcutNeverConflicts: it never takes a combination another binding uses.
            assert show(directory) not in taken

            # Settings.ShortcutIsApplied: a saved change binds exactly that combination; reset gives the default.
            if refused:
                after = (directory / "crossroads.lua").read_text() if (directory / "crossroads.lua").exists() else None
                assert after == before
                assert combo in taken
            else:
                assert bound_combos(directory) == [combo]
                assert show(directory) == combo


def test_Settings_ShortcutNeverConflicts_rechecks_right_before_saving(tmp_path):
    """The race TLC found: another binding takes the combination while it is being written."""
    directory = hypr_dir(tmp_path)
    set_shortcut(DEFAULT, directory, lambda: [], lambda: None)
    before = (directory / "crossroads.lua").read_bytes()
    checks = iter([[], [bind("SUPER + ALT + Y")]])

    with pytest.raises(ShortcutError, match="already"):
        set_shortcut("SUPER + ALT + Y", directory, lambda: next(checks), lambda: None)

    assert (directory / "crossroads.lua").read_bytes() == before
    assert sorted(p.name for p in directory.iterdir()) == ["crossroads.lua", "hyprland.lua"]


@pytest.mark.parametrize("failing", ["fsync", "replace"])
def test_Settings_ShortcutFileIsAlwaysWhole_a_failed_write_keeps_the_old_file(tmp_path, monkeypatch, failing):
    directory = hypr_dir(tmp_path)
    set_shortcut(DEFAULT, directory, lambda: [], lambda: None)
    before = (directory / "crossroads.lua").read_bytes()

    def crash(*args, **kwargs):
        raise OSError("disk went away")

    monkeypatch.setattr(files.os, failing, crash)
    with pytest.raises(OSError):
        set_shortcut("SUPER + ALT + X", directory, lambda: [], lambda: None)

    assert (directory / "crossroads.lua").read_bytes() == before
    assert sorted(p.name for p in directory.iterdir()) == ["crossroads.lua", "hyprland.lua"]


def test_its_own_binding_and_submap_bindings_are_not_conflicts(tmp_path):
    directory = hypr_dir(tmp_path)
    binds = [bind(DEFAULT, "Crossroads"), bind("SUPER + ALT + X", submap="omacast")]

    set_shortcut("SUPER + ALT + X", directory, lambda: binds, lambda: None)
    set_shortcut(DEFAULT, directory, lambda: binds, lambda: None)

    assert show(directory) == DEFAULT


def test_hyprland_reloads_only_after_a_saved_change(tmp_path):
    directory = hypr_dir(tmp_path)
    reloads = []

    set_shortcut("SUPER + ALT + X", directory, lambda: [], lambda: reloads.append(1))
    with pytest.raises(ShortcutError):
        set_shortcut("SUPER + ALT + T", directory, lambda: [bind("SUPER + ALT + T")], lambda: reloads.append(1))

    assert reloads == [1]


def test_without_the_require_line_nothing_is_written(tmp_path):
    (tmp_path / "hyprland.lua").write_text('require("hypr.bindings")\n')

    with pytest.raises(ShortcutError, match='require\\("hypr.crossroads"\\)'):
        set_shortcut("SUPER + ALT + X", tmp_path, lambda: [], lambda: None)

    assert not (tmp_path / "crossroads.lua").exists()


@pytest.mark.parametrize(("given", "canonical"), [
    ("SUPER + ALT + C", "SUPER + ALT + C"),
    ("alt+super+c", "SUPER + ALT + C"),
    ("CTRL + SHIFT + ALT + SUPER + F12", "SUPER + CTRL + ALT + SHIFT + F12"),
    ("SUPER + SPACE", "SUPER + SPACE"),
    ("ctrl + 7", "CTRL + 7"),
])
def test_combinations_are_written_one_way(given, canonical):
    assert shortcut.canonical(given) == canonical


@pytest.mark.parametrize("bad", ["C", "SHIFT + C", "SUPER + ALT", "SUPER + ALT + RETURN", "SUPER + HYPER + C",
                                 "SUPER + ALT + CC", "", "SUPER + ALT + \"); os.exit(", "SUPER + F13"])
def test_invalid_combinations_are_rejected(bad):
    with pytest.raises(ShortcutError):
        shortcut.canonical(bad)


def test_show_is_the_default_without_a_file(tmp_path):
    assert show(tmp_path) == DEFAULT
