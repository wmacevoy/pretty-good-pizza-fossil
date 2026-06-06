# Custom Fossil build

This directory builds a Fossil binary with SQLCipher (encrypted storage) and LibreSSL (TLS + libcrypto for SQLCipher). The result is a single statically-linkable executable.

The CLI (`bin/ppv`) is NOT linked into this binary. It runs in standalone QuickJS alongside the binary. A verifier needs: this custom Fossil (only for mode-2 encrypted repos; stock Fossil works for mode-1), plus `qjs`, `openssl`, and `gpg` on PATH.

## Status

**Skeleton.** `build-fossil.sh` validates inputs, sources pinned upstream versions from `versions.env`, and lays out the build sequence. Fossil is pinned to **version-2.28** (commit `1573b8e66e402f7d3f5cf70d37036a4ba2966edd` on the GitHub mirror, Fossil-native hash prefix `52445a27`, released 2026-03-11). Source-layout and configure-flag assumptions in the script are verified against this revision.

**`fossil-db-key.patch` is written** (see `patches/README.md`). It applies cleanly to the pinned Fossil 2.28 source tree; the syntax-check passes on the patched region (full compile awaits LibreSSL install).

What still gates a reproducible end-to-end build:

1. **Pin LibreSSL version** in `versions.env` (suggested: 4.2.1, matching sqlcipher-libressl CI).
2. **Pin sqlcipher-libressl commit** in `versions.env`.
3. **Install** LibreSSL and have the sqlcipher-libressl checkout ready.
4. **Run** `build-fossil.sh` against those inputs.

## Dependencies

| Dep | Source | Trust |
|---|---|---|
| LibreSSL (libcrypto + libssl) | upstream `libressl.org` | well-vetted; OpenBSD foundation |
| SQLCipher amalgamation | sibling `sqlcipher-libressl` | Warren's fork; CI-validated on 5 platforms |
| Fossil source | upstream `fossil-scm.org` | small C codebase, auditable |
| zlib | system (or upstream static) | ubiquitous |

For running the CLI (separate from this build):

| Dep | Notes |
|---|---|
| QuickJS (`qjs`) | upstream `bellard/quickjs`; pin a version in `versions.env` once the build machine's qjs is verified |
| `openssl` | for SHA3-256 + SHAKE128 via shell-out |
| `gpg` | for clearsign verification + mode-2 master-key decryption |

## Inputs (env)

| Variable | Required | Meaning |
|---|---|---|
| `LIBRESSL_PREFIX` | yes | LibreSSL install prefix (contains `include/`, `lib/libcrypto.a`, `lib/libssl.a`) |
| `SQLCIPHER_DIR` | yes | Path to a `sqlcipher-libressl` checkout |
| `FOSSIL_SRC` | yes | Path to a Fossil source checkout |
| `FOSSIL_REF` | no | Expected git ref of `FOSSIL_SRC`; verified if set |
| `OUTPUT_DIR` | no | Default `build/dist` |
| `ZLIB_PREFIX` | no | Static zlib prefix (default: system zlib) |
| `JOBS` | no | `make -j` parallelism (default: detected) |

## Why the CLI is not linked into Fossil

Originally the plan was to embed the CLI (then in Tcl) inside Fossil via `--with-tcl`. After switching the CLI to QuickJS we re-evaluated and concluded the cleaner story is to keep them separate:

- **Verifier gets a stronger story.** Anyone with stock Fossil + `qjs` + `openssl` can verify a mode-1 election. Only mode-2 needs the custom Fossil binary at all.
- **Fossil's own configure has no `--with-quickjs`.** Embedding would mean inventing our own integration patches, adding work without proportional gain.
- **Standalone is simpler to audit.** Two small binaries with well-defined responsibilities beats one big binary that does both.

Fossil's built-in TH1 (Tcl-flavored templating, baked in) remains available for any future web-UI hook work. We just do not link full Tcl on top.

## Pinning the recipe

When the open TODO is resolved, this directory should also contain:

- `patches/fossil-db-key.patch` — the small Fossil-side patch wiring `PRAGMA key`.

Cross-platform reproducibility (matching the `sqlcipher-libressl` model) implies a CI matrix building this on the same 5 platforms. That's phase-2-of-phase-2; do it after the local build works.
