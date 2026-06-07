# Install

Two paths, depending on which trust mode you want to support:

- **Mode-1 (public) only — stock Fossil works.** Sufficient for transparent elections where the repo content is meant to be world-readable. The fastest install path.
- **Mode-2 (group, encrypted) — needs the custom `fossil-ppv` binary.** Required if you want the election repo encrypted at rest with SQLCipher.

Either way you also need:

- `qjs` (QuickJS) — runs the CLI.
- `openssl` — SHA3-256 and SHAKE128 (almost certainly already installed on your system).
- `gpg` (GnuPG 2.x) — clearsigning ballots, identity, and the mode-2 key wrap.

## Get the source

```
git clone --recurse-submodules https://github.com/wmacevoy/pizza-party-vote-fossil
cd pizza-party-vote-fossil
```

`--recurse-submodules` populates `vendor/fossil`, `vendor/sqlcipher-libressl`, and `vendor/quickjs`. If you forgot, run `git submodule update --init --recursive` after cloning.

## Quick path — mode 1 only

Install the runtime dependencies via your package manager.

**macOS (Homebrew):**

```
brew install fossil qjs openssl gnupg
```

**Debian/Ubuntu:**

```
sudo apt install fossil openssl gnupg
# qjs may not be packaged; either build vendor/quickjs (see below) or grab
# a prebuilt binary from upstream releases.
```

**Verify:**

```
./test/run-tests.js
```

Expect `15 passed, 0 failed`. The CLI is now usable for mode-1 elections via `bin/ppv {init,vote,tally,verify}`.

## Full path — mode 2 (encrypted)

You also need to build the custom Fossil binary that wires SQLCipher into Fossil's `db_open` path with the mode-aware key source.

**Prerequisites for the build itself** (in addition to the runtime deps above):

- A C compiler (`gcc` or `clang`)
- `make`
- `cmake` (used to build LibreSSL from the vendored tarball)
- `tcl` / `tclsh` (used by SQLCipher's amalgamation step)
- `autoconf`, `automake`, `pkg-config` (for SQLCipher's configure)

**macOS:** these come with Xcode Command Line Tools plus `brew install cmake tcl-tk autoconf automake pkg-config`.

**Debian/Ubuntu:**

```
sudo apt install build-essential cmake tcl tcl-dev autoconf automake pkg-config
```

**Build:**

```
./build/build-fossil.sh
```

First run takes 5–10 minutes (most of it building LibreSSL from the vendored source). Subsequent runs are cached and finish in under a minute.

Output: `build/dist/fossil-ppv` (a ~7MB self-contained binary).

**Put it on PATH as `fossil`** (so `bin/ppv` finds it):

```
ln -sf "$PWD/build/dist/fossil-ppv" ~/.local/bin/fossil
# or:
export PATH="$PWD/build/dist:$PATH"
# (and rename the symlink to 'fossil' if you want both names)
```

If you have system `fossil` installed and want both, the simplest is to put `build/dist/fossil-ppv` on PATH and use it explicitly as `fossil-ppv` for ppv repos; modify `bin/ppv` to call `fossil-ppv` instead of `fossil` if you prefer that.

**Verify the encrypted path works:**

```
./build/dist/fossil-ppv version
# Should report: This is fossil version 2.28 ...

tmp=$(mktemp -d)
FOSSIL_PPV_KEY="testkey" ./build/dist/fossil-ppv init $tmp/test.efossil
head -c 16 $tmp/test.efossil | xxd
# Should NOT start with "SQLite format 3" — should be random bytes.
# That confirms SQLCipher is engaged.
rm -rf $tmp
```

## Verify the full federated story

The end-to-end test exercises three ephemeral GPG identities, the full
`init` → `vote` → `tally` → `verify` flow, and confirms that three independent tally runs produce byte-identical results.

```
./test/scenario-test.sh
```

Expect `PASS: three independent tallies match byte-for-byte and verify succeeds in all three workspaces.` followed by a JSON result.

If you only built mode-1, this still works (the scenario uses public-mode elections).

## What's next

Once installed, walk through [`docs/walkthrough.md`](walkthrough.md) — three friends use ppv to plan a surprise party.
