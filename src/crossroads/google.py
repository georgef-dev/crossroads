"""Google Calendar and Gmail, read-only, through one OAuth desktop client on a personal account."""

import base64
import hashlib
import http.server
import json
import urllib.parse
import webbrowser
from dataclasses import dataclass
from datetime import date, datetime, time
from secrets import token_urlsafe

import requests

from crossroads import secrets
from crossroads.config import Calendar
from crossroads.conflicts import Event

SCOPES = [
    "https://www.googleapis.com/auth/calendar.readonly",
    "https://www.googleapis.com/auth/gmail.metadata",
]
CALENDAR_API = "https://www.googleapis.com/calendar/v3"
GMAIL_API = "https://gmail.googleapis.com/gmail/v1/users/me"
TIMEOUT = 20
MAX_PAGES = 4
MAIL_LIMIT = 25
# A calendar shared as free/busy only returns events without a title.
BUSY = "Busy"
CALENDAR_WEB = "https://calendar.google.com/calendar/r/day"
GMAIL_WEB = "https://mail.google.com/mail/"


class GoogleError(Exception):
    pass


@dataclass(frozen=True)
class Mail:
    account: str
    sender: str
    subject: str
    received: datetime
    link: str


# Mapping: pure, so it can be tested against recorded API responses.


def event_from_google(item: dict, calendar: Calendar, account: str) -> Event | None:
    if item.get("status") == "cancelled":
        return None

    all_day = "date" in item["start"]
    start = _when(item["start"])
    instance = item.get("originalStartTime", item["start"])
    return Event(
        id=f"{item.get('iCalUID') or item['id']}@{instance.get('dateTime') or instance.get('date')}",
        calendar=calendar.id,
        tag=calendar.tag,
        title=item.get("summary") or BUSY,
        start=start,
        end=_when(item["end"]),
        all_day=all_day,
        status=_status(item),
        # Free/busy events may have no link of their own; their day still opens.
        link=item.get("htmlLink") or f"{CALENDAR_WEB}/{start:%Y/%m/%d}?authuser={urllib.parse.quote(account)}",
    )


def mail_from_gmail(account: str, message: dict) -> Mail:
    headers = {header["name"].lower(): header["value"] for header in message["payload"].get("headers", [])}
    return Mail(
        account=account,
        sender=headers.get("from", ""),
        subject=headers.get("subject", ""),
        received=datetime.fromtimestamp(int(message["internalDate"]) / 1000).astimezone(),
        link=f"{GMAIL_WEB}?authuser={urllib.parse.quote(account)}#all/{message['threadId']}",
    )


def _when(value: dict) -> datetime:
    if "dateTime" in value:
        return datetime.fromisoformat(value["dateTime"])
    # All-day dates start at local midnight, with the offset that applies on that date.
    return datetime.combine(date.fromisoformat(value["date"]), time()).astimezone()


def _status(item: dict) -> str:
    me = next((attendee for attendee in item.get("attendees", []) if attendee.get("self")), None)
    response = me.get("responseStatus") if me else None
    if response == "declined":
        return "declined"
    if response == "tentative" or item.get("status") == "tentative":
        return "tentative"
    return "accepted"


# Fetching.


def fetch_events(account: str, calendar: Calendar, start: datetime, end: datetime) -> list[Event]:
    url = f"{CALENDAR_API}/calendars/{urllib.parse.quote(calendar.id, safe='')}/events"
    params = {
        "timeMin": start.isoformat(),
        "timeMax": end.isoformat(),
        "singleEvents": "true",
        "orderBy": "startTime",
        "maxResults": 250,
    }
    events = []
    for item in _pages(account, url, params, "items"):
        event = event_from_google(item, calendar, account)
        if event:
            events.append(event)
    return events


def fetch_unread(account: str) -> list[Mail]:
    token = _access_token(account)
    listing = _get(token, f"{GMAIL_API}/messages",
                   {"labelIds": ["INBOX", "UNREAD"], "maxResults": MAIL_LIMIT})
    params = {"format": "metadata", "metadataHeaders": ["From", "Subject"]}
    return [
        mail_from_gmail(account, _get(token, f"{GMAIL_API}/messages/{message['id']}", params))
        for message in listing.get("messages", [])[:MAIL_LIMIT]
    ]


