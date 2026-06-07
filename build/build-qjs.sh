#!/usr/bin/env bash
set -euo pipefail

# Build a custom qjs binary (qjs-ppv) with src/qjs-crypto.c statically linked
# against LibreSSL libcrypto, so JS code can `import { sha3_256, shake128,
# randomBytes } from "ppv-crypto"` in-process — no openssl on PATH.
#
# Assumes LibreSSL has already been built by build/build-fossil.sh (or that
# the user pointed LIBRESSL_PREFIX at an external prefix containing libcrypto.a
# and the OpenSSL-compatible headers).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR/dist}"

# shellcheck source=./versions.env
. "$SCRIPT_DIR/versions.env"

: "${LIBRESSL_PREFIX:=$REPO_ROOT/vendor/libressl-build-out}"
: "${QUICKJS_SRC:=$REPO_ROOT/vendor/quickjs}"

if [ -z "${JOBS:-}" ]; then
    if command -v nproc >/dev/null 2>&1; then JOBS="$(nproc)"
    else JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 2)"; fi
fi

mkdir -p "$OUTPUT_DIR"

# ── Sanity checks ───────────────────────────────────────────────
echo "==> Verifying inputs"
[ -f "$LIBRESSL_PREFIX/lib/libcrypto.a" ] || {
    echo "ERR: $LIBRESSL_PREFIX/lib/libcrypto.a missing"
    echo "     run build/build-fossil.sh first to produce LibreSSL, or set LIBRESSL_PREFIX"
    exit 1
}
[ -f "$LIBRESSL_PREFIX/include/openssl/evp.h" ] || {
    echo "ERR: LibreSSL headers missing under $LIBRESSL_PREFIX/include"
    exit 1
}
[ -d "$QUICKJS_SRC" ] || {
    echo "ERR: vendor/quickjs missing (did you 'git submodule update --init'?)"
    exit 1
}

PATCH="$SCRIPT_DIR/patches/qjs-register-ppv-crypto.patch"
[ -f "$PATCH" ] || { echo "ERR: $PATCH missing"; exit 1; }

# ── Step 1: apply the registration patch ───────────────────────
# Reset the vendor tree first so re-runs don't double-apply or fail.
echo "==> Applying qjs registration patch"
(
    cd "$QUICKJS_SRC"
    git checkout -- qjs.c 2>/dev/null || true
    patch -p1 < "$PATCH"
)

# ── Step 2: build the QuickJS object files via its own Makefile ─
# Build only the .o files, not the qjs binary — the link would fail
# because the patched qjs.c references our symbol that isn't built yet.
QJS_OBJ_FILES=(
    .obj/qjs.o
    .obj/repl.o
    .obj/quickjs.o
    .obj/dtoa.o
    .obj/libregexp.o
    .obj/libunicode.o
    .obj/cutils.o
    .obj/quickjs-libc.o
)
echo "==> Building QuickJS objects"
make -C "$QUICKJS_SRC" -j"$JOBS" "${QJS_OBJ_FILES[@]}" >/dev/null

# ── Step 3: compile src/qjs-crypto.c against quickjs + libcrypto ─
echo "==> Compiling src/qjs-crypto.c"
TMP_OBJ="$QUICKJS_SRC/.obj/qjs-crypto.o"
cc -O2 -Wall -Wno-unused-parameter \
   -I"$QUICKJS_SRC" \
   -I"$LIBRESSL_PREFIX/include" \
   -c "$REPO_ROOT/src/qjs-crypto.c" \
   -o "$TMP_OBJ"

# ── Step 4: link qjs-ppv ────────────────────────────────────────
echo "==> Linking qjs-ppv"
cc -O2 -o "$OUTPUT_DIR/qjs-ppv" \
    "$QUICKJS_SRC/.obj/qjs.o" \
    "$QUICKJS_SRC/.obj/repl.o" \
    "$QUICKJS_SRC/.obj/quickjs.o" \
    "$QUICKJS_SRC/.obj/dtoa.o" \
    "$QUICKJS_SRC/.obj/libregexp.o" \
    "$QUICKJS_SRC/.obj/libunicode.o" \
    "$QUICKJS_SRC/.obj/cutils.o" \
    "$QUICKJS_SRC/.obj/quickjs-libc.o" \
    "$TMP_OBJ" \
    "$LIBRESSL_PREFIX/lib/libcrypto.a" \
    -lm -lpthread

# Restore vendor/quickjs to its pristine pinned state so the submodule's
# working tree stays clean (the patch only needs to live during the build).
(cd "$QUICKJS_SRC" && git checkout -- qjs.c)
rm -f "$TMP_OBJ"

# ── Step 5: smoke test ──────────────────────────────────────────
echo "==> Smoke test"
SMOKE=$(mktemp /tmp/ppv-qjs-smoke.XXXXXX.js)
cat > "$SMOKE" <<'JS'
import { sha3_256, shake128, randomBytes } from "ppv-crypto";

function hex(buf) {
    return Array.from(new Uint8Array(buf))
        .map(b => b.toString(16).padStart(2, "0")).join("");
}

// Known SHA3-256("") = a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a
const h = hex(sha3_256(""));
if (h !== "a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a") {
    console.log("FAIL sha3_256(''):", h);
    throw new Error("sha3_256 mismatch");
}
console.log("ok sha3_256");

// SHAKE128 of any input must return the requested number of bytes.
const xof = shake128("hello", 17);
if (xof.byteLength !== 17) {
    console.log("FAIL shake128 length:", xof.byteLength);
    throw new Error("shake128 length mismatch");
}
console.log("ok shake128");

// randomBytes returns the right length.
const rb = randomBytes(32);
if (rb.byteLength !== 32) {
    console.log("FAIL randomBytes length:", rb.byteLength);
    throw new Error("randomBytes length mismatch");
}
console.log("ok randomBytes");
JS
"$OUTPUT_DIR/qjs-ppv" "$SMOKE"
rm -f "$SMOKE"

echo "==> Build complete: $OUTPUT_DIR/qjs-ppv"
ls -lh "$OUTPUT_DIR/qjs-ppv"
