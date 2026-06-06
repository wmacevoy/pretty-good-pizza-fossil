# Roadmap

This document captures the ordered sequence of work to reach each milestone. The repo is currently between "design pinned" and "first build."

## Current state (2026-06-06)

**Pinned and ready:**
- Algorithm spec (sibling `../pretty-good-pizza` repo).
- Schemas: `manifest-schema.md`, `ballot-schema.md`, `canonical-json.md`, `deterministic-sampling.md`. All four are normative.
- Threat model: three trust modes; modes 1 (public) and 2 (group) fully specified; mode 3 deferred. `Status: Pinned`.
- Build skeleton: `build/build-fossil.sh` validates inputs, sources `versions.env`, dispatches build sequence. Bash-parses cleanly.
- Fossil revision: **version-2.28** (commit `1573b8e66e402f7d3f5cf70d37036a4ba2966edd`). Source layout (`src/sqlite3.c`, `src/sqlite3.h`, `src/db.c`, `configure`) and configure-flag spellings verified against this revision.
- SEE-reuse pattern: Fossil 2.28's existing scaffolding for the SQLite Encryption Extension (`db_maybe_obtain_encryption_key` in `src/db.c`, `*.efossil` filename convention) is reusable. Patch hook point identified.

**Done since the initial scaffold:**
- CLI runtime swapped from Tcl to QuickJS. `bin/ppv` is the entry; `lib/*.js` modules replace the Tcl equivalents. Rationale: JSON.parse + BigInt are native, dependency posture stays small (qjs + openssl + gpg), familiarity for the maintainer.
- `lib/canonical-json.js` implements RFC 8785 JCS for the restricted subset; passing regression against `test/fixtures/canonical-json/tiny.{json,canonical,sha3-256}`.
- `lib/sha3.js` and `lib/shell.js` shell out to `openssl` for SHA3-256 and SHAKE128.
- `lib/manifest.js`: `load`, `validate` (full schema), `canonicalHash` implemented.
- `lib/ballot.js`: `load`, `validate` (rules 1–5) implemented.
- `lib/tally.js`: `run` implemented for all three modes (A, B, C), including threshold filter, SHAKE128 stream, BigInt weight computation, and mode-C tie-breaking. Cross-implementation regression fixtures frozen in `test/fixtures/sampling/{mode-c-boundary-tie,mode-a-replacement,mode-b-no-replacement}/`.
- `build/build-fossil.sh` incorporates the SEE-reuse approach (`--with-see=1`, `src/sqlite3-see.c`); drops `--with-tcl` since the CLI is now standalone.
- Protocol abbreviation renamed `ppp` → `ppv` (avoids PGP collision); schema version is `"ppv/1"`.

**Stubbed or missing:**
- `bin/ppv` subcommands (`init`, `vote`, `tally`, `verify`) — print "not implemented (phase 1 stub)" and exit nonzero. The algorithm is in place; the CLI just needs wiring.
- `build/patches/fossil-db-key.patch` — not written. Design pinned in `docs/threat-model.md`.
- `versions.env` — LibreSSL, sqlcipher-libressl, and QuickJS versions still unpinned.

## Milestone 1: First custom Fossil binary

Goal: produce a `fossil-ppv` binary that links LibreSSL libssl + libcrypto + SQLCipher amalgamation, with the mode-aware `PRAGMA key` wiring in place. Verifying by `./fossil-ppv version` and opening a stock (mode-1, unencrypted) repo successfully.

Order matters — each step depends on the ones above:

