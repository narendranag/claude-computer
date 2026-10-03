# __NAME__

<!-- /new-client replaces this stub. Keep it short: who the client is, what the engagement is, where things are. -->

**Client:** _who they are, in one line_
**Engagement:** _what you are doing for them, and until when_
**Contact:** _name and role — never an email address or phone number in a repo_

## Where things are

- `brief/` — everything the client gave you: decks, documents, data, the original ask. Tracked in git, never edited; a newer version is a new file.
- This folder's root — your own work: notes, analysis, `PLAN.md`, drafts.
- Code built for them — its own repo inside this folder (`new-app <type> <name> --dir ~/clients/__NAME__`), ignored by this repo.
- Tasks: `TASKS.md`. Decisions: `DECISIONS.md` when there are any.
- System and fleet: `~/claude-computer/docs/`.

## Rules

- This repo is private and stays private: `security-check` fails if it is public.
- Never commit a credential the client shares with you. It goes in Bitwarden (`claude-computer/client-__NAME__-*`).
