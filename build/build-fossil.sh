#!/usr/bin/env bash
set -euo pipefail

# Build a custom Fossil binary with:
#   - SQLCipher (encrypted SQLite) via the sibling sqlcipher-libressl project
#   - LibreSSL for libcrypto (SQLCipher storage encryption) and libssl (TLS for sync)
#   - The mode-aware PRAGMA key patch, wired into Fossil's existing SEE scaffolding
#
# The CLI (bin/ppv) is not linked into Fossil. It runs in standalone QuickJS
# alongside this binary. A verifier needs: the custom fossil (for mode-2 SQLCipher
# repos), qjs, openssl, gpg.
#
# Modeled on ../sqlcipher-libressl/build-sqlcipher-libressl.sh.
# Read build/README.md before running. The TODO blocks below mark steps that
# need to be pinned against the chosen Fossil revision; the script is a
# skeleton, not yet a reproducible recipe.
#
# Required env:
#   LIBRESSL_PREFIX   install prefix containing include/ and lib/{libcrypto.a,libssl.a}
#   SQLCIPHER_DIR     path to a sqlcipher-libressl checkout (sibling project)
#   FOSSIL_SRC        path to a Fossil source checkout (pinned revision; see FOSSIL_REF)
#
# Optional env:
#   OUTPUT_DIR        where to write the built binary (default: build/dist)
#   FOSSIL_REF        expected git ref of FOSSIL_SRC (verified if set)
#   ZLIB_PREFIX       static zlib prefix (default: system zlib)
#   JOBS              make parallelism (default: nproc or sysctl detected)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR/dist}"

# Load pinned upstream version metadata.
# shellcheck source=./versions.env
. "$SCRIPT_DIR/versions.env"

# Default the source paths to the vendored submodules under ../vendor/.
# Each can be overridden by exporting before invoking, e.g.
#   FOSSIL_SRC=$HOME/work/fossil-trunk ./build/build-fossil.sh
: "${FOSSIL_SRC:=$REPO_ROOT/vendor/fossil}"
: "${SQLCIPHER_DIR:=$REPO_ROOT/vendor/sqlcipher-libressl}"
: "${LIBRESSL_PREFIX:=$REPO_ROOT/vendor/libressl-build-out}"
: "${LIBRESSL_CACHE:=$REPO_ROOT/vendor/libressl-cache}"

# Parallelism
if [ -z "${JOBS:-}" ]; then
    if command -v nproc >/dev/null 2>&1; then
        JOBS="$(nproc)"
    else
        JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 2)"
    fi
fi

mkdir -p "$OUTPUT_DIR"

# ── Step 0: Download + build LibreSSL if not already built ──────
# Uses the official GitHub release tarball with pinned SHA256 (libressl/
# portable's git tree is build glue around OpenBSD sources it doesn't
# carry; the release tarballs are the actual source distribution).
# Same approach sqlcipher-libressl uses in CI.
if [ ! -f "$LIBRESSL_PREFIX/lib/libcrypto.a" ] || [ ! -f "$LIBRESSL_PREFIX/lib/libssl.a" ]; then
    : "${LIBRESSL_TARBALL_URL:?Set LIBRESSL_TARBALL_URL (see versions.env)}"
    : "${LIBRESSL_TARBALL_SHA256:?Set LIBRESSL_TARBALL_SHA256 (see versions.env)}"
    command -v cmake >/dev/null 2>&1 || { echo "ERR: cmake is required to build LibreSSL"; exit 1; }

    mkdir -p "$LIBRESSL_CACHE"
    tarball="$LIBRESSL_CACHE/libressl-${LIBRESSL_VERSION}.tar.gz"
    if [ ! -f "$tarball" ]; then
        echo "==> Downloading LibreSSL $LIBRESSL_VERSION from $LIBRESSL_TARBALL_URL"
        curl -fsSL "$LIBRESSL_TARBALL_URL" -o "$tarball"
    fi

    actual_sha="$(shasum -a 256 "$tarball" | awk '{print $1}')"
    if [ "$actual_sha" != "$LIBRESSL_TARBALL_SHA256" ]; then
        echo "ERR: LibreSSL tarball SHA256 mismatch"
        echo "     expected: $LIBRESSL_TARBALL_SHA256"
        echo "     actual:   $actual_sha"
        exit 1
    fi

    echo "==> Building LibreSSL $LIBRESSL_VERSION"
    extract_dir="$LIBRESSL_CACHE/libressl-${LIBRESSL_VERSION}"
    rm -rf "$extract_dir"
    tar -xzf "$tarball" -C "$LIBRESSL_CACHE"
    (
        cd "$extract_dir"
        mkdir -p build
        cd build
        # Investigated turning on LIBRESSL_APPS to get a self-hosted openssl
        # binary. LibreSSL's openssl CLI supports SHA-3-256 via `dgst -sha3-256`
        # but does NOT expose SHAKE128 in a usable form, so it can't replace
        # the system openssl for the runtime. Kept APPS off; runtime needs a
        # modern openssl (Homebrew's, conda's, distro package) on PATH.
        cmake .. -DCMAKE_INSTALL_PREFIX="$LIBRESSL_PREFIX" \
            -DLIBRESSL_APPS=OFF -DLIBRESSL_TESTS=OFF -DBUILD_SHARED_LIBS=OFF \
            -DCMAKE_BUILD_TYPE=Release
        make -j"$JOBS"
        make install
    )
