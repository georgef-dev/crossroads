"""`omaview calendars --json`: every calendar each configured account can see, with its tag."""

from omaview.calendars import listing
from omaview.config import Account, Calendar

GOOGLE = Account("google", "you@example.com", True, (Calendar("you@example.com", "personal", "Mine"),))
ICLOUD = Account("icloud", "me@icloud.com", False, (Calendar("/1/home/", "personal", "George"),))


def fake_lists(google=None, icloud=None):
    def list_for(provider, account):
        result = {"google": google, "icloud": icloud}[provider]
        if isinstance(result, Exception):
            raise result
        return result
    return list_for


def test_lists_every_visible_calendar_with_its_tag():
    result = listing([GOOGLE, ICLOUD], fake_lists(
        google=[("you@example.com", "you@example.com"), ("holidays", "Holidays")],
        icloud=[("/1/home/", "George"), ("/1/family/", "Family")],
    ))

    assert result == [
        {"provider": "google", "account": "you@example.com", "mail": True, "error": "", "calendars": [
            {"id": "you@example.com", "name": "Mine", "tag": "personal"},
            {"id": "holidays", "name": "Holidays", "tag": "off"},
        ]},
        {"provider": "icloud", "account": "me@icloud.com", "mail": False, "error": "", "calendars": [
            {"id": "/1/home/", "name": "George", "tag": "personal"},
            {"id": "/1/family/", "name": "Family", "tag": "off"},
        ]},
    ]


def test_a_failing_account_still_shows_its_configured_calendars():
    result = listing([ICLOUD], fake_lists(icloud=RuntimeError("401 from iCloud PROPFIND")))

    assert result == [{"provider": "icloud", "account": "me@icloud.com", "mail": False,
                       "error": "401 from iCloud PROPFIND",
                       "calendars": [{"id": "/1/home/", "name": "George", "tag": "personal"}]}]


def test_configured_calendars_the_account_no_longer_sees_are_kept():
    result = listing([ICLOUD], fake_lists(icloud=[("/1/family/", "Family")]))

    assert [c["id"] for c in result[0]["calendars"]] == ["/1/family/", "/1/home/"]
