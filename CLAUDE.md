# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Fossil-based reference implementation of the Pizza Party Voting (ppv) mechanism. The mechanism spec lives in the sibling `pizza-party-vote` repo. **Always cross-check tally logic against [`../pizza-party-vote/README.md`](../pizza-party-vote/README.md) and [`../pizza-party-vote/CLAUDE.md`](../pizza-party-vote/CLAUDE.md)** before changing the algorithm. The spec is the source of truth; this repo implements it.

The protocol abbreviation is **ppv** (pizza party voting). An earlier iteration used `ppp`; that was changed to avoid semantic collision with PGP, which the system uses heavily for identity and signing.

## Architectural decisions

These were made deliberately in design conversation. Do not relitigate without reason:

- **Fossil is the foundation.** Distributed-by-design, hash-chained history, built-in wiki + forum + identity, single binary. Anyone can host a clone; sync handles federation.
- **No central server.** Each voter holds a clone; ballots propagate via `fossil sync`.
- **Identity = PGP keypair = Fossil user (one thing, not two).** Use `fossil setting clearsign on` for per-commit PGP signing. **Do not** implement a separate ballot-signing layer in the CLI. The voter's PGP fingerprint is the canonical identity in both the Fossil user record and the manifest's voter roster.
- **Public-ballot only (phase 1).** Targeting grants and board votes where transparency is wanted. Secret-ballot elections require a different layer (blind signatures, anonymous tokens) and are explicitly out of scope.
- **Wire format: JSON.** `JSON.parse` reads it; Fossil's web UI displays it; any language can independently verify a ballot file.
- **CLI runtime: QuickJS.** JavaScript via the standalone `qjs` interpreter. JSON is native, BigInt is native, the audit surface is small (Bellard-tier code, ~70k lines C). Shell-outs to system `openssl` (SHA3-256, SHAKE128) and `gpg` (PGP decrypt) keep the dependency tree minimal: `qjs` + `openssl` + `gpg` + Fossil.

## Phase plan

1. **Phase 1 (current).** Stock Fossil + standalone `qjs` + system `openssl`/`gpg`. Schemas, CLI subcommands, deterministic tally, federation/partition tests. No custom Fossil build.
2. **Phase 2.** Custom Fossil binary, built by `build/build-fossil.sh`, with:
   - SQLCipher swapped in for the bundled SQLite, via the sibling `../sqlcipher-libressl` project.
   - LibreSSL providing both `libcrypto` (for SQLCipher) and `libssl` (for TLS sync).
   - The mode-aware `PRAGMA key` patch wired into Fossil's existing SEE scaffolding.

The CLI does not get linked into the custom Fossil binary. It remains a separate `qjs` script, which means: anyone with stock Fossil + `qjs` + `openssl` can verify a mode-1 (public) election; only mode-2 (group, encrypted-at-rest) needs the custom Fossil binary at all. This is a stronger verifier story than embedding the CLI would give.

Phase 2 collapses what was originally planned as a separate "custom Fossil" phase and a later "SQLCipher swap-in" phase. The heavy lift — LibreSSL ↔ SQLCipher integration — is solved by `sqlcipher-libressl`, so adding SQLCipher to the Fossil build is a few extra compile flags rather than a separate phase. See `build/README.md` for the rationale and the open TODOs.

Phase 1 must work against an unmodified `fossil` binary so the algorithm and the federation model can be verified before betting on the custom-binary distribution story.

**Threat model for at-rest encryption** is in `docs/threat-model.md` (Pinned). The SQLCipher `PRAGMA key` source is the PGP-wrapped master key in mode 2; that doc is the source of truth for the build patch.

## Layout

- `docs/` — the trust-bearing specifications. Any independent verifier reads these:
  - `manifest-schema.md` — election manifest format.
  - `ballot-schema.md` — ballot file format and per-ballot validity rules.
  - `canonical-json.md` — byte-exact JSON serialization used for `manifest_hash` (RFC 8785 JCS, restricted subset).
  - `deterministic-sampling.md` — exact seed-to-draw procedure for stochastic allocation modes (SHAKE128 stream, integer weights via product-of-prices).
  - `threat-model.md` — three trust modes, at-rest encryption design, build patch plumbing.
  - `roadmap.md` — ordered checklist of milestones and what blocks each.
- `bin/ppv` — CLI entry point with subcommand dispatch (`init`, `vote`, `tally`, `verify`). QuickJS module; `#!/usr/bin/env qjs` shebang.
- `lib/` — JS modules:
  - `canonical-json.js` — JCS encoder + restricted-subset parser.
  - `sha3.js` — SHA3-256 and SHAKE128 wrappers (shell out to system `openssl`).
  - `shell.js` — common shell-out helper used by `sha3.js` and the future `gpg` paths.
  - `manifest.js` — load, validate, canonical hash.
  - `ballot.js` — load, validate (per-ballot rules only; equivocation is a tally-time check).
  - `tally.js` — the three allocation rules + threshold filter + seeded sampling.
- `test/` — `run-tests.js` harness and `fixtures/` directories. `fixtures/canonical-json/` holds the cross-implementation regression for the JCS encoder + hash.
- `build/` — custom Fossil build script, version pins, and patch placeholder.

## Spec invariants to preserve

These are easy to get wrong; the spec has been corrected on each in conversation:

- **Selection-probability formula is `votes × value`, NOT `votes / value`.** The multiplication rewards both popularity and efficiency.
- **Three allocation modes (A, B, C).** A = stochastic with replacement; B = stochastic without replacement; C = deterministic weighted top-M. The mechanism is a framework, not a single algorithm.
- **No distribution phase.** A prior spec draft had one; it was removed because the real use cases are global allocations.
- **"Threshold," not "quorum."** Option-elimination cutoff. Parameterizable as absolute, fraction, or top-K. (Standard parliamentary "quorum" — members present to conduct business — is a separate concept and may appear in unrelated procedural notes.)
- **Schema version is `"ppv/1"`** (renamed from `"ppp/1"` for clarity; `ppp` collided with PGP).
- **Integer weights via BigInt.** JS BigInt handles the product-of-other-prices arithmetic exactly. No floating-point divergence between implementations.

## Things to verify before implementing tally

- Canonical-JSON byte rules and the SHAKE128 draw protocol are pinned in `docs/canonical-json.md` and `docs/deterministic-sampling.md`. Read both before writing tally code. If you find yourself making a serialization or sampling choice not covered by those docs, update the doc first, not the code.
- Cross-implementation regression fixtures live in `test/fixtures/canonical-json/` and (TODO) `test/fixtures/sampling/`. Any change that alters output breaks the fixture intentionally and forces an audit.
- Equivocation detection (a voter committing two contradictory ballots) is done at tally time and must produce a deterministic, documented outcome. The current default (subject to change): reject the voter entirely and surface for convener review. Whatever rule is chosen must be specified in `docs/`, not implicit in code.
