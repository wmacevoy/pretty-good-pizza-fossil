# Custom Fossil build

This directory builds a Fossil binary with SQLCipher (encrypted storage) and LibreSSL (TLS + libcrypto for SQLCipher). The result is a single statically-linkable executable.

The CLI (`bin/ppv`) is NOT linked into this binary. It runs in standalone QuickJS alongside the binary. A verifier needs: this custom Fossil (only for mode-2 encrypted repos; stock Fossil works for mode-1), plus `qjs`, `openssl`, and `gpg` on PATH.

## Vendored dependencies

All build inputs are vendored as git submodules under `vendor/`. After cloning the repo:

```
git submodule update --init --recursive
```

| Submodule | Upstream | Pinned ref | Notes |
|---|---|---|---|
| `vendor/fossil` | drhsqlite/fossil-mirror | `1573b8e6` (version-2.28) | Source for the custom Fossil binary |
| `vendor/sqlcipher-libressl` | wmacevoy/sqlcipher-libressl | `0a6386e0` | SQLCipher amalgamation source (LibreSSL-patched fork) |
| LibreSSL (no submodule) | github releases | `v4.2.1` tarball, SHA256 `6d5c2f58…` | Downloaded + built locally into `vendor/libressl-build-out/` on first run (matches sqlcipher-libressl CI's CMake recipe) |
| `vendor/quickjs` | bellard/quickjs | `3d5e064e` | CLI runtime; build with `(cd vendor/quickjs && make)` |

Pin metadata (`*_REF`, version strings, release dates) lives in `versions.env`, which `build-fossil.sh` sources.

To bump a dependency:

```
cd vendor/<name>
git fetch
git checkout <new-ref>
cd ../..
git add vendor/<name>
# update the corresponding *_REF in build/versions.env
git commit -m "Bump <name> to <new-ref>"
```

## Status

**Skeleton plus all parts ready to run.** `build-fossil.sh` validates inputs, sources `versions.env`, builds LibreSSL from `vendor/libressl/` on first run (caches `build-out/`), produces the SQLCipher amalgamation via the sibling sqlcipher-libressl, swaps it into the Fossil source tree at the SEE filename (`src/sqlite3-see.c`), applies `patches/fossil-db-key.patch` for the mode-aware `PRAGMA key` wiring, and builds. The patch is verified to apply cleanly against the pinned Fossil revision.

The remaining gate on running an end-to-end build is operator-side: the build machine needs Fossil's normal build deps (`make`, a C compiler, `autoconf`/`automake` for the LibreSSL bootstrap) plus the time to compile LibreSSL once.

## Inputs (env)

All have sensible vendor-path defaults; override only for iterative work against a sibling checkout.

| Variable | Default | Meaning |
|---|---|---|
| `LIBRESSL_PREFIX` | `vendor/libressl-build-out` | LibreSSL install prefix (built on first run from the pinned tarball) |
| `LIBRESSL_CACHE` | `vendor/libressl-cache` | Where the downloaded tarball is kept between runs |
| `SQLCIPHER_DIR` | `vendor/sqlcipher-libressl` | sqlcipher-libressl checkout |
| `FOSSIL_SRC` | `vendor/fossil` | Fossil source checkout |
| `FOSSIL_REF` | from `versions.env` | Expected git ref of `FOSSIL_SRC`; verified before build |
| `OUTPUT_DIR` | `build/dist` | Where to write the built binary |
| `JOBS` | detected via `nproc`/`sysctl` | `make -j` parallelism |

## Build pipeline

1. **Build LibreSSL** from `vendor/libressl/` into `LIBRESSL_PREFIX` (skipped if `libcrypto.a` and `libssl.a` are already present).
2. **Produce the SQLCipher amalgamation** by running `vendor/sqlcipher-libressl`'s configure + `make sqlite3.c` against the just-built LibreSSL.
3. **Copy the amalgamation** to `vendor/fossil/src/sqlite3-see.c` — `--with-see=1` makes Fossil's build look for it there (`SQLITE3_ORIGIN=1`).
4. **Apply** `patches/fossil-db-key.patch` to wire the mode-aware key source into `db_maybe_obtain_encryption_key`.
5. **Configure** Fossil with `--with-openssl=$LIBRESSL_PREFIX --with-see=1 --json --internal-sqlite=1`.
6. **Build** Fossil; copy `fossil` to `$OUTPUT_DIR/fossil-ppv`.
7. **Smoke test** `fossil-ppv version`.

## Why the CLI is not linked into Fossil

Originally the plan was to embed the CLI (then in Tcl) inside Fossil via `--with-tcl`. After switching the CLI to QuickJS we kept them separate because:

- **Verifier gets a stronger story.** Anyone with stock Fossil + `qjs` + `openssl` can verify a mode-1 election. Only mode-2 needs the custom Fossil binary at all.
- **Fossil's own configure has no `--with-quickjs`.** Embedding would mean inventing our own integration patches, adding work without proportional gain.
- **Standalone is simpler to audit.** Two small binaries with well-defined responsibilities beats one big binary that does both.

Fossil's built-in TH1 (Tcl-flavored templating, baked in) remains available for any future web-UI hook work. We just do not link full Tcl on top.
