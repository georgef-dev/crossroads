"""Every calendar each configured account can see, with its current tag, for the settings view."""

from omaview import google, icloud
from omaview.config import Account


def list_for(provider: str, account: str) -> list[tuple[str, str]]:
    """(id, name) of the calendars an account can see."""
    if provider == "google":
        return [(c["id"], c.get("summary", c["id"])) for c in google.list_calendars(account)]
    return icloud.list_calendars(account)


def listing(accounts: list[Account], list_calendars=list_for) -> list[dict]:
    result = []
    for account in accounts:
        configured = {c.id: c for c in account.calendars}
        error = ""
        try:
            visible = list_calendars(account.provider, account.account)
        except Exception as failure:  # one account failing must not hide the others
            visible, error = [], str(failure) or type(failure).__name__

        calendars = [
            {"id": id, "name": configured[id].name if id in configured and configured[id].name else name,
             "tag": configured[id].tag if id in configured else "off"}
            for id, name in visible
        ]
        # Keep tagged calendars the account didn't list, so they can still be turned off.
        seen = {id for id, _ in visible}
        calendars += [
            {"id": c.id, "name": c.name or c.id, "tag": c.tag}
            for c in account.calendars if c.id not in seen
        ]
        result.append({"provider": account.provider, "account": account.account, "mail": account.mail,
                       "error": error, "calendars": calendars})
    return result
