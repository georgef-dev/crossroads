"""Property-based tests derived from the invariants in specs/ConflictFlags.tla.

The properties are restated from the spec's English lines with their own
helpers, so they don't share the logic under test.
"""

from datetime import datetime, timedelta, timezone

from hypothesis import given
from hypothesis import strategies as st

from crossroads.conflicts import KINDS, MIXED, NONE, PERSONAL, STATUSES, WORK, Event, classify, overlaps

BASE = datetime(2026, 11, 17, 8, tzinfo=timezone.utc)
SLOT = timedelta(minutes=30)
CALENDARS = [("family", PERSONAL), ("kids", PERSONAL), ("work", WORK)]


@st.composite
def event_lists(draw):
    """Small event lists where copies of one event share their time, as in the spec."""
    shapes = {}
    for event_id in ["e1", "e2", "e3", "e4"]:
        start = draw(st.integers(0, 6))
        length = draw(st.integers(1, 4))
        all_day = draw(st.booleans())
        shapes[event_id] = (BASE + start * SLOT, BASE + (start + length) * SLOT, all_day)

    occurrences = draw(
        st.lists(
            st.tuples(st.sampled_from(sorted(shapes)), st.sampled_from(CALENDARS)),
            max_size=6,
            unique=True,
        )
    )
    events = []
    for event_id, (calendar, tag) in occurrences:
        start, end, all_day = shapes[event_id]
        status = draw(st.sampled_from(STATUSES))
        events.append(Event(event_id, calendar, tag, event_id, start, end, all_day, status))
    return events


def active(event):
    return event.status in ("accepted", "tentative")


def real_overlap(a, b):
    return (
        a.id != b.id
        and not a.all_day
        and not b.all_day
        and active(a)
        and active(b)
        and a.start < b.end
        and b.start < a.end
    )


@given(event_lists())
def test_ConflictFlags_TypeOK(events):
    """Every event in the view has one of the three kinds."""
    kinds = classify(events)
    assert len(kinds) == len(events)
    assert all(kind in KINDS for kind in kinds)


@given(event_lists())
def test_ConflictFlags_AllDayNeverFlagged(events):
    """All-day events are never flagged."""
    for event, kind in zip(events, classify(events)):
        if event.all_day:
            assert kind == NONE


@given(event_lists())
def test_ConflictFlags_InactiveNeverFlagged(events):
    """Declined and cancelled events are never flagged; tentative ones can be."""
    for event, kind in zip(events, classify(events)):
        if not active(event):
            assert kind == NONE


@given(event_lists())
def test_ConflictFlags_OverlapsAreFlagged(events):
    """Any two timed events that overlap are both flagged, whatever their calendars."""
    kinds = classify(events)
    for i, a in enumerate(events):
        for j, b in enumerate(events):
            if real_overlap(a, b):
                assert kinds[i] != NONE and kinds[j] != NONE


@given(event_lists())
def test_ConflictFlags_FlagsNeedRealOverlap(events):
    """An event is flagged only for a real overlap: touching ends and its own copies don't count."""
    for event, kind in zip(events, classify(events)):
        if kind != NONE:
            assert any(real_overlap(event, other) for other in events)


@given(event_lists())
def test_ConflictFlags_CrossTagShowsMixed(events):
    """An event that overlaps one with the other tag shows as personal + work."""
    for event, kind in zip(events, classify(events)):
        if any(real_overlap(event, other) and other.tag != event.tag for other in events):
            assert kind == MIXED


@given(event_lists())
def test_ConflictFlags_CardsAreRealOverlaps(events):
    """Every overlap card shows two different events that really overlap."""
    for card in overlaps(events):
        assert real_overlap(card.first, card.second)


@given(event_lists())
def test_ConflictFlags_OneCardPerOverlap(events):
    """Every real overlap between two events gets exactly one card, even when one of them sits on two calendars."""
    cards = overlaps(events)
    for a in events:
        for b in events:
            if real_overlap(a, b):
                matching = [c for c in cards if {c.first.id, c.second.id} == {a.id, b.id}]
                assert len(matching) == 1


@given(event_lists())
def test_ConflictFlags_CardWindowIsTheOverlap(events):
    """A card's window is the time when both events are happening."""
    for card in overlaps(events):
        later_start = card.first.start if card.first.start > card.second.start else card.second.start
        earlier_end = card.first.end if card.first.end < card.second.end else card.second.end
        assert (card.start, card.end) == (later_start, earlier_end)


@given(event_lists())
def test_ConflictFlags_MixedNeedsCrossTag(events):
    """An event shows as personal + work only when it overlaps one with the other tag."""
    for event, kind in zip(events, classify(events)):
        if kind == MIXED:
            assert any(real_overlap(event, other) and other.tag != event.tag for other in events)
