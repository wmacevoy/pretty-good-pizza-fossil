# Pretty Good Pizza — Fossil implementation

Reference implementation of the [Pretty Good Pizza voting mechanism](../pretty-good-pizza) backed by Fossil.

## Status

**Phase 1 (scaffolding).** Schemas defined, Tcl CLI skeleton in place. No working tally yet. See `CLAUDE.md` for the phased build plan and the architectural decisions already made.

## Architecture in one sentence

Each election lives in a Fossil repository: the genesis commit is a signed election manifest, ballots are clearsigned commits at `ballots/<voter-fingerprint>.json`, and a Tcl CLI (`bin/ppp`) reads the synced repo state to compute a deterministic, independently verifiable result.

## Quick reference

| What | Where |
|---|---|
| Voting mechanism spec | [`../pretty-good-pizza/README.md`](../pretty-good-pizza/README.md) |
| Election manifest format | [`docs/manifest-schema.md`](docs/manifest-schema.md) |
| Ballot file format | [`docs/ballot-schema.md`](docs/ballot-schema.md) |
| Canonical JSON (for `manifest_hash`) | [`docs/canonical-json.md`](docs/canonical-json.md) |
| Deterministic sampling | [`docs/deterministic-sampling.md`](docs/deterministic-sampling.md) |
| CLI entry point | [`bin/ppp`](bin/ppp) |
| Tests | [`test/run-tests.tcl`](test/run-tests.tcl) |

## Dependencies (target)

- Fossil (stock, with `clearsign` enabled).
- Tcl 8.6+ with `tcllib` (for `json`, `sha3`, time parsing).
- `gpg` (system install; used by Fossil's clearsign and by the CLI for signature verification).

No Python, Node, or Rust in the voter's verification path.

## License

MIT. See `LICENSE`.