fi

# ── Sanity checks ───────────────────────────────────────────────
echo "==> Verifying inputs"
[ -f "$LIBRESSL_PREFIX/lib/libcrypto.a" ]        || { echo "ERR: $LIBRESSL_PREFIX/lib/libcrypto.a missing"; exit 1; }
[ -f "$LIBRESSL_PREFIX/lib/libssl.a" ]           || { echo "ERR: $LIBRESSL_PREFIX/lib/libssl.a missing";    exit 1; }
[ -f "$LIBRESSL_PREFIX/include/openssl/crypto.h" ] || { echo "ERR: LibreSSL headers missing under $LIBRESSL_PREFIX/include"; exit 1; }
[ -d "$SQLCIPHER_DIR" ]                          || { echo "ERR: SQLCIPHER_DIR not a directory: $SQLCIPHER_DIR (did you 'git submodule update --init'?)"; exit 1; }
[ -d "$FOSSIL_SRC" ]                             || { echo "ERR: FOSSIL_SRC not a directory: $FOSSIL_SRC (did you 'git submodule update --init'?)"; exit 1; }
command -v qjs >/dev/null 2>&1                   || { echo "WARN: qjs (QuickJS) not on PATH; not required to build Fossil but required to run bin/ppv against the result; build with: (cd vendor/quickjs && make)"; }

if [ -n "${FOSSIL_REF:-}" ]; then
    actual="$(git -C "$FOSSIL_SRC" rev-parse HEAD 2>/dev/null || echo unknown)"
    if [ "$actual" != "$FOSSIL_REF" ]; then
        echo "ERR: FOSSIL_SRC is at $actual, expected FOSSIL_REF=$FOSSIL_REF"
        exit 1
    fi
fi

# ── Step 1: SQLCipher amalgamation ──────────────────────────────
echo "==> Producing SQLCipher amalgamation (via sqlcipher-libressl)"
if [ ! -f "$SQLCIPHER_DIR/sqlite3.c" ] || [ ! -f "$SQLCIPHER_DIR/sqlite3.h" ]; then
    (
        cd "$SQLCIPHER_DIR"
        ./configure --with-tempstore=yes \
            CFLAGS="-DSQLITE_HAS_CODEC -DSQLCIPHER_CRYPTO_OPENSSL \
                    -DSQLITE_EXTRA_INIT=sqlcipher_extra_init \
                    -DSQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown \
                    -I$LIBRESSL_PREFIX/include" \
            LDFLAGS="$LIBRESSL_PREFIX/lib/libcrypto.a"
        make -j"$JOBS" sqlite3.c
    )
fi
[ -f "$SQLCIPHER_DIR/sqlite3.c" ] || { echo "ERR: sqlite3.c not produced"; exit 1; }

# ── Step 2: Swap SQLCipher into Fossil source tree ──────────────
echo "==> Patching Fossil source"
# --with-see=1 sets SQLITE3_ORIGIN=1; Fossil's main.mk resolves that to
# extsrc/sqlite3-see.c (the auto.def comment says "src/" but the real path
# per main.mk is $(SRCDIR_extsrc)/sqlite3-see.c). Drop the SQLCipher
# amalgamation there.
cp "$SQLCIPHER_DIR/sqlite3.c" "$FOSSIL_SRC/extsrc/sqlite3-see.c"
cp "$SQLCIPHER_DIR/sqlite3.h" "$FOSSIL_SRC/extsrc/sqlite3.h"
# Fossil's SEE convention also expects extsrc/shell-see.c. Stock shell.c
# works since SQLCipher's bundled SQLite (3.53.1 via vendor/sqlcipher-libressl
# at v4.16.0 baseline) has every symbol Fossil's shell.c references.
cp "$FOSSIL_SRC/extsrc/shell.c" "$FOSSIL_SRC/extsrc/shell-see.c"

