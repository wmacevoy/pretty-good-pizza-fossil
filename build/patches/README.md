# Fossil source patches

Small patches applied to the upstream Fossil source tree during the build. Each patch should be self-contained, attributed to a specific Fossil revision (`FOSSIL_REF`), and small enough to read in one sitting.

## Expected patches

- `fossil-db-key.patch` — wires `PRAGMA key = '<key>'` into Fossil's `db_open` path so SQLCipher unlocks the database after `sqlite3_open_v2`. Key source (env var, prompt, keyfile) is determined by `docs/threat-model.md`. **Not yet written.**
- `fossil-configure.patch` — only if Fossil's autosetup needs surgery to accept the SQLCipher amalgamation in place of vanilla SQLite. Probably not needed; the bundled amalgamation is referenced by a fixed path that the build script overwrites.

## Conventions

- One patch per concern. Don't bundle unrelated edits.
- The first line of each patch's commit-message-style header names the Fossil revision it applies to.
- Patches are unified diffs (`diff -u` or `git diff` output), applied with `patch -p1` from the Fossil source root.
