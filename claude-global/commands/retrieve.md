---
description: Find something in the R2 archive and restore it
argument-hint: "<what you are looking for>"
---

Find and restore: $ARGUMENTS

1. Search the index: `~/claude-computer/bin/archive-pull --search "<term>"`, trying a few terms (names, years, extensions). If `INDEX.md` looks stale, `archive-pull --reindex` first.
2. Show me the candidates (path, size, date). Ask which one if more than one matches.
3. Ask where it should go (default `~/archive/<path>`; a project goes to `~/projects/`). Restores never overwrite.
4. `archive-pull <path> [dest]`. Report the local path. R2 keeps its copy; nothing else changes.
