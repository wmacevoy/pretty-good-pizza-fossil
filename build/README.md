# Custom Fossil build

This directory builds a Fossil binary with SQLCipher (encrypted storage), LibreSSL (TLS + libcrypto for SQLCipher), and full Tcl 8.6 linked in. The result is a single statically-linked executable with no runtime dependencies beyond libc.

## Status

**Skeleton.** `build-fossil.sh` validates inputs, sources pinned upstream versions from `versions.env`, and lays out the build sequence. Fossil is pinned to **version-2.28** (commit `1573b8e66e402f7d3f5cf70d37036a4ba2966edd` on the GitHub mirror, Fossil-native hash prefix `52445a27`, released 2026-03-11). Source-layout and configure-flag assumptions in the script are verified against this revision.

One step remains before the recipe is reproducible:

1. **`PRAGMA key` wiring** — write `build/patches/fossil-db-key.patch` against Fossil's `src/db.c` to be **mode-aware** per the manifest's `rule.privacy`: skip `PRAGMA key` for `"public"`, shell out to `gpg --decrypt --output - keys/master.key.asc` and pass `PRAGMA key = "x'<hex>'";` for `"group"`, reject `"individual"` with a clear error. Full design in `docs/threat-model.md` (Pinned).

LibreSSL, sqlcipher-libressl, and Tcl versions still need pinning in `versions.env`. Those are environment inputs to the script; pin them when ready.

## Worth investigating before writing the patch

Fossil 2.28 already exposes `--with-see=1` for the SQLite Encryption Extension (SEE — drh's commercial encryption add-on). That implies the source already has scaffolding for `PRAGMA key` / `PRAGMA rekey` and surrounding key-source plumbing along the SEE code paths. SQLCipher uses the same `PRAGMA key` API by design, so the SEE scaffolding may be largely reusable: the mode-aware patch could become an insertion into existing key-source code rather than a from-scratch wiring of `db_open`. Investigate the SEE code paths (`grep -r "PRAGMA key" src/`, `grep -r "with-see" src/`) before authoring the patch — if reusable, the patch shrinks substantially.

## Dependencies

| Dep | Source | Trust |
|---|---|---|
| LibreSSL (libcrypto + libssl) | upstream `libressl.org` | well-vetted; OpenBSD foundation |
| SQLCipher amalgamation | sibling `sqlcipher-libressl` | your fork; reviewable |
| Tcl 8.6 (static) | upstream `tcl.tk` | long-lived, slow-moving |
| zlib | system (or upstream static) | ubiquitous |
| Fossil source | upstream `fossil-scm.org` | small C codebase, auditable |

All dependencies are static-linkable. The final binary has no runtime dependency outside libc.

## Inputs (env)

| Variable | Required | Meaning |
|---|---|---|
| `LIBRESSL_PREFIX` | yes | LibreSSL install prefix (contains `include/`, `lib/libcrypto.a`, `lib/libssl.a`) |
| `SQLCIPHER_DIR` | yes | Path to a `sqlcipher-libressl` checkout |
| `TCL_PREFIX` | yes | Tcl 8.6 install prefix (contains `include/tcl.h`, `lib/libtcl8.6.a`) |
| `FOSSIL_SRC` | yes | Path to a Fossil source checkout |
| `FOSSIL_REF` | no | Expected git ref of `FOSSIL_SRC`; verified if set |
| `OUTPUT_DIR` | no | Default `build/dist` |
| `ZLIB_PREFIX` | no | Static zlib prefix (default: system zlib) |
| `JOBS` | no | `make -j` parallelism (default: detected) |

## Pinning the recipe

When the three TODOs are resolved, this directory should also contain:

- `versions.env` — pinned versions/commits for LibreSSL, sqlcipher-libressl, Tcl, and Fossil. Sourced by the script so a reproducible build is one `source build/versions.env && ./build/build-fossil.sh` away.
- `patches/fossil-db-key.patch` — the small Fossil-side patch wiring `PRAGMA key`.
- `patches/fossil-configure.patch` — only if Fossil's autosetup needs surgery to accept the SQLCipher amalgamation in place of vanilla SQLite. May not be needed.

Cross-implementation reproducibility (matching the `sqlcipher-libressl` model) implies a CI matrix building this on the same 5 platforms. That's phase-2-of-phase-2; do it after the local build works.

## Why this collapses phase 2 and phase 3

The original phase plan (in `CLAUDE.md`) separated:

- Phase 2: custom Fossil with full Tcl linked in.
- Phase 3: SQLCipher swap-in.

In practice the heavy lift is the LibreSSL ↔ SQLCipher integration, which `sqlcipher-libressl` has already solved. Once you're building a custom Fossil at all, adding the SQLCipher amalgamation in step 2 of the recipe is a few extra compile flags, not a separate phase. Doing both at once forfeits no optionality and saves a second build pipeline.

The threat-model document for at-rest encryption (key source, lifecycle, recovery) is still required before phase-2-combined ships — but it's a doc, not a separate build effort.
