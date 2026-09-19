# resources — family key documents brain

One folder per person: passports, IDs, tax, insurance, wills, certificates. **Sensitive.** Never a git repo, never in the vault, never in plain object storage.

System context: `~/claude-computer/docs/`.

## Layout

```
resources/
  <person>/
    <person>_<doctype>_<YYYY-MM-DD>.pdf    searchable PDF (OCR'd)
    INDEX.md                                one row per document, with expiry dates
  TASKS.md                                  renewals live here
```

## Jobs

1. **File an incoming scan**: OCR with `ocrmypdf --skip-text in.pdf out.pdf`; read only enough to identify person, document type, issue and expiry dates; rename `<person>_<doctype>_<date>.pdf`; add the row to that person's `INDEX.md`.
2. **Expiry tracking**: for any expiry within 6 months, add `- [ ] Renew <doc> for <person> 📅 <expiry minus lead time>` to `TASKS.md` (passports: 6 months ahead).
3. **Sync**: `resources-sync` (two-way, encrypted with rclone crypt). Runs from the session-start hook and hourly. First run or after an interruption: `resources-sync --resync --dry-run`, show me, then `--resync --yes`.

## Rules

- Never copy document contents into any other file, note, message, or commit. The vault may carry an expiry summary (person, document type, expiry date) — nothing more.
- Never send these files anywhere except the encrypted remote. Sharing a document with someone is my action, not yours.
- Ask before deleting or replacing any document.
