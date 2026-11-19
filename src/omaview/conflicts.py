"""Which events overlap, and how each one is shown. Spec: specs/ConflictFlags.tla."""

from dataclasses import dataclass
from datetime import datetime

PERSONAL = "personal"
WORK = "work"
TAGS = (PERSONAL, WORK)

STATUSES = ("accepted", "tentative", "declined", "cancelled")
ACTIVE_STATUSES = ("accepted", "tentative")

NONE = "none"
SAME = "same"
MIXED = "mixed"
KINDS = (NONE, SAME, MIXED)


@dataclass(frozen=True)
class Event:
    id: str  # copies of one event on different calendars share an id
    calendar: str
    tag: str
    title: str
    start: datetime
    end: datetime
    all_day: bool
    status: str
    link: str = ""  # where the event opens in the browser


@dataclass(frozen=True)
class Overlap:
    first: Event
    second: Event
    start: datetime  # when both events are happening
    end: datetime


def overlaps(events: list[Event]) -> list[Overlap]:
    """One overlap per pair of colliding events, even when an event sits on two calendars."""
    seen = set()
    result = []
    for index, first in enumerate(events):
        for second in events[index + 1:]:
            pair = frozenset((first.id, second.id))
            if _conflict(first, second) and pair not in seen:
                seen.add(pair)
                result.append(Overlap(first, second, max(first.start, second.start), min(first.end, second.end)))
    return result


def classify(events: list[Event]) -> list[str]:
    """Return the kind of each event, in the same order as the input."""
    return [_kind_of(event, events) for event in events]


def _kind_of(event: Event, events: list[Event]) -> str:
    partners = [other for other in events if _conflict(event, other)]
    if any(partner.tag != event.tag for partner in partners):
        return MIXED
    if partners:
        return SAME
    return NONE


def _conflict(a: Event, b: Event) -> bool:
    return (
        _can_conflict(a)
        and _can_conflict(b)
        and a.id != b.id
        and a.start < b.end
        and b.start < a.end
    )


def _can_conflict(event: Event) -> bool:
    return not event.all_day and event.status in ACTIVE_STATUSES
