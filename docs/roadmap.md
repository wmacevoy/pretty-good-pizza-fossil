# Roadmap

This document captures the ordered sequence of work to reach each milestone. The repo is currently between "design pinned" and "first build."

## Current state (2026-06-06)

**Pinned and ready:**
- Algorithm spec (sibling `../pizza-party-vote` repo).
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
- `bin/ppv tally [dir]` writes `result.json`; `bin/ppv verify [dir]` re-runs and diffs. Round-trip end-to-end tested.
- `bin/ppv init <manifest.json> [target-dir]` validates the manifest, resolves the convener's gpg key (always-confirm + chooser per threat-model), generates a 256-bit master key K via `openssl rand`, multi-recipient gpg-encrypts to the roster as `keys/master.key.asc` for group mode, copies the manifest in, and creates `ballots/`. For mode public with `fossil` on PATH, **auto-invokes** `fossil init` / `open` / `setting clearsign on` / `add manifest.json` / `ci`. Mode group deliberately stays manual (the `.efossil` repo file must be created by the patched `fossil-ppv`, not stock fossil, because SQLCipher cannot retroactively encrypt a plaintext DB). Refuses `rule.privacy="individual"` with a clear error.
- `bin/ppv vote <option-id> ...` validates approvals against the manifest, resolves the voter's gpg key from the local keyring (chooser when >1 match per threat-model first-open UX), builds the ballot JSON with the correct `manifest_hash`, writes `ballots/<fingerprint>.json`. With `fossil` on PATH, **auto-invokes** `fossil add` / `ci` to commit the ballot (clearsign engaged). Falls back to printed manual instructions when fossil is unavailable.
- `lib/gpg.js` wraps `gpg --list-secret-keys --with-colons` and multi-recipient `--encrypt --armor` for both subcommands.
- `build/build-fossil.sh` incorporates the SEE-reuse approach (`--with-see=1`, `src/sqlite3-see.c`); drops `--with-tcl` since the CLI is now standalone.
- `build/patches/fossil-db-key.patch` written: mode-aware key source (`FOSSIL_PPV_KEY` env var > gpg-decrypt `keys/master.key.asc` > stock prompt under `FOSSIL_PPV_STOCK_PROMPT=1`). Verified to apply cleanly against pinned Fossil 2.28; full compile awaits LibreSSL install.
- Protocol abbreviation renamed `ppp` → `ppv` (avoids PGP collision); schema version is `"ppv/1"`.

**Stubbed or missing:**
- QuickJS version pin in `versions.env` (LibreSSL and sqlcipher-libressl pins done).

## Milestone 1: First custom Fossil binary

Goal: produce a `fossil-ppv` binary that links LibreSSL libssl + libcrypto + SQLCipher amalgamation, with the mode-aware `PRAGMA key` wiring in place. Verifying by `./fossil-ppv version` and opening a stock (mode-1, unencrypted) repo successfully.

**Patch written and verified to apply.** `build/patches/fossil-db-key.patch` (~136 lines) adds `ppv_decrypt_master_key()` as a static helper near Fossil's existing SEE scaffolding and replaces the body of `db_maybe_obtain_encryption_key`'s `else` branch with the mode-aware key source. Applies cleanly against the pinned Fossil 2.28 source; syntax-check passes on the patched region.

What still gates running the build:

1. **Pin LibreSSL version** in `build/versions.env`. Recommended: 4.2.1 (matches sqlcipher-libressl CI).
2. **Pin sqlcipher-libressl commit** in `build/versions.env`. Recommended: latest tagged release, or current `main` if no release tag.
3. **Pin QuickJS version** in `build/versions.env`. Used to run `bin/ppv`; not linked into Fossil.
4. **Install** LibreSSL and sqlcipher-libressl locally at the pinned versions.
5. **Run** `LIBRESSL_PREFIX=... SQLCIPHER_DIR=... FOSSIL_SRC=... ./build/build-fossil.sh`.
6. **Verify**: `./build/dist/fossil-ppv version` reports the expected build flags; opening a stock (mode-1) repo works.

## Milestone 2: First working tally — DONE

Algorithm, fixtures, and CLI wiring all in place. `bin/ppv tally <dir>` writes `result.json`; `bin/ppv verify <dir>` re-runs and exits 0 on match, nonzero on tampering. Tests cover all three modes plus CLI round-trip.

Phase 1 caveat that's worth knowing about: the seed currently comes from a `seed.hex` file in the working directory. The two protocols pinned in the manifest schema (NIST beacon, commit-reveal) are not yet implemented — fetching the beacon pulse at the declared timestamp, or aggregating commit-reveal shares from the repo, are next-up work but not blocking the tally itself.

