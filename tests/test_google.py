"""Mapping of Google Calendar and Gmail responses, in the shapes the APIs return."""

from datetime import datetime, timedelta, timezone

from crossroads.config import Calendar
from crossroads.google import BUSY, event_from_google, mail_from_gmail

ME = "you@example.com"

FAMILY = Calendar("primary", "personal")
WORK = Calendar("me@work.com", "work")


def timed(start, end, **fields):
    return {"id": "abc", "status": "confirmed",
            "start": {"dateTime": start}, "end": {"dateTime": end}, **fields}


def test_timed_event():
    event = event_from_google(
        timed("2026-11-17T15:00:00-05:00", "2026-11-17T15:30:00-05:00",
              iCalUID="pickup@google.com", summary="Kids pickup",
              htmlLink="https://www.google.com/calendar/event?eid=abc"),
        FAMILY, ME,
    )

    assert event.id == "pickup@google.com@2026-11-17T15:00:00-05:00"
    assert (event.calendar, event.tag, event.title) == ("primary", "personal", "Kids pickup")
    assert event.start == datetime(2026, 11, 17, 15, tzinfo=timezone(timedelta(hours=-5)))
    assert event.end - event.start == timedelta(minutes=30)
    assert (event.all_day, event.status) == (False, "accepted")
    assert event.link == "https://www.google.com/calendar/event?eid=abc"


def test_all_day_event_starts_at_local_midnight():
    event = event_from_google(
        {"id": "b", "status": "confirmed", "start": {"date": "2026-11-17"}, "end": {"date": "2026-11-18"}},
        FAMILY, ME,
    )

    assert event.all_day
    assert event.start.utcoffset() is not None
    assert (event.start.hour, event.start.minute) == (0, 0)
    assert event.end.date().isoformat() == "2026-11-18"


def test_cancelled_events_are_skipped():
    assert event_from_google(
        timed("2026-11-17T09:00:00Z", "2026-11-17T10:00:00Z", status="cancelled"), FAMILY, ME
    ) is None


def test_my_response_sets_the_status():
    def with_response(response):
        attendees = [{"email": "other@x.com", "responseStatus": "accepted"},
                     {"email": "me@gmail.com", "self": True, "responseStatus": response}]
        return event_from_google(timed("2026-11-17T09:00:00Z", "2026-11-17T10:00:00Z", attendees=attendees), FAMILY, ME)

    assert with_response("declined").status == "declined"
    assert with_response("tentative").status == "tentative"
    assert with_response("accepted").status == "accepted"
    assert with_response("needsAction").status == "accepted"


def test_recurring_instances_get_their_own_ids():
    def instance(day):
        return event_from_google(
            timed(f"2026-11-{day}T09:00:00Z", f"2026-11-{day}T10:00:00Z", iCalUID="standup@google.com",
                  recurringEventId="r1", originalStartTime={"dateTime": f"2026-11-{day}T09:00:00Z"}),
            WORK, ME,
        )

    assert instance(17).id != instance(18).id


def test_free_busy_events_show_as_separate_busy_blocks():
    # A calendar shared as free/busy only: no title, no iCalUID.
    first = event_from_google({"id": "x1", "start": {"dateTime": "2026-11-17T09:00:00Z"},
                               "end": {"dateTime": "2026-11-17T10:00:00Z"}}, WORK, ME)
    second = event_from_google({"id": "x2", "start": {"dateTime": "2026-11-17T10:00:00Z"},
                                "end": {"dateTime": "2026-11-17T11:00:00Z"}}, WORK, ME)

    assert (first.title, second.title) == (BUSY, BUSY)
    assert (first.tag, second.tag) == ("work", "work")
    assert first.id != second.id
    assert first.end == second.start
    # No link of their own, so they open their day in the shared calendar.
    assert first.link == "https://calendar.google.com/calendar/r/day/2026/11/17?authuser=you%40example.com"


def test_unread_mail():
    mail = mail_from_gmail("me@gmail.com", {
        "id": "m1",
        "threadId": "t1",
        "internalDate": "1794942000000",
        "payload": {"headers": [{"name": "From", "value": "School <office@school.org>"},
                                {"name": "Subject", "value": "Early pickup Friday"}]},
    })

    assert (mail.account, mail.sender, mail.subject) == ("me@gmail.com", "School <office@school.org>", "Early pickup Friday")
    assert mail.received == datetime.fromtimestamp(1794942000, timezone.utc)
    assert mail.link == "https://mail.google.com/mail/?authuser=me%40gmail.com#all/t1"
