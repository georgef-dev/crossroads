"""Credentials in the desktop keyring (gnome-keyring), through secret-tool."""

import subprocess

GOOGLE_CLIENT = "google-client"  # the OAuth client JSON, stored under account "default"
GOOGLE_TOKEN = "google-token"  # one refresh token per Google account
ICLOUD_PASSWORD = "icloud-password"  # one app-specific password per Apple ID


def get(kind: str, account: str) -> str | None:
    result = subprocess.run(
        ["secret-tool", "lookup", "service", "crossroads", "kind", kind, "account", account],
        capture_output=True,
        text=True,
    )
    return result.stdout if result.returncode == 0 and result.stdout else None


def put(kind: str, account: str, value: str) -> None:
    # The secret goes through stdin so it never appears in the process list.
    subprocess.run(
        ["secret-tool", "store", f"--label=Crossroads {kind} {account}",
         "service", "crossroads", "kind", kind, "account", account],
        input=value,
        text=True,
        check=True,
    )
