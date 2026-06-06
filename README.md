# Pretty Good Pizza — Fossil implementation

Reference implementation of the [Pretty Good Pizza voting mechanism](../pretty-good-pizza) backed by Fossil.

## Status

**Phase 1.** Schemas pinned, QuickJS CLI skeleton in place, canonical-JSON + SHA3-256 implemented and regression-tested. Tally algorithm not yet implemented. See `CLAUDE.md` for the architectural decisions and `docs/roadmap.md` for the milestone-by-milestone state.

## Architecture in one sentence

Each election lives in a Fossil repository: the genesis commit is a signed election manifest, ballots are clearsigned commits at `ballots/<voter-fingerprint>.json`, and a QuickJS CLI (`bin/ppv`) reads the synced repo state to compute a deterministic, independently verifiable result.

## Quick reference

| What | Where |
|---|---|
| Voting mechanism spec | [`../pretty-good-pizza/README.md`](../pretty-good-pizza/README.md) |
| Election manifest format | [`docs/manifest-schema.md`](docs/manifest-schema.md) |
| Ballot file format | [`docs/ballot-schema.md`](docs/ballot-schema.md) |
| Canonical JSON (for `manifest_hash`) | [`docs/canonical-json.md`](docs/canonical-json.md) |
| Deterministic sampling | [`docs/deterministic-sampling.md`](docs/deterministic-sampling.md) |
| CLI entry point | [`bin/ppv`](bin/ppv) |
| Tests | [`test/run-tests.js`](test/run-tests.js) |

## Dependencies (target)

- Fossil (stock for mode 1; custom build with SQLCipher for mode 2 — see `build/`).
- `qjs` (QuickJS standalone interpreter; runs `bin/ppv`).
- `openssl` (system install; SHA3-256 and SHAKE128 via shell-out).
- `gpg` (system install; used by Fossil's clearsign and by mode-2 master-key decryption).

The CLI is NOT linked into Fossil; it runs in standalone `qjs` alongside the binary. A mode-1 (public) election can be verified with stock Fossil + `qjs` + `openssl`; only mode-2 (group, encrypted-at-rest) requires the custom Fossil build. No Python, no Node, no Rust toolchain in the voter's verification path.

## License

MIT. See `LICENSE`.