# Extend SEE_FLAGS.1 in main.mk with the SQLCipher-required compile flags.
# Fossil's main.mk hard-codes SQLITE_THREADSAFE=0 in SQLITE_OPTIONS; SQLCipher
# requires 1 or 2. SEE_FLAGS.1 is appended AFTER SQLITE_OPTIONS on the compile
# line, so the last -D wins. SQLCipher also requires SQLITE_TEMP_STORE=2 and
# the EXTRA_INIT/SHUTDOWN hooks.
MAINMK="$FOSSIL_SRC/src/main.mk"
SEE_OLD='SEE_FLAGS.1 = -DSQLITE_HAS_CODEC -DSQLITE_SHELL_DBKEY_PROC=fossil_key'
SEE_NEW="${SEE_OLD} -DSQLITE_THREADSAFE=1 -DSQLITE_TEMP_STORE=2 -DSQLITE_EXTRA_INIT=sqlcipher_extra_init -DSQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown"
if ! grep -qF "$SEE_OLD" "$MAINMK"; then
    echo "ERR: SEE_FLAGS.1 line not found verbatim in main.mk; check FOSSIL_REF" >&2
    exit 1
fi
# In-place edit. `awk` treats sub's first arg as a regex and its second as
# a replacement template (with & specials); use literal-string substring math
# instead so neither dot/dollar in old nor ampersand/backslash in new can bite.
awk -v old="$SEE_OLD" -v new="$SEE_NEW" '
    !done {
        i = index($0, old)
        if (i > 0) {
            $0 = substr($0, 1, i - 1) new substr($0, i + length(old))
            done = 1
        }
    } { print }
' "$MAINMK" > "$MAINMK.tmp" && mv "$MAINMK.tmp" "$MAINMK"

# patches/fossil-db-key.patch wires the mode-aware key source into Fossil's
# existing SEE scaffolding (db_maybe_obtain_encryption_key in src/db.c):
#   FOSSIL_PPV_KEY env var > gpg-decrypt keys/master.key.asc > stock prompt
#   only if FOSSIL_PPV_STOCK_PROMPT=1.
# See patches/README.md and docs/threat-model.md for the design.
if [ -f "$SCRIPT_DIR/patches/fossil-db-key.patch" ]; then
    echo "  applying fossil-db-key.patch"
    ( cd "$FOSSIL_SRC" && patch -p1 < "$SCRIPT_DIR/patches/fossil-db-key.patch" )
else
    echo "  WARN: patches/fossil-db-key.patch absent — built binary will use Fossil's stock SEE prompt-for-passphrase behavior, not the mode-aware ppv flow"
fi

# (Earlier versions of this script carried xsystem.c sed shims for
# sqlite3_str_free and sqlite3_format_query_result. Those symbols now
# exist in vendor/sqlcipher-libressl's SQLite 3.53.1 baseline + Fossil's
# stock shell.c, so the shims have been removed. See git history if you
# need to resurrect them for an older SQLCipher.)

# ── Step 3: Configure Fossil ────────────────────────────────────
echo "==> Configuring Fossil"
# Configure flags verified against Fossil $FOSSIL_VERSION auto.def.
#   --with-openssl=<prefix>    same flag for OpenSSL or LibreSSL; Fossil probes
#                              for libcrypto/libssl symbols at configure time
#   --with-see=1               enables Fossil's SEE scaffolding (the hook point
#                              for our patch); defines USE_SEE and SQLITE_HAS_CODEC
#   --json                     enables Fossil's JSON HTTP API endpoints
#   --internal-sqlite=1        explicit; we substitute the bundled amalgamation
(
    cd "$FOSSIL_SRC"
    ./configure \
        --with-openssl="$LIBRESSL_PREFIX" \
        --with-see=1 \
        --json \
        --internal-sqlite=1 \
        CFLAGS="-DSQLCIPHER_CRYPTO_OPENSSL -O2" \
        LIBS="$LIBRESSL_PREFIX/lib/libssl.a $LIBRESSL_PREFIX/lib/libcrypto.a"
)

# ── Step 4: Build ───────────────────────────────────────────────
echo "==> Building Fossil"
make -C "$FOSSIL_SRC" -j"$JOBS"

# ── Step 5: Install ─────────────────────────────────────────────
echo "==> Installing to $OUTPUT_DIR"
cp "$FOSSIL_SRC/fossil" "$OUTPUT_DIR/fossil-ppv"
ls -lh "$OUTPUT_DIR/fossil-ppv"

# ── Step 6: Smoke test ──────────────────────────────────────────
echo "==> Smoke tests"
"$OUTPUT_DIR/fossil-ppv" version

echo "==> Build complete"
