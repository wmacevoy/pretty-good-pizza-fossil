# Pizza Party Voting — Fossil implementation

Reference implementation of the [Pizza Party Voting mechanism](../pizza-party-vote) backed by Fossil.

## Status

Milestones 1–3 done. Custom Fossil binary builds end-to-end with SQLCipher + LibreSSL via the vendored build pipeline. Tally is implemented for all three allocation modes with frozen cross-implementation regression fixtures. `init`, `vote`, `tally`, and `verify` subcommands are wired up. A federated scenario test exercises three independent voters producing byte-identical results.

See `CLAUDE.md` for the architectural decisions and `docs/roadmap.md` for the milestone-by-milestone state.

## Architecture in one sentence

Each election lives in a Fossil repository: the genesis commit is a signed election manifest, ballots are clearsigned commits at `ballots/<voter-fingerprint>.json`, and a QuickJS CLI (`bin/ppv`) reads the synced repo state to compute a deterministic, independently verifiable result.

## Get started

1. [`docs/install.md`](docs/install.md) — install the runtime deps (`qjs`, `openssl`, `gpg`) and optionally build the custom `fossil-ppv` binary for mode-2 (encrypted) repos.
2. [`docs/walkthrough.md`](docs/walkthrough.md) — Alice, Bob, and Carol use ppv to agree on decorations for a surprise party. End-to-end worked example with concrete commands.

## Quick reference

| What | Where |
|---|---|
| Install guide | [`docs/install.md`](docs/install.md) |
| Worked example | [`docs/walkthrough.md`](docs/walkthrough.md) |
| Voting mechanism spec | [`../pizza-party-vote/README.md`](../pizza-party-vote/README.md) |
| Election manifest format | [`docs/manifest-schema.md`](docs/manifest-schema.md) |
| Ballot file format | [`docs/ballot-schema.md`](docs/ballot-schema.md) |
| Canonical JSON (for `manifest_hash`) | [`docs/canonical-json.md`](docs/canonical-json.md) |
| Deterministic sampling | [`docs/deterministic-sampling.md`](docs/deterministic-sampling.md) |
| Threat model (trust modes) | [`docs/threat-model.md`](docs/threat-model.md) |
| Custom Fossil build | [`build/README.md`](build/README.md) |
| CLI entry point | [`bin/ppv`](bin/ppv) |
| Unit tests | [`test/run-tests.js`](test/run-tests.js) |
| Federated scenario test | [`test/scenario-test.sh`](test/scenario-test.sh) |

## Dependencies (target)

- Fossil (stock for mode 1; custom build with SQLCipher for mode 2 — see `build/`).
- `qjs` (QuickJS standalone interpreter; runs `bin/ppv`).
- `openssl` (system install; SHA3-256 and SHAKE128 via shell-out).
- `gpg` (system install; used by Fossil's clearsign and by mode-2 master-key decryption).

The CLI is NOT linked into Fossil; it runs in standalone `qjs` alongside the binary. A mode-1 (public) election can be verified with stock Fossil + `qjs` + `openssl`; only mode-2 (group, encrypted-at-rest) requires the custom Fossil build. No Python, no Node, no Rust toolchain in the voter's verification path.

## License

MIT. See `LICENSE`.
