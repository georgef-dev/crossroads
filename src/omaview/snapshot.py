"""One JSON-ready snapshot of every source, with each event's kind."""

from datetime import datetime, time, timedelta

from omaview import google, icloud
from omaview.config import Account
from omaview.conflicts import MIXED, SAME, classify, overlaps

DAYS = 15  # today plus the 14 days the panel can show
MAX_EVENTS = 500
MAX_TEXT = 200
MAX_LINK = 1000

FETCH_EVENTS = {"google": google.fetch_events, "icloud": icloud.fetch_events}


def build(accounts: list[Account], now: datetime, fetch_events=FETCH_EVENTS, fetch_mail=google.fetch_unread) -> dict:
    start = datetime.combine(now.date(), time()).astimezone()
    end = start + timedelta(days=DAYS)
    events, mail, errors = [], [], []
    names = {c.id: c.name or c.id for account in accounts for c in account.calendars}

    for account in accounts:
        for calendar in account.calendars:
            try:
                events += fetch_events[account.provider](account.account, calendar, start, end)
            except Exception as error:  # one broken source must not hide the others
                errors.append(_error(f"{account.account} {calendar.id}", error))
        if account.mail:
            try:
                mail += fetch_mail(account.account)
            except Exception as error:
                errors.append(_error(f"{account.account} mail", error))

    # Kinds are computed over every fetched event, before the list is capped.
    classified = sorted(zip(events, classify(events)), key=lambda pair: pair[0].start)[:MAX_EVENTS]
    cards = sorted(overlaps(events), key=lambda card: card.start)[:MAX_EVENTS]
    return {
        "fetchedAt": now.isoformat(),
        "events": [_event(event, kind, names) for event, kind in classified],
        "overlaps": [_card(card, names) for card in cards],
        "mail": [_mail(item) for item in sorted(mail, key=lambda item: item.received, reverse=True)],
        "errors": errors,
    }


def failed(now: datetime, source: str, error: Exception) -> dict:
    return {"fetchedAt": now.isoformat(), "events": [], "overlaps": [], "mail": [], "errors": [_error(source, error)]}


def _event(event, kind: str, names: dict) -> dict:
    return {
        "id": _text(event.id),
        "calendar": _text(event.calendar),
        "calendarName": _text(names.get(event.calendar, event.calendar)),
        "tag": event.tag,
        "title": _text(event.title),
        "start": event.start.isoformat(),
        "end": event.end.isoformat(),
        "allDay": event.all_day,
        "status": event.status,
        "kind": kind,
        "link": _link(event.link),
    }


def _card(card, names: dict) -> dict:
    kind = MIXED if card.first.tag != card.second.tag else SAME
    return {
        "start": card.start.isoformat(),
        "end": card.end.isoformat(),
        "kind": kind,
        "events": [_event(card.first, kind, names), _event(card.second, kind, names)],
    }


def _mail(item) -> dict:
    return {
        "account": _text(item.account),
        "sender": _text(item.sender),
        "subject": _text(item.subject),
        "received": item.received.isoformat(),
        "link": _link(item.link),
    }


def _error(source: str, error: Exception) -> dict:
    return {"source": _text(source), "message": _text(str(error) or type(error).__name__)}


def _text(value: str) -> str:
    return value[:MAX_TEXT]


def _link(value: str) -> str:
    # A cut link would open the wrong page, so an oversized one is dropped.
    return value if len(value) <= MAX_LINK else ""
