// lib/sha3.js
// SHA-3 family wrappers using the qjs-ppv native module.
//
// The `ppv-crypto` module is statically linked into qjs-ppv (built by
// build/build-qjs.sh). It provides:
//   - sha3_256: LibreSSL libcrypto's EVP_sha3_256 (audited upstream).
//   - shake128: vendored Keccak-f[1600] + SHAKE128 sponge in src/ppv-keccak.c
//     (LibreSSL doesn't expose SHAKE; verified byte-identical to OpenSSL's
//     SHAKE128 in the build's parity tests).
//
// Both accept strings (UTF-8 bytes) or Uint8Array/ArrayBuffer and return
// ArrayBuffer. This module wraps them in the {hex string} / {Uint8Array}
// shapes the rest of the codebase expects.

import { sha3_256, shake128 } from "ppv-crypto";

function bytesToHex(buf) {
    return Array.from(new Uint8Array(buf))
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
}

// Returns uppercase hex digest of SHA3-256 of the given bytes (Uint8Array or string).
export function sha3_256_hex(data) {
    return bytesToHex(sha3_256(data)).toUpperCase();
}

// Returns nbytes bytes of SHAKE128 output keyed by `data`.
// Used by the deterministic-sampling stream (see docs/deterministic-sampling.md).
export function shake128_bytes(data, nbytes) {
    return new Uint8Array(shake128(data, nbytes));
}
