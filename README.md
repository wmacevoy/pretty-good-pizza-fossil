# Pizza Party Voting — Fossil implementation

Reference implementation of the [Pizza Party Voting mechanism](../pizza-party-vote) backed by Fossil.

## Status

**v0.1.0 — first tagged release.** Milestones 1–5 done. Two custom binaries (`fossil-ppv` with SQLCipher + LibreSSL; `qjs-ppv` with the `ppv-crypto` native module replacing the openssl shell-out) build and test green across `linux-glibc-x86_64`, `linux-glibc-arm64`, and `macos-arm64`. Tally is implemented for all three allocation modes with frozen cross-implementation regression fixtures. `init`, `vote`, `tally`, and `verify` are wired up. The federated scenario test exercises three independent voters producing byte-identical results.

See `CLAUDE.md` for the architectural decisions and `docs/roadmap.md` for the milestone-by-milestone state.

## Architecture in one sentence

Each election lives in a Fossil repository: the genesis commit is a signed election manifest, ballots are clearsigned commits at `ballots/<voter-fingerprint>.json`, and a QuickJS CLI (`bin/ppv`) reads the synced repo state to compute a deterministic, independently verifiable result.

## Get started

1. [`docs/install.md`](docs/install.md) — build the two custom binaries (`fossil-ppv` and `qjs-ppv`); install `gpg`. Nothing else on PATH at runtime.
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

## Runtime dependencies

- `fossil-ppv` — built by `build/build-fossil.sh`. Fossil 2.28 + SQLCipher + LibreSSL + the mode-aware key patch. Required for mode-group elections (encrypted-at-rest clone, gpg-wrapped master key); mode-public elections can also use stock `fossil`.
- `qjs-ppv` — built by `build/build-qjs.sh`. QuickJS with the `ppv-crypto` native module (SHA3-256 via LibreSSL EVP, SHAKE128 via vendored Keccak, RAND_bytes via LibreSSL) linked in. Runs `bin/ppv`.
- `gpg` — only system tool needed. Identity, ballot clearsigning, and mode-2 master-key wrap/unwrap.

No `openssl`, no `qjs`, no Tcl, no Python, no Node, no Rust toolchain at runtime. The CLI is NOT linked into Fossil; it runs in `qjs-ppv` alongside the binary.

## License

MIT. See `LICENSE`.
