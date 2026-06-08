# Custom binaries

This directory produces two binaries:

- `build-fossil.sh` → `dist/fossil-ppv`: Fossil 2.28 + SQLCipher (encrypted storage) + LibreSSL (TLS + libcrypto for SQLCipher) + the mode-aware `PRAGMA key` patch.
- `build-qjs.sh` → `dist/qjs-ppv`: QuickJS with the `ppv-crypto` native module (`../src/qjs-crypto.c` + `../src/ppv-keccak.c`) linked against the LibreSSL libcrypto already built for `fossil-ppv`. Provides SHA3-256, SHAKE128, and `randomBytes` to `bin/ppv` without shelling out.

The CLI (`bin/ppv`) is NOT linked into either binary. It runs in `qjs-ppv` alongside `fossil-ppv`. A verifier needs both custom binaries plus `gpg` on PATH — no system `openssl`, no stock `qjs`, no Tcl, no Python at runtime. (For mode-1 elections a stock `fossil` binary suffices in place of `fossil-ppv`; mode-2 requires the SQLCipher build.)

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
| `vendor/quickjs` | bellard/quickjs | `3d5e064e` | CLI runtime; `build-qjs.sh` patches `qjs.c` to register `ppv-crypto` and compiles a custom `qjs-ppv` binary linked against LibreSSL libcrypto. |

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

**Working end-to-end on three platforms.** GitHub Actions builds `fossil-ppv` and `qjs-ppv`, runs the unit suite and the federated scenario test, on `linux-glibc-x86_64`, `linux-glibc-arm64`, and `macos-arm64` (Apple Silicon). See `.github/workflows/build-test.yml`.

Build-time toolchain: a C compiler, `make`, `awk`, `cmake`, `autoconf`, `automake`, `pkg-config`, `patch`, `git`, `gnupg`. No Tcl (SQLCipher's autosetup uses its bundled `jimsh`), no Python.

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

- **Verifier gets a stronger story.** A mode-1 election can be verified with stock `fossil` + `qjs-ppv` + `gpg`. Only mode-2 (encrypted at rest) actually needs `fossil-ppv`.
- **Fossil's own configure has no `--with-quickjs`.** Embedding would mean inventing our own integration patches, adding work without proportional gain.
- **Standalone is simpler to audit.** Two small binaries with well-defined responsibilities beats one big binary that does both.

Fossil's built-in TH1 (Tcl-flavored templating, baked in) remains available for any future web-UI hook work. We just do not link full Tcl on top.

## Why `ppv-crypto` instead of shelling to `openssl`

The original Phase-1 design had `bin/ppv` shell out to system `openssl` for SHA3-256 and SHAKE128. That worked but had three problems:

1. **`openssl` is a heavy runtime dep** for what is fundamentally two hash primitives.
2. **macOS ships LibreSSL 3.3.6 as its system `openssl`**, which has SHA-3 in the CLI but no SHAKE128 (`openssl shake128` is "invalid command"). Users had to install a modern OpenSSL on top.
3. **Shelling out fork()/exec()'s per hash call**, which adds up for SHAKE128 streams during tally.

`build-qjs.sh` reuses the LibreSSL libcrypto it already builds for `fossil-ppv`, patches QuickJS to register `ppv-crypto`, and links the resulting `qjs-ppv` against `libcrypto.a`. SHA3-256 and `RAND_bytes` come from LibreSSL EVP/RAND. SHAKE128 is implemented in `src/ppv-keccak.c` (LibreSSL has no SHAKE at any level — empirically verified via `EVP_get_digestbyname("shake128") == NULL`); the implementation is the textbook Keccak-f[1600] sponge from FIPS 202 §3, §6.2, verified byte-identical to OpenSSL on rate-boundary test cases.
