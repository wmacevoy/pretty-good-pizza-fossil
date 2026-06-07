/*
 * src/qjs-crypto.c
 *
 * QuickJS native module exposing the small slice of LibreSSL libcrypto that
 * Pizza Party Voting needs:
 *
 *   import { sha3_256, shake128, randomBytes } from "ppv-crypto";
 *
 *   sha3_256(data)             -> ArrayBuffer (32 bytes)
 *   shake128(data, nbytes)     -> ArrayBuffer (nbytes bytes)
 *   randomBytes(nbytes)        -> ArrayBuffer (nbytes bytes)
 *
 * `data` may be a string (UTF-8 bytes), a Uint8Array, or any TypedArray /
 * ArrayBuffer view. JS-side adapters in lib/sha3.js wrap return values in
 * Uint8Array and produce hex strings where the existing API expects them.
 *
 * This module is statically linked into the custom qjs-ppv binary by
 * build/build-qjs.sh. The corresponding registration patch against
 * vendor/quickjs/qjs.c lives at build/patches/qjs-register-ppv-crypto.patch.
 *
 * Why a native module instead of shelling out to openssl: macOS's system
 * /usr/bin/openssl is LibreSSL 3.x and supports neither SHA-3 nor SHAKE128
 * via its CLI. We already link LibreSSL 4.2.1 libcrypto for SQLCipher in the
 * fossil-ppv binary; reusing it for the QuickJS runtime eliminates one
 * external dependency and keeps the crypto provider consistent across the
 * stack. See docs/install.md for the resulting install story.
 */

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "quickjs.h"
#include "cutils.h"

#include <openssl/evp.h>
#include <openssl/rand.h>

#include "ppv-keccak.h"

/*
 * Resolve a JS value to a byte range. Accepts:
 *   - strings (uses their UTF-8 representation)
 *   - Uint8Array / other TypedArrays
 *   - ArrayBuffer
 *
 * On success returns 0 and fills *out_buf, *out_len. *str_out is non-NULL
 * iff the caller must JS_FreeCString(ctx, *str_out) after use; it stays
 * NULL for the TypedArray/ArrayBuffer paths.
 *
 * On type error returns -1 with an exception already raised on ctx.
 */
static int input_bytes(JSContext *ctx, JSValueConst val,
                       const uint8_t **out_buf, size_t *out_len,
                       const char **str_out)
{
    *str_out = NULL;

    if (JS_IsString(val)) {
        size_t len;
        const char *s = JS_ToCStringLen(ctx, &len, val);
        if (!s) return -1;
        *out_buf = (const uint8_t *)s;
        *out_len = len;
        *str_out = s;
        return 0;
    }

    /* Try TypedArray first; it covers Uint8Array which is the common case. */
    size_t byte_offset = 0, byte_length = 0;
    JSValue ab = JS_GetTypedArrayBuffer(ctx, val,
                                        &byte_offset, &byte_length, NULL);
    if (!JS_IsException(ab)) {
        size_t buf_size = 0;
        uint8_t *raw = JS_GetArrayBuffer(ctx, &buf_size, ab);
        JS_FreeValue(ctx, ab);
        if (raw && byte_offset + byte_length <= buf_size) {
            *out_buf = raw + byte_offset;
            *out_len = byte_length;
            return 0;
        }
    } else {
        /* Not a TypedArray; clear the pending exception and fall through. */
        JS_FreeValue(ctx, JS_GetException(ctx));
    }

    /* Try plain ArrayBuffer. */
    size_t buf_size = 0;
    uint8_t *raw = JS_GetArrayBuffer(ctx, &buf_size, val);
    if (raw) {
        *out_buf = raw;
        *out_len = buf_size;
        return 0;
    }
    /* Clear the second pending exception from the ArrayBuffer probe. */
    JS_FreeValue(ctx, JS_GetException(ctx));

    JS_ThrowTypeError(ctx,
        "expected string, TypedArray, or ArrayBuffer");
    return -1;
}

static JSValue js_sha3_256(JSContext *ctx, JSValueConst this_val,
                           int argc, JSValueConst *argv)
{
    if (argc < 1)
        return JS_ThrowTypeError(ctx, "sha3_256: missing argument");

    const uint8_t *in;
    size_t in_len;
    const char *str_to_free;
    if (input_bytes(ctx, argv[0], &in, &in_len, &str_to_free) < 0)
        return JS_EXCEPTION;

    JSValue ret = JS_EXCEPTION;
    EVP_MD_CTX *md = EVP_MD_CTX_new();
    if (!md) {
        JS_ThrowOutOfMemory(ctx);
        goto out;
    }

    uint8_t digest[32];
    unsigned int outlen = sizeof digest;
    if (!EVP_DigestInit_ex(md, EVP_sha3_256(), NULL) ||
        !EVP_DigestUpdate(md, in, in_len) ||
        !EVP_DigestFinal_ex(md, digest, &outlen) ||
        outlen != sizeof digest) {
        JS_ThrowInternalError(ctx, "sha3_256: libcrypto digest failed");
        goto out;
    }

    ret = JS_NewArrayBufferCopy(ctx, digest, sizeof digest);

out:
    if (md) EVP_MD_CTX_free(md);
    if (str_to_free) JS_FreeCString(ctx, str_to_free);
    return ret;
}

