"""The Hyprland shortcut that opens Crossroads, kept in ~/.config/hypr/crossroads.lua.

Spec: specs/Settings.tla (ShortcutNeverConflicts, OneShortcut, ShortcutIsApplied,
ShortcutFileIsAlwaysWhole). hyprland.lua loads the file with
require("hypr.crossroads"); Crossroads owns it and rewrites it whole.
"""

import json
import re
import subprocess
from pathlib import Path

from crossroads.files import write_atomically

DEFAULT = "SUPER + ALT + C"
DESCRIPTION = "Crossroads"
MODIFIERS = {"SUPER": 64, "CTRL": 4, "ALT": 8, "SHIFT": 1}  # in the order they're written
KEYS = {*"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", *(f"F{n}" for n in range(1, 13)), "SPACE"}
BIND_LINE = re.compile(r'^o\.bind\("([^"]+)"')
REQUIRE = 'require("hypr.crossroads")'


class ShortcutError(Exception):
    pass


def hypr_dir() -> Path:
    return Path.home() / ".config" / "hypr"


def canonical(combo: str) -> str:
    """One way to write a combination, or ShortcutError when it can't be a shortcut."""
    parts = [part.strip().upper() for part in combo.split("+")]
    *modifiers, key = parts
    if key not in KEYS or len(set(modifiers)) != len(modifiers) or not set(modifiers) <= set(MODIFIERS):
        raise ShortcutError(f"{combo!r} isn't a shortcut: use Super, Ctrl or Alt with a letter, digit, F1-F12 or Space")
    if not set(modifiers) - {"SHIFT"}:
        raise ShortcutError(f"{combo!r} needs Super, Ctrl or Alt")
    return " + ".join([m for m in MODIFIERS if m in modifiers] + [key])


def show(directory: Path | None = None) -> str:
    path = (directory or hypr_dir()) / "crossroads.lua"
    if not path.exists():
        return DEFAULT
    for line in path.read_text().splitlines():
        match = BIND_LINE.match(line)
        if match:
            return match.group(1)
    return DEFAULT


def set_shortcut(combo: str, directory: Path | None = None, binds=None, reload=None, *, loaded_check=True) -> str:
    """Bind Crossroads to `combo`, unless another binding uses it. Returns the saved combination."""
    directory = directory or hypr_dir()
    binds = binds or hyprctl_binds
    reload = reload or _hyprctl_reload
    combo = canonical(combo)

    hyprland = directory / "hyprland.lua"
    if loaded_check and REQUIRE not in (hyprland.read_text() if hyprland.exists() else ""):
        raise ShortcutError(f"{hyprland} must load the shortcut with {REQUIRE}: run crossroads setup shortcut")

    def refuse_if_taken():
        taken_by = _taken_by(combo, binds())
        if taken_by:
            raise ShortcutError(f"{combo} is already bound to {taken_by}")

    refuse_if_taken()
    # Checked again right before the rename, since another binding may have taken
    # the combination while the file was written. A tiny window remains between
    # that check and the rename.
    write_atomically(directory / "crossroads.lua", _lua(combo), before_replace=refuse_if_taken)
    reload()
    return combo


def setup(directory: Path | None = None, binds=None, reload=None) -> None:
    """Bind Crossroads in Hyprland: write crossroads.lua, then load it from hyprland.lua.

    That order means Hyprland never loads a file that doesn't exist yet. A
    shortcut already chosen is kept, and running setup again changes nothing.
    """
    directory = directory or hypr_dir()
    reload = reload or _hyprctl_reload
    hyprland = directory / "hyprland.lua"
    if not hyprland.exists():
        raise ShortcutError(f"no {hyprland}; is Hyprland set up?")

    changed = False
    if not (directory / "crossroads.lua").exists():
        set_shortcut(DEFAULT, directory, binds, lambda: None, loaded_check=False)
        changed = True

    text = hyprland.read_text()
    if REQUIRE not in text:
        block = f"\n-- Crossroads shortcut, written by its settings view (Super+Alt+C by default).\n{REQUIRE}\n"
        write_atomically(hyprland, text + ("" if text.endswith("\n") else "\n") + block)
        changed = True

    if changed:
        reload()


def _hyprctl_reload() -> None:
    subprocess.run(["hyprctl", "reload"], capture_output=True, check=True)


def hyprctl_binds() -> list[dict]:
    result = subprocess.run(["hyprctl", "binds", "-j"], capture_output=True, text=True, check=True)
    return json.loads(result.stdout)


def _taken_by(combo: str, binds: list[dict]) -> str:
    """What else uses `combo` in Hyprland's global keymap, or "" when it's free."""
    *modifiers, key = combo.split(" + ")
    mask = sum(MODIFIERS[m] for m in modifiers)
    for bind in binds:
        if bind.get("submap", "") or bind.get("description") == DESCRIPTION:
            continue
        if bind.get("modmask") == mask and str(bind.get("key", "")).upper() == key:
            return bind.get("description") or bind.get("dispatcher") or "another binding"
    return ""


def _lua(combo: str) -> str:
    return (
        "-- Written by Crossroads (crossroads shortcut, or its settings view).\n"
        "-- Rewritten whole on every change, so edit the shortcut there.\n"
        f'o.bind("{combo}", "{DESCRIPTION}", hl.dsp.global("crossroads:toggle"))\n'
    )
