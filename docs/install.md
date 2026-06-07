# Install

Two custom binaries to build, one system tool to install:

| Binary | Built by | What it does |
|---|---|---|
| `fossil-ppv` | `build/build-fossil.sh` | Fossil 2.28 + SQLCipher + LibreSSL + the mode-aware key patch. Used by `ppv` for mode-2 (encrypted) repos. Mode-1 elections work with stock Fossil too. |
| `qjs-ppv` | `build/build-qjs.sh` | QuickJS + the `ppv-crypto` native module (SHA3-256 from LibreSSL EVP, SHAKE128 from vendored Keccak, RAND_bytes for randomness). Runs `bin/ppv`. |
| `gpg` | system | Voter identity and signing. Mode-2 also uses it to wrap/unwrap the SQLCipher master key. |

After install: nothing else needed on PATH. No `openssl`, no `qjs`, no Tcl at runtime.

## Get the source

```
git clone --recurse-submodules https://github.com/wmacevoy/pizza-party-vote-fossil
cd pizza-party-vote-fossil
```

`--recurse-submodules` populates `vendor/fossil`, `vendor/sqlcipher-libressl`, and `vendor/quickjs`. If you forgot, run `git submodule update --init --recursive` after cloning.

## Build-time tools

The two `./build/build-*.sh` scripts need these to be on PATH:

- A C compiler (`gcc` or `clang`)
- `make`
- `cmake` (used to build LibreSSL from the vendored release tarball)
- `tclsh` / `tcl-tk` (used by SQLCipher's `make sqlite3.c` amalgamation step — **build-only**, never needed at runtime)
- `autoconf`, `automake`, `pkg-config` (for SQLCipher's `configure`)
- `patch` (for applying our two small patches to Fossil and QuickJS during the build)
- `python3` (one short inline script in `build-fossil.sh` edits Fossil's `main.mk` to add the SQLCipher flags — build-only)

**macOS (Homebrew):**

```
brew install cmake tcl-tk autoconf automake pkg-config gnupg
xcode-select --install   # if you haven't already; provides cc and make
```

**Debian/Ubuntu:**

```
sudo apt install build-essential cmake tcl tcl-dev \
                 autoconf automake pkg-config patch gnupg python3
```

## Build

```
./build/build-fossil.sh
./build/build-qjs.sh
```

First run takes 5–10 minutes (most of it building LibreSSL from the vendored source). Subsequent runs are cached.

Outputs:

- `build/dist/fossil-ppv` (~7 MB) — the custom Fossil binary.
- `build/dist/qjs-ppv` (~2.3 MB) — the custom QuickJS binary with `ppv-crypto` linked in.

## Put them on PATH

`bin/ppv` has `#!/usr/bin/env qjs-ppv` at its shebang, so `qjs-ppv` needs to be on PATH. The simplest:

```
mkdir -p ~/.local/bin
ln -sf "$PWD/build/dist/qjs-ppv" ~/.local/bin/qjs-ppv
ln -sf "$PWD/build/dist/fossil-ppv" ~/.local/bin/fossil-ppv
# also expose fossil-ppv as 'fossil' if you don't have system fossil installed:
ln -sf "$PWD/build/dist/fossil-ppv" ~/.local/bin/fossil
```

Adjust `~/.local/bin` to wherever you keep user binaries; just make sure it's on PATH.

## Verify

```
./build/dist/fossil-ppv version          # custom Fossil reports 2.28
./test/run-tests.js                       # 15 unit tests
./test/scenario-test.sh                   # full federated three-voter scenario
```

Both test suites should report `passed`. Common failure modes:

- `Could not find name 'ppv-crypto'` in the unit suite → `qjs-ppv` isn't on PATH yet, so `bin/ppv`'s shebang found a stock `qjs` that doesn't have our native module. Re-do the symlink step.
- `no fossil binary available` from the scenario test → the `fossil` symlink (pointing at `fossil-ppv`) is missing.

## What's next

Once installed, walk through [`docs/walkthrough.md`](walkthrough.md) — three friends use ppv to plan a surprise party. End-to-end worked example with commands that match the install you just did.