1. **Pin LibreSSL version** in `build/versions.env`. Recommended: 4.2.1 (matches sqlcipher-libressl CI).
2. **Pin sqlcipher-libressl commit** in `build/versions.env`. Recommended: latest tagged release, or current `main` if no release tag.
3. **Pin QuickJS version** in `build/versions.env`. Used to run `bin/ppv`; not linked into Fossil.
4. **Write `build/patches/fossil-db-key.patch`**. Target: `db_maybe_obtain_encryption_key` in `src/db.c` (Fossil's existing SEE policy hook). Replace the prompt-or-cache body with:
   - Check `FOSSIL_PPV_KEY` env var first (escape hatch for CI/testing).
   - Otherwise shell out to `gpg --decrypt --output - <repo-dir>/keys/master.key.asc`.
   - Populate `*pKey`, let the existing caching machinery handle reuse, zeroize the local buffer.
   - Add a tiny `ppv_gpg_decrypt_master_key()` helper (either inline in `db.c` or in a new `src/ppv_keys.c` listed in `main.mk`).
5. **Install** LibreSSL and sqlcipher-libressl locally at the pinned versions.
6. **Run** `LIBRESSL_PREFIX=... SQLCIPHER_DIR=... FOSSIL_SRC=... ./build/build-fossil.sh`.
7. **Verify**: `./build/dist/fossil-ppv version` reports the expected build flags; opening a stock (mode-1) repo works.

## Milestone 2: First working tally

Goal: a JS tally implementation that runs against frozen fixtures and produces the expected output byte-for-byte. This validates the algorithm independent of Fossil.

**Algorithm + fixtures: done.** `lib/tally.js::run` covers modes A/B/C; three frozen fixtures in `test/fixtures/sampling/` pass. Mode C hand-verified; modes A/B locked to current implementation output (any future reimplementation must reproduce these byte-for-byte).

**Remaining:**

1. **Wire up `bin/ppv tally`**: load manifest + all ballots from a working directory (or a passed-in repo path), fetch the seed (NIST beacon URL or commit-reveal blob), call `tally.run`, write the result as `result.json`, return exit 0.
2. **Wire up `bin/ppv verify`**: re-run the tally from public inputs and compare to the committed `result.json`. Exit 0 if match, nonzero if not.
3. **Extend sampling fixtures** with edge cases as they come up (threshold modes other than `absolute`, tie_break = `random`/`alphabetic`, mode C with `M >= ranked.length`, etc.).

Milestones 1 and 2 are independent and can run in parallel.

## Milestone 3: First federated election

Goal: convener + voters run a real election end-to-end on the custom binary.

Depends on milestones 1 and 2.

1. **Implement `bin/ppv init`**: validate manifest, generate `K` via LibreSSL `RAND_bytes()` (mode 2 only), multi-recipient gpg-encrypt to roster as `keys/master.key.asc`, write `manifest.json`, commit to Fossil as the genesis check-in (clearsign engaged).
2. **Implement `bin/ppv vote`**: load manifest, prompt for approvals (or accept on command line), build ballot JSON, write to `ballots/<fingerprint>.json`, commit to Fossil (clearsign engaged).
3. **Implement convener init-time chooser** per `threat-model.md` (always-confirm, plus chooser when >1 roster fingerprint matches the convener's keyring).
4. **Implement voter first-open chooser** per `threat-model.md` (chooser only when >1 match; warn read-only when 0 matches).
5. **Scenario test**: 3 simulated voters in 3 directories, sync via a local Fossil server (or peer-to-peer over loopback), each runs `bin/ppv tally` independently, all three produce the same result.
6. **Write a quick-start in `README.md`**.

## Deferred

- **Phase 3 / Mode 3 (individual)**: per-voter SQLCipher keys, no key sharing. For when peers do not mutually trust. Out of v1 scope.
- **CI matrix mirroring sqlcipher-libressl's 5 platforms**: debian-glibc-x64, debian-glibc-arm64, alpine-musl-x64, macos-arm64, macos-x64. Adds reproducible builds and release artifacts. Worth doing after milestone 3 passes locally.
- **Equivocation detection at tally time**: voter committing two contradictory ballots. Default in threat-model is "reject voter entirely and surface for convener review" — needs to be specified concretely in `docs/` before tally code enforces it.
- **TH1 hooks for Fossil web UI**: rendering ballots, manifests, tally results in browser via Fossil's built-in TH1 templating. Useful but not required for the CLI flow.
- **Threat model coverage for live-machine compromise**: outside SQLCipher's scope; would need OS-level mitigations (filesystem permissions, sandboxing). Document as known limitation, do not chase.

## Out of scope for this implementation

- Secret-ballot elections (would require blind-signature or anonymous-token protocols layered on top — different design).
- Open-roster elections (Sybil attack surface; the closed-roster assumption is load-bearing).
- Election mutation (manifest is immutable; mode is genesis-locked; rosters frozen at genesis).