def list_calendars(account: str) -> list[dict]:
    return list(_pages(account, f"{CALENDAR_API}/users/me/calendarList", {}, "items"))


def _pages(account: str, url: str, params: dict, key: str):
    token = _access_token(account)
    for _ in range(MAX_PAGES):
        page = _get(token, url, params)
        yield from page.get(key, [])
        if "nextPageToken" not in page:
            return
        params = {**params, "pageToken": page["nextPageToken"]}


def _get(token: str, url: str, params: dict) -> dict:
    response = requests.get(url, params=params, headers={"Authorization": f"Bearer {token}"}, timeout=TIMEOUT)
    if not response.ok:
        raise GoogleError(f"{response.status_code} from {urllib.parse.urlsplit(url).path}: {response.text[:200]}")
    return response.json()


# OAuth.


def save_client(client_file: str) -> None:
    client = json.loads(open(client_file).read())["installed"]
    secrets.put(secrets.GOOGLE_CLIENT, "default", json.dumps(client))


def _client() -> dict:
    stored = secrets.get(secrets.GOOGLE_CLIENT, "default")
    if not stored:
        raise GoogleError("no Google OAuth client; run: crossroads auth google-client <client_secret.json>")
    return json.loads(stored)


def _access_token(account: str) -> str:
    refresh_token = secrets.get(secrets.GOOGLE_TOKEN, account)
    if not refresh_token:
        raise GoogleError(f"{account} is not signed in; run: crossroads auth google {account}")
    client = _client()
    response = requests.post(client["token_uri"], timeout=TIMEOUT, data={
        "client_id": client["client_id"],
        "client_secret": client["client_secret"],
        "refresh_token": refresh_token,
        "grant_type": "refresh_token",
    })
    if not response.ok:
        raise GoogleError(f"could not refresh {account}: {response.text[:200]}")
    return response.json()["access_token"]


def sign_in(account: str) -> None:
    """Run the loopback consent flow in the browser and keep the refresh token."""
    client = _client()
    verifier = token_urlsafe(64)
    state = token_urlsafe(16)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()

    received = {}

    class Callback(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            received.update(urllib.parse.parse_qsl(urllib.parse.urlsplit(self.path).query))
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"Crossroads is signed in. You can close this tab.")

        def log_message(self, *args):
            pass

    server = http.server.HTTPServer(("127.0.0.1", 0), Callback)
    redirect_uri = f"http://127.0.0.1:{server.server_port}"
    url = client["auth_uri"] + "?" + urllib.parse.urlencode({
        "client_id": client["client_id"],
        "redirect_uri": redirect_uri,
        "response_type": "code",
        "scope": " ".join(SCOPES),
        "access_type": "offline",
        "prompt": "consent",
        "login_hint": account,
        "state": state,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
    })
    print(f"Opening the browser to sign in {account}. If it doesn't open, visit:\n{url}")
    webbrowser.open(url)
    while "code" not in received and "error" not in received:
        server.handle_request()
    server.server_close()

    if received.get("state") != state or "code" not in received:
        raise GoogleError(f"sign-in failed: {received.get('error', 'state mismatch')}")

    response = requests.post(client["token_uri"], timeout=TIMEOUT, data={
        "client_id": client["client_id"],
        "client_secret": client["client_secret"],
        "code": received["code"],
        "code_verifier": verifier,
        "redirect_uri": redirect_uri,
        "grant_type": "authorization_code",
    })
    if not response.ok:
        raise GoogleError(f"could not finish sign-in: {response.text[:200]}")
    tokens = response.json()

    # Guard against signing in with a different account than the one asked for.
    profile = requests.get(f"{GMAIL_API}/profile", timeout=TIMEOUT,
                           headers={"Authorization": f"Bearer {tokens['access_token']}"})
    signed_in = profile.json().get("emailAddress", "") if profile.ok else ""
    if signed_in.lower() != account.lower():
        raise GoogleError(f"signed in as {signed_in or 'an unknown account'}, expected {account}")

    secrets.put(secrets.GOOGLE_TOKEN, account, tokens["refresh_token"])
