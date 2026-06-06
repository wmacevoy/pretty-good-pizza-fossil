#!/usr/bin/env bash
set -euo pipefail

# Build a custom Fossil binary with:
#   - SQLCipher (encrypted SQLite) via the sibling sqlcipher-libressl project
#   - LibreSSL for libcrypto (storage encryption) and libssl (TLS for sync)
#   - Full Tcl 8.6 linked in (--with-tcl)
#
# Modeled on ../sqlcipher-libressl/build-sqlcipher-libressl.sh.
# Read build/README.md before running. The TODO blocks below mark steps
# that need to be pinned against a specific Fossil revision; the script
# is a skeleton, not yet a reproducible recipe.
#
# Required env:
#   LIBRESSL_PREFIX   install prefix containing include/ and lib/{libcrypto.a,libssl.a}
#   SQLCIPHER_DIR     path to a sqlcipher-libressl checkout (sibling project)
#   TCL_PREFIX        install prefix containing include/tcl.h and lib/libtcl8.6.a
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
: "${TCL_PREFIX:?Set TCL_PREFIX to your Tcl 8.6 install prefix}"
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
[ -f "$TCL_PREFIX/include/tcl.h" ]               || { echo "ERR: tcl.h missing under $TCL_PREFIX/include"; exit 1; }
ls "$TCL_PREFIX/lib/libtcl8.6.a" "$TCL_PREFIX/lib/libtcl.a" >/dev/null 2>&1 \
                                                 || { echo "ERR: no static Tcl library found under $TCL_PREFIX/lib"; exit 1; }
[ -d "$FOSSIL_SRC" ]                             || { echo "ERR: FOSSIL_SRC not a directory: $FOSSIL_SRC"; exit 1; }

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
#
# TODO(fossil-source-layout): verify the exact path Fossil expects for its
# bundled SQLite amalgamation against the pinned FOSSIL_REF. As of recent
# Fossil trunks, it lives at src/sqlite3.c, but this has shifted historically.
# Cross-check by inspecting "$FOSSIL_SRC/src/" before relying on this.
#
FOSSIL_SQLITE_C="$FOSSIL_SRC/src/sqlite3.c"
FOSSIL_SQLITE_H="$FOSSIL_SRC/src/sqlite3.h"
cp "$SQLCIPHER_DIR/sqlite3.c" "$FOSSIL_SQLITE_C"
cp "$SQLCIPHER_DIR/sqlite3.h" "$FOSSIL_SQLITE_H"

#
# TODO(db-key-wiring): Fossil's db_open path (src/db.c) needs a small patch
# to be MODE-AWARE per the manifest's rule.privacy field:
#   - rule.privacy == "public":  skip PRAGMA key entirely (stock SQLite behavior)
#   - rule.privacy == "group":   shell out to
#                                `gpg --decrypt --output - keys/master.key.asc`
#                                (no --batch; gpg-agent handles prompts), recover K,
#                                then PRAGMA key = "x'<K hex>'"; zeroize K.
#   - rule.privacy == "individual": error (deferred to a future phase)
# Also honor FOSSIL_PPP_KEY env var as a mode-2 escape hatch (testing only).
# Full design is in docs/threat-model.md (now Pinned).
#
if [ -f "$SCRIPT_DIR/patches/fossil-db-key.patch" ]; then
    echo "  applying fossil-db-key.patch"
    ( cd "$FOSSIL_SRC" && patch -p1 < "$SCRIPT_DIR/patches/fossil-db-key.patch" )
else
    echo "  WARN: patches/fossil-db-key.patch absent — built binary will not call PRAGMA key"
fi

# ── Step 3: Configure Fossil ────────────────────────────────────
echo "==> Configuring Fossil"
# Configure flags verified against Fossil $FOSSIL_VERSION auto.def.
#   --with-openssl=<prefix>    same flag for OpenSSL or LibreSSL; Fossil
#                              probes for libcrypto/libssl symbols at
#                              configure time
#   --with-tcl=<prefix>        Tcl install prefix; combined with --with-tcl-stubs
#                              gives the linked-Tcl interpreter
#   --json                     enables Fossil's JSON HTTP API endpoints
#   --internal-sqlite=1        explicit; we substitute the bundled amalgamation
#                              rather than linking an external SQLite
(
    cd "$FOSSIL_SRC"
    ./configure \
        --with-openssl="$LIBRESSL_PREFIX" \
        --with-tcl="$TCL_PREFIX" \
        --with-tcl-stubs \
        --json \
        --internal-sqlite=1 \
        CFLAGS="-DSQLITE_HAS_CODEC -DSQLCIPHER_CRYPTO_OPENSSL -O2" \
        LIBS="$LIBRESSL_PREFIX/lib/libssl.a $LIBRESSL_PREFIX/lib/libcrypto.a"
)

# ── Step 4: Build ───────────────────────────────────────────────
echo "==> Building Fossil"
make -C "$FOSSIL_SRC" -j"$JOBS"

# ── Step 5: Install ─────────────────────────────────────────────
echo "==> Installing to $OUTPUT_DIR"
cp "$FOSSIL_SRC/fossil" "$OUTPUT_DIR/fossil-ppp"
ls -lh "$OUTPUT_DIR/fossil-ppp"

# ── Step 6: Smoke test ──────────────────────────────────────────
echo "==> Smoke tests"
"$OUTPUT_DIR/fossil-ppp" version
# TODO(smoke-test-tcl): pick a real Tcl-integration smoke test once the
# command set is known. `fossil test-th-eval` exercises TH1, not full Tcl.
# Full Tcl in Fossil is reached via the (server-side) Tcl interpreter,
# which we'll exercise differently.

echo "==> Build complete"
