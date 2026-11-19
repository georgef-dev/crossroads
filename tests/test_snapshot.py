from datetime import datetime, timedelta, timezone

from omaview import snapshot
from omaview.config import Account, Calendar
from omaview.conflicts import Event
from omaview.google import Mail

NOW = datetime(2026, 11, 17, 7, tzinfo=timezone.utc)
FAMILY = Calendar("primary", "personal")
WORK = Calendar("me@work.com", "work", "Work")
ACCOUNT = Account("google", "me@gmail.com", True, (FAMILY, WORK))


def event(id, calendar, hour, minutes=60, title=None, link=""):
    start = NOW.replace(hour=hour)
    return Event(id, calendar.id, calendar.tag, title or id, start, start + timedelta(minutes=minutes), False, "accepted", link)


def no_mail(account):
    return []


def build(calendars, fetch_mail=no_mail, account=ACCOUNT):
    def fetch(account, calendar, start, end):
        source = calendars[calendar.id]
        if isinstance(source, Exception):
            raise source
        return source

    return snapshot.build([account], NOW, {"google": fetch}, fetch_mail)


def kinds(result):
    return {event["id"]: event["kind"] for event in result["events"]}


def test_ConflictFlags_ViewCatchesUp_kinds_follow_the_current_events():
    """After any calendar change, the view eventually catches up."""
    pickup = event("pickup", FAMILY, 15, 30)

    before = build({"primary": [pickup], "me@work.com": [event("busy", WORK, 15)]})
    after = build({"primary": [pickup], "me@work.com": [event("busy", WORK, 16)]})

    assert kinds(before) == {"pickup": "mixed", "busy": "mixed"}
    assert kinds(after) == {"pickup": "none", "busy": "none"}


def test_a_failing_source_does_not_hide_the_others():
    result = build({"primary": [event("pickup", FAMILY, 15)], "me@work.com": RuntimeError("403 from Google")})

    assert kinds(result) == {"pickup": "none"}
    assert result["errors"] == [{"source": "me@gmail.com me@work.com", "message": "403 from Google"}]


def test_mail_failure_is_reported():
    def broken(account):
        raise RuntimeError("token expired")

    result = build({"primary": [], "me@work.com": []}, fetch_mail=broken)

    assert result["errors"] == [{"source": "me@gmail.com mail", "message": "token expired"}]


def test_snapshot_shape_and_order():
    received = datetime(2026, 11, 17, 6, tzinfo=timezone.utc)

    def mail(account):
        return [Mail(account, "a@x.com", "older", received - timedelta(hours=1), "https://mail.google.com/a"),
                Mail(account, "b@x.com", "newer", received, "https://mail.google.com/b")]

    result = build({"primary": [event("late", FAMILY, 18), event("early", FAMILY, 9)], "me@work.com": []}, mail)

    assert result["fetchedAt"] == NOW.isoformat()
    assert [e["id"] for e in result["events"]] == ["early", "late"]
    assert result["events"][0] == {
        "id": "early", "calendar": "primary", "calendarName": "primary", "tag": "personal", "title": "early",
        "start": NOW.replace(hour=9).isoformat(), "end": NOW.replace(hour=10).isoformat(),
        "allDay": False, "status": "accepted", "kind": "none", "link": "",
    }
    assert [m["subject"] for m in result["mail"]] == ["newer", "older"]
    assert result["mail"][0]["link"] == "https://mail.google.com/b"


def test_window_starts_at_local_midnight_and_spans_fifteen_days():
    seen = []

    def fetch(account, calendar, start, end):
        seen.append((start, end))
        return []

    snapshot.build([Account("google", "me@gmail.com", False, (FAMILY,))], NOW, {"google": fetch}, no_mail)

    [(start, end)] = seen
    assert (start.hour, start.minute, start.utcoffset() is not None) == (0, 0, True)
    assert end - start == timedelta(days=15)


def test_untrusted_text_is_bounded():
    result = build({"primary": [event("x", FAMILY, 9, title="<b>" + "a" * 500)], "me@work.com": []})

    assert len(result["events"][0]["title"]) == snapshot.MAX_TEXT


def test_events_are_capped_after_kinds_are_computed():
    many = [event(f"e{i}", FAMILY, 9) for i in range(snapshot.MAX_EVENTS + 1)]

    result = build({"primary": many, "me@work.com": []})

    assert len(result["events"]) == snapshot.MAX_EVENTS
    assert all(e["kind"] == "same" for e in result["events"])


def test_overlap_cards_carry_both_events_and_their_shared_window():
    result = build({"primary": [event("pickup", FAMILY, 15, 30, link="https://www.icloud.com/calendar/")],
                    "me@work.com": [event("busy", WORK, 15)]})

    [card] = result["overlaps"]
    assert (card["start"], card["end"]) == (NOW.replace(hour=15).isoformat(), NOW.replace(hour=15, minute=30).isoformat())
    assert card["kind"] == "mixed"
    assert sorted(e["id"] for e in card["events"]) == ["busy", "pickup"]
    assert all(e["kind"] == "mixed" for e in card["events"])
    assert sorted(e["calendarName"] for e in card["events"]) == ["Work", "primary"]


def test_same_tag_cards_are_same_kind():
    result = build({"primary": [event("a", FAMILY, 9), event("b", FAMILY, 9, 30)], "me@work.com": []})

    assert [card["kind"] for card in result["overlaps"]] == ["same"]


def test_oversized_links_are_dropped_not_cut():
    result = build({"primary": [event("x", FAMILY, 9, link="https://www.google.com/" + "a" * 2000)], "me@work.com": []})

    assert result["events"][0]["link"] == ""
