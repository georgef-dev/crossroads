import json

import pytest

from crossroads.config import Account, Calendar, ConfigError, load


def write(tmp_path, data):
    path = tmp_path / "config.json"
    path.write_text(json.dumps(data) if not isinstance(data, str) else data)
    return path


def test_loads_accounts_and_tags(tmp_path):
    path = write(tmp_path, {
        "google": [{"account": "me@gmail.com", "mail": True,
                    "calendars": [{"id": "primary", "tag": "personal"},
                                  {"id": "me@work.com", "tag": "work", "name": "Work"}]}],
        "icloud": [{"account": "me@icloud.com",
                    "calendars": [{"id": "/1/calendars/home/", "tag": "personal"}]}],
    })

    assert load(path) == [
        Account("google", "me@gmail.com", True,
                (Calendar("primary", "personal"), Calendar("me@work.com", "work", "Work"))),
        Account("icloud", "me@icloud.com", False, (Calendar("/1/calendars/home/", "personal"),)),
    ]


@pytest.mark.parametrize(
    ("data", "message"),
    [
        ({"google": [{"account": "a", "calendars": [{"id": "primary"}]}]}, "needs a tag"),
        ({"google": [{"account": "a", "calendars": [{"id": "primary", "tag": "family"}]}]}, "needs a tag"),
        ({"google": [{"account": "a", "calendars": [{"id": "x", "tag": "work"},
                                                    {"id": "x", "tag": "personal"}]}]}, "tagged once"),
        ({"google": [{"calendars": []}]}, "missing its account"),
        ({"google": [{"account": "a", "calendars": [{"tag": "work"}]}]}, "missing its id"),
        ({"icloud": [{"account": "a", "mail": True}]}, "only read from Gmail"),
        ({"outlook": []}, "unknown providers"),
        ({"google": [{"account": "a", "calendars": [{"id": "x", "tag": "work", "name": 3}]}]}, "isn't text"),
        ("{not json", "not valid JSON"),
    ],
)
def test_rejects_invalid_config(tmp_path, data, message):
    with pytest.raises(ConfigError, match=message):
        load(write(tmp_path, data))


def test_missing_file(tmp_path):
    with pytest.raises(ConfigError, match="no config"):
        load(tmp_path / "missing.json")