static JSValue js_shake128(JSContext *ctx, JSValueConst this_val,
                           int argc, JSValueConst *argv)
{
    if (argc < 2)
        return JS_ThrowTypeError(ctx,
            "shake128: expected (data, nbytes)");

    const uint8_t *in;
    size_t in_len;
    const char *str_to_free;
    if (input_bytes(ctx, argv[0], &in, &in_len, &str_to_free) < 0)
        return JS_EXCEPTION;

    int64_t nbytes;
    if (JS_ToInt64(ctx, &nbytes, argv[1]) < 0) {
        if (str_to_free) JS_FreeCString(ctx, str_to_free);
        return JS_EXCEPTION;
    }
    /*
     * Upper bound is generous (1 GiB). The deterministic-sampling stream
     * consumes a few KiB at most for realistic elections; cap exists to
     * prevent accidental enormous allocations from a buggy caller.
     */
    if (nbytes <= 0 || nbytes > (int64_t)(1 << 30)) {
        if (str_to_free) JS_FreeCString(ctx, str_to_free);
        return JS_ThrowRangeError(ctx,
            "shake128: nbytes must be in (0, 2^30]");
    }

    uint8_t *out = js_malloc(ctx, (size_t)nbytes);
    if (!out) {
        if (str_to_free) JS_FreeCString(ctx, str_to_free);
        return JS_EXCEPTION;
    }

    /* LibreSSL 4.2.1's libcrypto doesn't expose SHAKE / XOF at all (no
     * EVP_shake128, no EVP_DigestFinalXOF, no NID), so this path uses our
     * own Keccak-f[1600] + SHAKE128 sponge in src/ppv-keccak.c. SHA-3-256
     * above stays on EVP_sha3_256() since LibreSSL does ship that. */
    ppv_shake128(in, in_len, out, (size_t)nbytes);
    JSValue ret = JS_NewArrayBufferCopy(ctx, out, (size_t)nbytes);

    js_free(ctx, out);
    if (str_to_free) JS_FreeCString(ctx, str_to_free);
    return ret;
}

static JSValue js_random_bytes(JSContext *ctx, JSValueConst this_val,
                               int argc, JSValueConst *argv)
{
    if (argc < 1)
        return JS_ThrowTypeError(ctx, "randomBytes: missing argument");

    int64_t nbytes;
    if (JS_ToInt64(ctx, &nbytes, argv[0]) < 0)
        return JS_EXCEPTION;
    /* 1 MiB cap is plenty for our use (32-byte master keys) and protects
     * against accidental large allocations. */
    if (nbytes <= 0 || nbytes > (int64_t)(1 << 20))
        return JS_ThrowRangeError(ctx,
            "randomBytes: nbytes must be in (0, 2^20]");

    uint8_t *out = js_malloc(ctx, (size_t)nbytes);
    if (!out) return JS_EXCEPTION;

    JSValue ret = JS_EXCEPTION;
    if (RAND_bytes(out, (int)nbytes) != 1) {
        JS_ThrowInternalError(ctx, "randomBytes: RAND_bytes failed");
        goto out_rand;
    }
    ret = JS_NewArrayBufferCopy(ctx, out, (size_t)nbytes);

out_rand:
    js_free(ctx, out);
    return ret;
}

/* ──────────────────────── module registration ──────────────────────── */

static const JSCFunctionListEntry ppv_crypto_funcs[] = {
    JS_CFUNC_DEF("sha3_256",    1, js_sha3_256),
    JS_CFUNC_DEF("shake128",    2, js_shake128),
    JS_CFUNC_DEF("randomBytes", 1, js_random_bytes),
};

static int ppv_crypto_init(JSContext *ctx, JSModuleDef *m)
{
    return JS_SetModuleExportList(ctx, m, ppv_crypto_funcs,
                                  countof(ppv_crypto_funcs));
}

JSModuleDef *js_init_module_ppv_crypto(JSContext *ctx, const char *module_name)
{
    JSModuleDef *m = JS_NewCModule(ctx, module_name, ppv_crypto_init);
    if (!m) return NULL;
    JS_AddModuleExportList(ctx, m, ppv_crypto_funcs,
                           countof(ppv_crypto_funcs));
    return m;
}
