# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Fossil-based reference implementation of the Pretty Good Pizza voting mechanism. The mechanism spec lives in the sibling `pretty-good-pizza` repo. **Always cross-check tally logic against [`../pretty-good-pizza/README.md`](../pretty-good-pizza/README.md) and [`../pretty-good-pizza/CLAUDE.md`](../pretty-good-pizza/CLAUDE.md)** before changing the algorithm. The spec is the source of truth; this repo implements it.

## Architectural decisions

These were made deliberately in design conversation. Do not relitigate without reason:

- **Fossil is the foundation.** Distributed-by-design, hash-chained history, built-in wiki + forum + identity, single binary. Anyone can host a clone; sync handles federation.
- **No central server.** Each voter holds a clone; ballots propagate via `fossil sync`.
- **Identity = PGP keypair = Fossil user (one thing, not two).** Use `fossil setting clearsign on` for per-commit PGP signing. **Do not** implement a separate ballot-signing layer in Tcl. The voter's PGP fingerprint is the canonical identity in both the Fossil user record and the manifest's voter roster.
- **Public-ballot only (phase 1).** Targeting grants and board votes where transparency is wanted. Secret-ballot elections require a different layer (blind signatures, anonymous tokens) and are explicitly out of scope.
- **Wire format: JSON.** `tcllib` parses it; Fossil's web UI displays it; any language can independently verify a ballot file.
- **CLI language: Tcl.** Chosen to keep the verifier's dependency tree small (Tcl + tcllib + Fossil + system `gpg`). No Python, no Node, no Rust toolchain in the audit path.

## Phase plan

1. **Phase 1 (current).** Stock Fossil + Tcl library + system `gpg`. Schemas, CLI subcommands, deterministic tally, federation/partition tests. No custom Fossil build.
2. **Phase 2.** Custom Fossil build with `fossil ppp …` subcommands and full Tcl linked in.
3. **Phase 3.** SQLCipher swap-in, only after the threat model for at-rest encryption is concrete.

Phase 1 must work against an unmodified `fossil` binary so the algorithm and the federation model can be verified before betting on the custom-binary distribution story.

## Layout

- `docs/` — the trust-bearing specifications. Any independent verifier reads these:
  - `manifest-schema.md` — election manifest format.
  - `ballot-schema.md` — ballot file format and per-ballot validity rules.
  - `canonical-json.md` — byte-exact JSON serialization used for `manifest_hash` (RFC 8785 JCS, restricted subset).
  - `deterministic-sampling.md` — exact seed-to-draw procedure for stochastic allocation modes (SHAKE128 stream, integer weights via product-of-prices).
- `bin/ppp` — CLI entry point with subcommand dispatch (`init`, `vote`, `tally`, `verify`).
- `lib/` — Tcl modules:
  - `manifest.tcl` — load, validate, canonical hash.
  - `ballot.tcl` — load, validate (per-ballot rules only; equivocation is a tally-time check).
  - `tally.tcl` — the three allocation rules + threshold filter + seeded sampling.
- `test/` — `run-tests.tcl` harness and `fixtures/example-grant/` showing a complete election.

## Spec invariants to preserve

These are easy to get wrong; the spec has been corrected on each in conversation:

- **Selection-probability formula is `votes × value`, NOT `votes / value`.** The multiplication rewards both popularity and efficiency.
- **Three allocation modes (A, B, C).** A = stochastic with replacement; B = stochastic without replacement; C = deterministic weighted top-M. The mechanism is a framework, not a single algorithm.
- **No distribution phase.** A prior spec draft had one; it was removed because the real use cases are global allocations.
- **"Threshold," not "quorum."** Option-elimination cutoff. Parameterizable as absolute, fraction, or top-K. (Standard parliamentary "quorum" — members present to conduct business — is a separate concept and may appear in unrelated procedural notes.)
- **Seed must be reproducible.** Every implementation must produce the same selection from the same `(manifest, ballots, seed)` input. The exact mapping from seed bytes to draws must be specified concretely (suggested: HKDF-expand to a byte stream, take fixed-width chunks, modulo cumulative weights).

## Things to verify before implementing tally

- Canonical-JSON byte rules and the SHAKE128 draw protocol are pinned in `docs/canonical-json.md` and `docs/deterministic-sampling.md`. Read both before writing tally code. If you find yourself making a serialization or sampling choice not covered by those docs, update the doc first, not the code.
- Cross-implementation regression fixtures will live in `test/fixtures/canonical-json/` and `test/fixtures/sampling/`. Add a frozen `(input, expected)` pair the first time each component is implemented; any later change that alters output breaks the fixture intentionally and forces an audit.
- Equivocation detection (a voter committing two contradictory ballots) is done at tally time and must produce a deterministic, documented outcome. The current default (subject to change): reject the voter entirely and surface for convener review. Whatever rule is chosen must be specified in `docs/`, not implicit in code.
