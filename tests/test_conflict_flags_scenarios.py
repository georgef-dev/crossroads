"""Gherkin scenarios for specs/ConflictFlags.tla, tagged by property."""

from datetime import datetime, time, timezone

from pytest_bdd import given, scenarios, then, when

from omaview.conflicts import Event, classify, overlaps

scenarios("conflict_flags.feature")

DAY = datetime(2026, 11, 17, tzinfo=timezone.utc).date()


def at(clock: str) -> datetime:
    return datetime.combine(DAY, time.fromisoformat(clock), tzinfo=timezone.utc)


def rows(datatable):
    header, *body = datatable
    return [dict(zip(header, row)) for row in body]


@given("these events:", target_fixture="events")
def these_events(datatable):
    return [
        Event(
            id=row["id"],
            calendar=row["calendar"],
            tag=row["tag"],
            title=row["id"],
            start=at(row["start"]),
            end=at(row["end"]),
            all_day=row["all_day"] == "yes",
            status=row["status"],
        )
        for row in rows(datatable)
    ]


@when("Omaview classifies them", target_fixture="kinds")
def classify_them(events):
    return {(event.id, event.calendar): kind for event, kind in zip(events, classify(events))}


@then("the kinds are:")
def the_kinds_are(kinds, datatable):
    expected = {(row["id"], row["calendar"]): row["kind"] for row in rows(datatable)}
    assert kinds == expected


@when("Omaview builds the overlap cards", target_fixture="cards")
def build_cards(events):
    # A list, not a dict, so a duplicate card for the same pair shows up.
    return sorted(
        ("+".join(sorted({card.first.id, card.second.id})), card.start, card.end)
        for card in overlaps(events)
    )


@then("the overlap cards are:")
def the_cards_are(cards, datatable):
    assert cards == sorted((row["ids"], at(row["start"]), at(row["end"])) for row in rows(datatable))


@then("there are no overlap cards")
def no_cards(cards):
    assert cards == []
