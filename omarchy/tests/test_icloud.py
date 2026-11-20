"""Parsing of iCloud CalDAV responses and calendar data, in the shapes iCloud returns."""

from datetime import datetime, timedelta, timezone

from crossroads.config import Calendar
from crossroads.icloud import calendar_data, calendars_in, events_from_ics, href_of

FAMILY = Calendar("/123/calendars/home/", "personal")
ME = "me@icloud.com"
WEEK_START = datetime(2026, 11, 16, tzinfo=timezone.utc)
WEEK_END = WEEK_START + timedelta(days=7)


def ics(*events: str) -> str:
    return "\r\n".join([
        "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Apple Inc.//iCloud//EN",
        "BEGIN:VTIMEZONE", "TZID:America/New_York",
        "BEGIN:STANDARD", "DTSTART:20071104T020000", "RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU",
        "TZOFFSETFROM:-0400", "TZOFFSETTO:-0500", "TZNAME:EST", "END:STANDARD",
        "END:VTIMEZONE",
        *events,
        "END:VCALENDAR",
    ]) + "\r\n"


def vevent(*lines: str) -> str:
    return "\r\n".join(["BEGIN:VEVENT", "DTSTAMP:20261101T000000Z", *lines, "END:VEVENT"])


def test_weekly_pickup_expands_into_instances_with_their_own_ids():
    events = events_from_ics(ics(vevent(
        "UID:pickup", "SUMMARY:Kids pickup",
        "DTSTART;TZID=America/New_York:20261102T150000",
        "DTEND;TZID=America/New_York:20261102T153000",
        "RRULE:FREQ=WEEKLY;BYDAY=MO,WE",
    )), FAMILY, ME, WEEK_START, WEEK_END)

    assert [e.start.astimezone(timezone.utc) for e in events] == [
        datetime(2026, 11, 16, 20, tzinfo=timezone.utc),
        datetime(2026, 11, 18, 20, tzinfo=timezone.utc),
    ]
    assert len({e.id for e in events}) == 2
    assert all((e.title, e.tag, e.status, e.all_day) == ("Kids pickup", "personal", "accepted", False) for e in events)
    assert all(e.end - e.start == timedelta(minutes=30) for e in events)
    assert all(e.link == "https://www.icloud.com/calendar/" for e in events)


def test_all_day_event():
    [event] = events_from_ics(ics(vevent(
        "UID:bday", "SUMMARY:Birthday", "DTSTART;VALUE=DATE:20261117", "DTEND;VALUE=DATE:20261118",
    )), FAMILY, ME, WEEK_START, WEEK_END)

    assert event.all_day
    assert (event.start.hour, event.start.utcoffset() is not None) == (0, True)


def test_statuses():
    def status(*lines):
        [event] = events_from_ics(ics(vevent(
            "UID:x", "DTSTART:20261117T090000Z", "DTEND:20261117T100000Z", *lines,
        )), FAMILY, ME, WEEK_START, WEEK_END)
        return event.status

    assert status("STATUS:CANCELLED") == "cancelled"
    assert status("STATUS:TENTATIVE") == "tentative"
    assert status("ATTENDEE;PARTSTAT=DECLINED:mailto:me@icloud.com") == "declined"
    assert status("ATTENDEE;PARTSTAT=TENTATIVE:mailto:ME@icloud.com") == "tentative"
    assert status("ATTENDEE;PARTSTAT=DECLINED:mailto:other@icloud.com",
                  "ATTENDEE;PARTSTAT=ACCEPTED:mailto:me@icloud.com") == "accepted"
    assert status() == "accepted"


def test_event_without_dtend_uses_its_duration():
    [event] = events_from_ics(ics(vevent(
        "UID:x", "DTSTART:20261117T090000Z", "DURATION:PT45M",
    )), FAMILY, ME, WEEK_START, WEEK_END)

    assert event.end - event.start == timedelta(minutes=45)


MULTISTATUS = """<?xml version="1.0" encoding="UTF-8"?>
<multistatus xmlns="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <response>
    <href>/123/calendars/</href>
    <propstat><prop><resourcetype><collection/></resourcetype></prop></propstat>
  </response>
  <response>
    <href>/123/calendars/home/</href>
    <propstat><prop>
      <displayname>Family</displayname>
      <resourcetype><collection/><C:calendar/></resourcetype>
      <C:supported-calendar-component-set><C:comp name="VEVENT"/></C:supported-calendar-component-set>
    </prop></propstat>
  </response>
  <response>
    <href>/123/calendars/tasks/</href>
    <propstat><prop>
      <displayname>Reminders</displayname>
      <resourcetype><collection/><C:calendar/></resourcetype>
      <C:supported-calendar-component-set><C:comp name="VTODO"/></C:supported-calendar-component-set>
    </prop></propstat>
  </response>
</multistatus>"""


def test_calendars_in_home_skips_non_event_collections():
    assert calendars_in(MULTISTATUS) == [("/123/calendars/home/", "Family")]


def test_principal_and_home_hrefs():
    principal = """<multistatus xmlns="DAV:"><response><href>/</href><propstat><prop>
      <current-user-principal><href>/123/principal/</href></current-user-principal>
    </prop></propstat></response></multistatus>"""
    home = """<multistatus xmlns="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav"><response><href>/123/principal/</href>
      <propstat><prop><C:calendar-home-set><href>https://p42-caldav.icloud.com:443/123/calendars/</href></C:calendar-home-set>
    </prop></propstat></response></multistatus>"""

    assert href_of(principal, "d:current-user-principal") == "/123/principal/"
    assert href_of(home, "c:calendar-home-set") == "https://p42-caldav.icloud.com:443/123/calendars/"


def test_calendar_data_from_report():
    report = """<multistatus xmlns="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
      <response><href>/123/calendars/home/a.ics</href><propstat><prop>
        <C:calendar-data>BEGIN:VCALENDAR
END:VCALENDAR</C:calendar-data></prop></propstat></response>
    </multistatus>"""

    assert calendar_data(report) == ["BEGIN:VCALENDAR\nEND:VCALENDAR"]
