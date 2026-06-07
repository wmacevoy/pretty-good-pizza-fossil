/*
 * src/ppv-keccak.h
 *
 * Minimal SHAKE128 declaration for qjs-crypto.c.
 *
 * Filling the gap that LibreSSL 4.2.1's libcrypto leaves open: it ships
 * SHA-3 (EVP_sha3_256 etc.) but no SHAKE / XOF. We provide our own
 * SHAKE128 here, used by lib/tally.js's seeded sampling stream.
 *
 * SHA-3-256 in qjs-crypto.c stays on LibreSSL's EVP for the audit-pedigree
 * win; only the XOF that LibreSSL omits is reimplemented.
 */

#ifndef PPV_KECCAK_H
#define PPV_KECCAK_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * SHAKE128 extendable-output function, FIPS 202.
 *
 *   in       input message bytes
 *   in_len   length of input in bytes
 *   out      output buffer (must be at least out_len bytes)
 *   out_len  number of output bytes requested
 *
 * Standard NIST KAT: ppv_shake128("", 0, out, 32) =
 *   7f 9c 2b a4 e8 8f 82 7d 61 60 45 50 76 05 85 3e
 *   d7 3b 80 93 f6 ef bc 88 eb 1a 6e ac fa 66 ef 26
 */
void ppv_shake128(const uint8_t *in, size_t in_len,
                  uint8_t *out, size_t out_len);

#ifdef __cplusplus
}
#endif

#endif /* PPV_KECCAK_H */
