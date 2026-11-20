"""The shared conformance cases for specs/ConflictFlags.tla, run against Python.

The cases in conformance/ are the same examples the Swift implementation runs,
so the two platforms cannot drift apart. See conformance/README.md.
"""

import json
from datetime import datetime, time, timezone
from pathlib import Path

import pytest

from crossroads.conflicts import Event, classify, overlaps

CASES = sorted((Path(__file__).parents[2] / "conformance").glob("*.json"))

# Every case is one modeled day. Which day it is never matters to the rules.
DAY = datetime(2026, 11, 17, tzinfo=timezone.utc).date()


def at(clock: str) -> datetime:
    return datetime.combine(DAY, time.fromisoformat(clock), tzinfo=timezone.utc)


def load(path: Path) -> dict:
    return json.loads(path.read_text())


def events_of(case: dict) -> list[Event]:
    return [
        Event(
            id=event["id"],
            calendar=event["calendar"],
            tag=event["tag"],
            title=event["id"],
            start=at(event["start"]),
            end=at(event["end"]),
            all_day=event["allDay"],
            status=event["status"],
        )
        for event in case["events"]
    ]


@pytest.mark.parametrize("path", CASES, ids=lambda path: path.stem)
def test_case(path):
    case = load(path)
    events = events_of(case)
    asserted = False

    if "kinds" in case:
        asserted = True
        kinds = {f"{event.id}@{event.calendar}": kind for event, kind in zip(events, classify(events))}
        assert kinds == case["kinds"]

    if "overlaps" in case:
        asserted = True
        # A list, not a set, so a duplicate card for the same pair shows up.
        cards = sorted(
            (sorted({card.first.id, card.second.id}), card.start, card.end)
            for card in overlaps(events)
        )
        expected = sorted(
            (sorted(card["ids"]), at(card["start"]), at(card["end"]))
            for card in case["overlaps"]
        )
        assert cards == expected

    assert asserted, "a case must assert kinds, overlaps, or both"


def test_every_case_names_a_property():
    properties = {load(path)["property"] for path in CASES}
    assert properties, "no conformance cases found"
    assert all(name.startswith("ConflictFlags.") for name in properties)
