"""iCloud calendars over CalDAV, read-only, with an app-specific password."""

import urllib.parse
import xml.etree.ElementTree as ElementTree
from datetime import date, datetime, time, timedelta, timezone

import icalendar
import recurring_ical_events
import requests

from crossroads import secrets
from crossroads.config import Calendar
from crossroads.conflicts import Event

SERVER = "https://caldav.icloud.com/"
# iCloud has no per-event web links, so events open the calendar web app.
CALENDAR_WEB = "https://www.icloud.com/calendar/"
TIMEOUT = 20
NAMESPACES = {"d": "DAV:", "c": "urn:ietf:params:xml:ns:caldav"}


class ICloudError(Exception):
    pass


# Parsing: pure, so it can be tested against recorded responses.


def href_of(multistatus: str, prop: str) -> str:
    """The href inside a single property, like current-user-principal or calendar-home-set."""
    href = ElementTree.fromstring(multistatus).find(f".//{prop}/d:href", NAMESPACES)
    if href is None or not href.text:
        raise ICloudError(f"no {prop} in the server response")
    return href.text.strip()


def calendars_in(multistatus: str) -> list[tuple[str, str]]:
    """(href, name) of every event calendar in a calendar home."""
    calendars = []
    for response in ElementTree.fromstring(multistatus).findall("d:response", NAMESPACES):
        prop = response.find("d:propstat/d:prop", NAMESPACES)
        if prop is None or prop.find("d:resourcetype/c:calendar", NAMESPACES) is None:
            continue
        components = [c.get("name") for c in prop.findall("c:supported-calendar-component-set/c:comp", NAMESPACES)]
        if components and "VEVENT" not in components:
            continue
        name = prop.findtext("d:displayname", "", NAMESPACES).strip()
        calendars.append((response.findtext("d:href", "", NAMESPACES).strip(), name))
    return calendars


def calendar_data(multistatus: str) -> list[str]:
    root = ElementTree.fromstring(multistatus)
    return [data.text for data in root.iterfind(".//c:calendar-data", NAMESPACES) if data.text]


def events_from_ics(ics: str, calendar: Calendar, account: str, start: datetime, end: datetime) -> list[Event]:
    parsed = icalendar.Calendar.from_ical(ics)
    return [_event(component, calendar, account) for component in recurring_ical_events.of(parsed).between(start, end)]


def _event(component, calendar: Calendar, account: str) -> Event:
    start = component.decoded("DTSTART")
    all_day = not isinstance(start, datetime)
    end = _end(component, start)
    instance = component.get("RECURRENCE-ID") or component.get("DTSTART")
    return Event(
        id=f"{component.get('UID')}@{instance.to_ical().decode()}",
        calendar=calendar.id,
        tag=calendar.tag,
        title=str(component.get("SUMMARY", "")),
        start=_local(start),
        end=_local(end),
        all_day=all_day,
        status=_status(component, account),
        link=CALENDAR_WEB,
    )


def _end(component, start):
    if "DTEND" in component:
        return component.decoded("DTEND")
    if "DURATION" in component:
        return start + component.decoded("DURATION")
    return start + timedelta(days=1) if not isinstance(start, datetime) else start


def _local(value: date | datetime) -> datetime:
    if not isinstance(value, datetime):
        value = datetime.combine(value, time())
    # Dates and floating times are wall-clock times in the local timezone.
    return value if value.tzinfo else value.astimezone()


def _status(component, account: str) -> str:
    status = str(component.get("STATUS", "")).upper()
    if status == "CANCELLED":
        return "cancelled"
    attendees = component.get("ATTENDEE", [])
    attendees = attendees if isinstance(attendees, list) else [attendees]
    mine = next((a for a in attendees if str(a).lower() == f"mailto:{account.lower()}"), None)
    response = str(mine.params.get("PARTSTAT", "")).upper() if mine is not None else ""
    if response == "DECLINED":
        return "declined"
    if response == "TENTATIVE" or status == "TENTATIVE":
        return "tentative"
    return "accepted"


# Fetching.


def fetch_events(account: str, calendar: Calendar, start: datetime, end: datetime) -> list[Event]:
    home = _calendar_home(account)
    body = f"""<?xml version="1.0" encoding="utf-8"?>
<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><c:calendar-data/></d:prop>
  <c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT">
    <c:time-range start="{_utc(start)}" end="{_utc(end)}"/>
  </c:comp-filter></c:comp-filter></c:filter>
</c:calendar-query>"""
    response = _request(account, "REPORT", urllib.parse.urljoin(home, calendar.id), body, depth="1")
    return [event for ics in calendar_data(response) for event in events_from_ics(ics, calendar, account, start, end)]


def list_calendars(account: str) -> list[tuple[str, str]]:
    body = """<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><d:displayname/><d:resourcetype/><c:supported-calendar-component-set/></d:prop>
</d:propfind>"""
    return calendars_in(_request(account, "PROPFIND", _calendar_home(account), body, depth="1"))


def save_password(account: str, password: str) -> None:
    secrets.put(secrets.ICLOUD_PASSWORD, account, password)


def _calendar_home(account: str) -> str:
    principal = href_of(_propfind(account, SERVER, "<d:current-user-principal/>"), "d:current-user-principal")
    principal_url = urllib.parse.urljoin(SERVER, principal)
    home = href_of(_propfind(account, principal_url, "<c:calendar-home-set/>"), "c:calendar-home-set")
    return urllib.parse.urljoin(principal_url, home)


def _propfind(account: str, url: str, prop: str) -> str:
    body = f"""<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop>{prop}</d:prop></d:propfind>"""
    return _request(account, "PROPFIND", url, body, depth="0")


def _request(account: str, method: str, url: str, body: str, depth: str) -> str:
    password = secrets.get(secrets.ICLOUD_PASSWORD, account)
    if not password:
        raise ICloudError(f"{account} is not signed in; run: crossroads auth icloud {account}")
    if urllib.parse.urlsplit(url).scheme != "https" or not urllib.parse.urlsplit(url).hostname.endswith(".icloud.com"):
        raise ICloudError(f"refusing to send credentials to {url}")
    response = requests.request(
        method, url, data=body.encode(), auth=(account, password), timeout=TIMEOUT,
        headers={"Depth": depth, "Content-Type": "application/xml; charset=utf-8"},
    )
    if response.status_code != 207:
        raise ICloudError(f"{response.status_code} from iCloud {method}")
    return response.text


def _utc(value: datetime) -> str:
    return value.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