Future polish (deferred, not blocking):
- NIST beacon fetcher + commit-reveal aggregator for seed source.
- Sampling fixtures for `threshold.type = fraction|top-k`, `tie_break = random|alphabetic`, mode C with `M >= ranked.length`.

Milestones 1 and 3 remain.

## Milestone 3: First federated election — DONE

`bin/ppv init` and `vote` implemented, including the convener-init-confirm and first-open chooser UX from `threat-model.md`. `test/scenario-test.sh` exercises the full end-to-end story: three ephemeral GPG identities, each in their own workspace, mode-public election, three ballots cast independently, three independent `ppv tally` runs producing byte-identical results, three independent `ppv verify` runs passing.

The federation property — anyone with the same public inputs (manifest + ballots + seed) can independently re-run tally and verify a result — is demonstrated and regression-tested.

Remaining polish (deferred):

- Mode-2 (group, SQLCipher-encrypted) version of the scenario test, exercising the full custom Fossil binary's PRAGMA-key flow. The unit-level proof that mode-2 works was the build-time smoke test (`.efossil` files have opaque random headers); a multi-voter scenario would be the next confirmation.
- HTTP/HTTPS sync between distinct Fossil servers (instead of `.fossil` file copy as the federation substrate). Fossil's sync protocol is upstream's concern; the scenario test uses file copy to keep the test self-contained.

## Milestone 4: Eliminate the openssl runtime dep — DONE

`build/build-qjs.sh` produces `qjs-ppv`, a custom QuickJS binary with a `ppv-crypto` native module linked against the LibreSSL libcrypto that `build-fossil.sh` already builds. `lib/sha3.js` now does `import { sha3_256, shake128 } from "ppv-crypto"` instead of shelling out to `openssl`. SHA3-256 and `RAND_bytes` come from LibreSSL EVP/RAND; SHAKE128 is implemented in `src/ppv-keccak.c` because LibreSSL has no SHAKE primitive at any level (empirically confirmed, byte-verified against OpenSSL on rate-boundary cases). `bin/ppv` and `test/run-tests.js` shebangs switched to `#!/usr/bin/env qjs-ppv`.

Result: the runtime dependency footprint is just `fossil-ppv` + `qjs-ppv` + `gpg`. No `openssl` install, no stock `qjs`, no Tcl, no Python.

## Milestone 5: CI matrix + first tagged release — DONE

`.github/workflows/build-test.yml` builds + tests both binaries on every push across `linux-glibc-x86_64`, `linux-glibc-arm64`, `macos-arm64`. `.github/workflows/release.yml` does the same for `v*` tags and produces draft GitHub Releases with `ppv-<tag>-<platform>.tar.gz` artifacts + a `git archive` source tarball + `SHA256SUMS` (operator signs locally with PGP before publishing). First tag: **v0.1.0**.

Skipped for v0.1.0: `macos-x86_64` (GitHub-hosted Intel macOS runners no longer schedule reliably) and `alpine-musl` (deferred).

## Deferred

- **ppv homeserver** (federated Pi Zero 2 W per user, browser PWA, WebSocket sync, restic-based RAID-1-across-peers backup). Sketch in `docs/future-homeserver.md`. Operational polish on top of the voting protocol; not blocking v1.
- **Phase 3 / Mode 3 (individual)**: per-voter SQLCipher keys, no key sharing. For when peers do not mutually trust. Out of v1 scope.
- **Restore `macos-x86_64` and add `alpine-musl-x64` to the CI matrix.** Intel Mac GitHub-hosted runners stopped allocating during the v0.1.0 build push (job sat queued indefinitely); needs an investigation pass before re-adding. Alpine/musl is the natural next coverage step but the CMake-based LibreSSL build needs a few musl-specific tweaks.
- **Equivocation detection at tally time**: voter committing two contradictory ballots. Default in threat-model is "reject voter entirely and surface for convener review" — needs to be specified concretely in `docs/` before tally code enforces it.
- **TH1 hooks for Fossil web UI**: rendering ballots, manifests, tally results in browser via Fossil's built-in TH1 templating. Useful but not required for the CLI flow.
- **Threat model coverage for live-machine compromise**: outside SQLCipher's scope; would need OS-level mitigations (filesystem permissions, sandboxing). Document as known limitation, do not chase.

## Out of scope for this implementation

- Secret-ballot elections (would require blind-signature or anonymous-token protocols layered on top — different design).
- Open-roster elections (Sybil attack surface; the closed-roster assumption is load-bearing).
- Election mutation (manifest is immutable; mode is genesis-locked; rosters frozen at genesis).
