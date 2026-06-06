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

# Load pinned upstream versions (FOSSIL_REF in particular). Each variable can
# still be overridden by setting it in the environment before invocation.
# shellcheck source=./versions.env
. "$SCRIPT_DIR/versions.env"

# ── Required env ────────────────────────────────────────────────
: "${LIBRESSL_PREFIX:?Set LIBRESSL_PREFIX to your LibreSSL install prefix}"
: "${SQLCIPHER_DIR:?Set SQLCIPHER_DIR to a sqlcipher-libressl checkout}"
: "${FOSSIL_SRC:?Set FOSSIL_SRC to a Fossil source checkout (at FOSSIL_REF=$FOSSIL_REF)}"

# Parallelism
if [ -z "${JOBS:-}" ]; then
    if command -v nproc >/dev/null 2>&1; then
        JOBS="$(nproc)"
    else
        JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 2)"
    fi
fi

mkdir -p "$OUTPUT_DIR"

# ── Sanity checks ───────────────────────────────────────────────
echo "==> Verifying inputs"
[ -f "$LIBRESSL_PREFIX/lib/libcrypto.a" ]        || { echo "ERR: $LIBRESSL_PREFIX/lib/libcrypto.a missing"; exit 1; }
[ -f "$LIBRESSL_PREFIX/lib/libssl.a" ]           || { echo "ERR: $LIBRESSL_PREFIX/lib/libssl.a missing";    exit 1; }
[ -f "$LIBRESSL_PREFIX/include/openssl/crypto.h" ] || { echo "ERR: LibreSSL headers missing under $LIBRESSL_PREFIX/include"; exit 1; }
[ -d "$SQLCIPHER_DIR" ]                          || { echo "ERR: SQLCIPHER_DIR not a directory: $SQLCIPHER_DIR"; exit 1; }
[ -d "$FOSSIL_SRC" ]                             || { echo "ERR: FOSSIL_SRC not a directory: $FOSSIL_SRC"; exit 1; }
command -v qjs >/dev/null 2>&1                   || { echo "WARN: qjs (QuickJS) not on PATH; not required to build Fossil but required to run bin/ppv against the result"; }

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
# --with-see=1 sets SQLITE3_ORIGIN=1, which makes Fossil's build look for
# src/sqlite3-see.c (not src/sqlite3.c). Drop the SQLCipher amalgamation there.
FOSSIL_SQLITE_C="$FOSSIL_SRC/src/sqlite3-see.c"
FOSSIL_SQLITE_H="$FOSSIL_SRC/src/sqlite3.h"
cp "$SQLCIPHER_DIR/sqlite3.c" "$FOSSIL_SQLITE_C"
cp "$SQLCIPHER_DIR/sqlite3.h" "$FOSSIL_SQLITE_H"

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
