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

**Stubbed or missing:**
- `lib/manifest.tcl`, `lib/ballot.tcl`, `lib/tally.tcl` — all procs error with "not implemented."
- `bin/ppp` subcommands (`init`, `vote`, `tally`, `verify`) — all print "not implemented (phase 1 stub)" and exit nonzero.
- `build/patches/fossil-db-key.patch` — not written.
- `build/build-fossil.sh` — does not yet incorporate the SEE-reuse approach (`--with-see=1`, copy SQLCipher amalgamation to `src/sqlite3-see.c`).
- `versions.env` — LibreSSL, sqlcipher-libressl, and Tcl versions still unpinned.
- Test fixtures: `test/fixtures/canonical-json/` and `test/fixtures/sampling/` do not exist; only the placeholder `test/fixtures/example-grant/` is in place.

## Milestone 1: First custom Fossil binary

Goal: produce a `fossil-ppp` binary that links LibreSSL libssl + libcrypto + Tcl 8.6 + SQLCipher amalgamation, with the mode-aware `PRAGMA key` wiring in place. Verifying by `./fossil-ppp version` and opening a stock (mode-1, unencrypted) repo successfully.

Order matters — each step depends on the ones above:

1. **Pin LibreSSL version** in `build/versions.env`. Recommended: 4.2.1 (matches sqlcipher-libressl CI).
2. **Pin sqlcipher-libressl commit** in `build/versions.env`. Recommended: latest tagged release, or current `main` if no release tag.
3. **Pin Tcl version** in `build/versions.env`. Recommended: latest stable 8.6.x from tcl.tk.
4. **Update `build/build-fossil.sh`** to incorporate SEE-reuse:
   - Pass `--with-see=1` to Fossil's configure.
   - Copy SQLCipher amalgamation to `src/sqlite3-see.c` (not `src/sqlite3.c`) because `--with-see=1` sets `SQLITE3_ORIGIN 1`, which expects the SEE filename.
   - Keep `-DSQLCIPHER_CRYPTO_OPENSSL` in CFLAGS (SQLCipher-specific; `SQLITE_HAS_CODEC` arrives automatically via `config.h` when `USE_SEE` is set).
5. **Write `build/patches/fossil-db-key.patch`**. Target: `db_maybe_obtain_encryption_key` in `src/db.c`. Replace the prompt-or-cache body with:
   - Check `FOSSIL_PPP_KEY` env var first (escape hatch for CI/testing).
   - Otherwise shell out to `gpg --decrypt --output - <repo-dir>/keys/master.key.asc`.
   - Populate `*pKey`, let the existing caching machinery handle reuse, zeroize the local buffer.
   - Add a tiny `ppp_gpg_decrypt_master_key()` helper (either inline in `db.c` or in a new `src/ppp_keys.c` listed in `main.mk`).
6. **Install** LibreSSL, Tcl, and sqlcipher-libressl locally at the pinned versions.
7. **Run** `LIBRESSL_PREFIX=... SQLCIPHER_DIR=... TCL_PREFIX=... FOSSIL_SRC=... ./build/build-fossil.sh`.
8. **Verify**: `./build/dist/fossil-ppp version` reports the expected build flags; opening a stock (mode-1) repo works.

## Milestone 2: First working tally

Goal: a Tcl tally implementation that runs against frozen fixtures and produces the expected output byte-for-byte. This validates the algorithm independent of Fossil.

1. **Implement** `lib/manifest.tcl::canonical_hash` per `docs/canonical-json.md` (RFC 8785 JCS subset → SHA3-256). Use `tcllib`'s `sha3` module.
2. **Freeze** `test/fixtures/canonical-json/tiny.expected` — the hex digest of the worked example in `docs/canonical-json.md`. This is the cross-implementation regression fixture.
3. **Implement** `lib/tally.tcl::run` per `docs/deterministic-sampling.md` (SHAKE128 stream domain-separated by manifest_hash, integer weights via product-of-other-prices, per-draw byte budget for ≤ 2^-128 bias).
4. **Freeze** `test/fixtures/sampling/<mode>.expected` for modes A, B, C — frozen `(seed, manifest, ballots)` triples and the expected outputs.
5. **Implement** `lib/manifest.tcl::load`, `lib/manifest.tcl::validate`, `lib/ballot.tcl::load`, `lib/ballot.tcl::validate` (validity rules 1–5 from `docs/ballot-schema.md`).
6. **Wire up** `bin/ppp tally` and `bin/ppp verify` against the fixtures.
7. **Round-trip**: `bin/ppp tally <fixture-dir>` matches the committed expected output; `bin/ppp verify` against the same input exits 0.

Milestones 1 and 2 are independent and can run in parallel.

## Milestone 3: First federated election

Goal: convener + voters run a real election end-to-end on the custom binary.

Depends on milestones 1 and 2.

1. **Implement `bin/ppp init`**: validate manifest, generate `K` via LibreSSL `RAND_bytes()` (mode 2 only), multi-recipient gpg-encrypt to roster as `keys/master.key.asc`, write `manifest.json`, commit to Fossil as the genesis check-in (clearsign engaged).
2. **Implement `bin/ppp vote`**: load manifest, prompt for approvals (or accept on command line), build ballot JSON, write to `ballots/<fingerprint>.json`, commit to Fossil (clearsign engaged).
3. **Implement convener init-time chooser** per `threat-model.md` (always-confirm, plus chooser when >1 roster fingerprint matches the convener's keyring).
4. **Implement voter first-open chooser** per `threat-model.md` (chooser only when >1 match; warn read-only when 0 matches).
5. **Scenario test**: 3 simulated voters in 3 directories, sync via a local Fossil server (or peer-to-peer over loopback), each runs `bin/ppp tally` independently, all three produce the same result.
6. **Write a quick-start in `README.md`**.

## Deferred

- **Phase 3 / Mode 3 (individual)**: per-voter SQLCipher keys, no key sharing. For when peers do not mutually trust. Out of v1 scope.
- **CI matrix mirroring sqlcipher-libressl's 5 platforms**: debian-glibc-x64, debian-glibc-arm64, alpine-musl-x64, macos-arm64, macos-x64. Adds reproducible builds and release artifacts. Worth doing after milestone 3 passes locally.
- **Equivocation detection at tally time**: voter committing two contradictory ballots. Default in threat-model is "reject voter entirely and surface for convener review" — needs to be specified concretely in `docs/` before tally code enforces it.
- **TH1/Tcl hooks for Fossil web UI**: rendering ballots, manifests, tally results in browser. Useful but not required for the CLI flow.
- **Threat model coverage for live-machine compromise**: outside SQLCipher's scope; would need OS-level mitigations (filesystem permissions, sandboxing). Document as known limitation, do not chase.

## Out of scope for this implementation

- Secret-ballot elections (would require blind-signature or anonymous-token protocols layered on top — different design).
- Open-roster elections (Sybil attack surface; the closed-roster assumption is load-bearing).
- Election mutation (manifest is immutable; mode is genesis-locked; rosters frozen at genesis).
