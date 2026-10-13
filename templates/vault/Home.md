---
type: map
created: 2026-10-13
---
# Home

`$= dv.paragraph("[[daily/" + moment().format("YYYY-MM-DD") + "|Today's note]] · [[maps/tasks|Tasks]] · inbox: " + dv.pages('"inbox"').where(p => p.file.name != "quick").length + " captures, " + dv.pages('"inbox/transcripts"').where(p => p.status == "unprocessed").length + " transcripts waiting")`

Two layers: **`notes/` and `daily/` are yours**; **`memory/` is Claude's** graph of people, orgs, meetings, decisions, commitments and projects, every fact cited from `sources/`. The night shift files the inbox at 04:30 and reports under *Overnight* in the daily note. The rules: `CLAUDE.md`.

## Open commitments

```dataview
TABLE WITHOUT ID file.link AS "Commitment", row["from"] AS "From", row["to"] AS "To", due AS "Due", made_in AS "Made in"
FROM "memory/commitments"
WHERE status = "open"
SORT choice(row["from"].me, 0, 1) ASC, due ASC
```

## Recent meetings

```dataview
TABLE WITHOUT ID file.link AS "Meeting", date AS "Date", length(attendees) AS "People"
FROM "memory/meetings"
SORT date DESC
LIMIT 8
```

## People, most recent first

```dataview
TABLE WITHOUT ID file.link AS "Person", relationship AS "Relationship", last_contact AS "Last contact"
FROM "memory/people"
WHERE last_contact
SORT last_contact DESC
LIMIT 12
```

## Active projects

```dataview
TABLE WITHOUT ID file.link AS "Project", repo AS "Repo", local AS "Checkout"
FROM "memory/projects"
WHERE status = "active"
SORT file.name ASC
```

## Decisions

```dataview
TABLE WITHOUT ID file.link AS "Decision", date AS "Date", status AS "Status"
FROM "memory/decisions"
SORT date DESC
LIMIT 6
```

## Your latest notes

```dataview
LIST
FROM "notes"
SORT file.mtime DESC
LIMIT 10
```

## Lately filed

```dataview
TABLE WITHOUT ID file.link AS "Source", kind AS "Kind", created AS "Filed"
FROM "sources"
WHERE !generated AND kind != "transcript"
SORT created DESC
LIMIT 10
```
