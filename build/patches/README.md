# Fossil source patches

Small patches applied to the upstream Fossil source tree during the build. Each patch is self-contained, attributed to a specific Fossil revision (`FOSSIL_REF` in `../versions.env`), and small enough to read in one sitting.

## Patches in this directory

- **`fossil-db-key.patch`** — wires the mode-aware key source into Fossil's existing SEE scaffolding (`db_maybe_obtain_encryption_key` in `src/db.c`). Adds a new static helper `ppv_decrypt_master_key()` that shells out to `gpg --decrypt --output - <repo-dir>/keys/master.key.asc`. Key-source priority:
  1. `FOSSIL_PPV_KEY` env var (escape hatch, documented as testing-only).
  2. gpg-decrypted `keys/master.key.asc`.
  3. Stock Fossil prompt, only if `FOSSIL_PPV_STOCK_PROMPT=1` is set (compatibility escape hatch).
  Fails fast with a descriptive `fossil_fatal()` message if none of the above produces a key. Target revision: `FOSSIL_REF` in `versions.env`.

## Conventions

- One patch per concern. Don't bundle unrelated edits.
- Patches are unified diffs (`diff -u` or `git diff` output), applied with `patch -p1` from the Fossil source root.
- Verify against the pinned `FOSSIL_REF` before treating a patch as ready.
