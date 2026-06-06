// lib/sha3.js
// SHA-3 family wrappers via shell-out to system openssl.
// Same dependency posture as the gpg shell-out: openssl is universally
// available, audited, process-isolated.

import { runForString, runForBytes } from "./shell.js";

// Returns uppercase hex digest of SHA3-256 of the given bytes (Uint8Array or string).
export function sha3_256_hex(data) {
    const out = runForString(["openssl", "dgst", "-sha3-256", "-hex"], data);
    const m = out.match(/([0-9a-fA-F]{64})/);
    if (!m) {
        throw new Error(`sha3_256_hex: cannot parse openssl output: ${out.slice(0, 100)}`);
    }
    return m[1].toUpperCase();
}

// Returns nbytes bytes of SHAKE128 output keyed by `data`.
// Used by the deterministic-sampling stream (see docs/deterministic-sampling.md).
export function shake128_bytes(data, nbytes) {
    const out = runForBytes(
        ["openssl", "dgst", "-shake128", "-xoflen", String(nbytes), "-binary"],
        data
    );
    if (out.length !== nbytes) {
        throw new Error(`shake128_bytes: openssl returned ${out.length} bytes, expected ${nbytes}`);
    }
    return out;
}
