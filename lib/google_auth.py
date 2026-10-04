"""OAuth for the gcal / gmail / gdrive wrappers.

One OAuth client (Desktop app) and one token shared by all three wrappers, both in the
secrets store (docs/SECRETS.md):
  google.credentials   the downloaded credentials.json
  google.token         the authorised token (written by the first run)

Nothing is written to disk. First run opens a browser for consent (the human does this).

The access token lasts an hour, so it is refreshed in memory on each run and never stored:
writing it back would commit the store once an hour on every machine, and every machine's
commit would conflict with the others'. The token is written back (through `secrets set`,
which commits) only when Google issues a new refresh token, and after the first consent.
"""

from __future__ import annotations

import json

import cc

# What one sign-in grants. Changing this list makes the next run ask for consent again
# (credentials() notices the stored token lacks a scope). each scope is annotated with what needs it.
_G = "https://www.googleapis.com/auth/"
SCOPES = [
    _G + "gmail.modify",            # read, send, draft, label, archive; not permanent delete
    _G + "calendar.events",
    _G + "drive",
    _G + "documents",
    _G + "spreadsheets",
    _G + "presentations",
    _G + "contacts",                # People API
    _G + "chat.messages",           # Google Chat (Workspace accounts only, Google says)
    _G + "chat.spaces.readonly",
    _G + "meetings.space.created",  # Meet: create spaces, read their conferences
    _G + "meetings.space.readonly",
    _G + "analytics.readonly",      # Analytics Data API (reports)
    _G + "analytics.edit",          # Analytics Admin: create properties and data streams
    _G + "tagmanager.readonly",
    _G + "tagmanager.edit.containers",         # containers, workspaces, tags, triggers
    _G + "tagmanager.edit.containerversions",  # create versions
    _G + "tagmanager.publish",                 # make a version live (always asked about first)
]


def credentials():
    from google.auth.transport.requests import Request
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow

    creds = None
    try:
        info = json.loads(cc.secret("google", "token"))
        # A token granted before SCOPES grew would refresh fine and then fail with 403s: ask again.
        if set(SCOPES) <= set(info.get("scopes") or []):
            creds = Credentials.from_authorized_user_info(info, SCOPES)
    except cc.CCError as e:
        if e.code != cc.EX_CONFIG:
            raise

    if creds and creds.valid:
        return creds
    if creds and creds.expired and creds.refresh_token:
        before = creds.refresh_token
        creds.refresh(Request())
        if creds.refresh_token and creds.refresh_token != before:
            cc.set_secret("google", "token", creds.to_json())
        return creds
    client = json.loads(cc.secret("google", "credentials"))
    flow = InstalledAppFlow.from_client_config(client, SCOPES)
    creds = flow.run_local_server(port=0, open_browser=True)
    cc.set_secret("google", "token", creds.to_json())
    return creds


def service(name: str, version: str):
    from googleapiclient.discovery import build

    return build(name, version, credentials=credentials(), cache_discovery=False)
