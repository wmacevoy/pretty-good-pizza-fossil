/*
 * src/ppv-keccak.c
 *
 * Keccak-f[1600] permutation + SHAKE128 sponge per NIST FIPS 202.
 * Public domain (the Keccak permutation and sponge construction themselves
 * are by the Keccak team; this is a clean-room implementation following the
 * standard's prose).
 *
 * Assumes little-endian host (true for all targets we support: x86_64,
 * arm64, RISC-V). The Keccak lane convention treats each 64-bit lane's
 * bytes as little-endian, so on a LE host we can XOR input bytes directly
 * into the state's byte view without swapping. On a hypothetical BE port,
 * absorb/squeeze would need explicit byte swaps around keccak_f().
 */

#include "ppv-keccak.h"

#include <stdint.h>
#include <string.h>

#define KECCAK_ROUNDS 24
#define SHAKE128_RATE_BYTES 168   /* 1344 bits, capacity = 256 bits */

/* Round constants (RC[r]) — FIPS 202 §3.2.5 / Table 1. */
static const uint64_t RC[KECCAK_ROUNDS] = {
    0x0000000000000001ULL, 0x0000000000008082ULL,
    0x800000000000808AULL, 0x8000000080008000ULL,
    0x000000000000808BULL, 0x0000000080000001ULL,
    0x8000000080008081ULL, 0x8000000000008009ULL,
    0x000000000000008AULL, 0x0000000000000088ULL,
    0x0000000080008009ULL, 0x000000008000000AULL,
    0x000000008000808BULL, 0x800000000000008BULL,
    0x8000000000008089ULL, 0x8000000000008003ULL,
    0x8000000000008002ULL, 0x8000000000000080ULL,
    0x000000000000800AULL, 0x800000008000000AULL,
    0x8000000080008081ULL, 0x8000000000008080ULL,
    0x0000000080000001ULL, 0x8000000080008008ULL
};

/* Rotation offsets for ρ (rho) over the lane traversal used below. */
static const int RHO[24] = {
     1,  3,  6, 10, 15, 21, 28, 36, 45, 55,  2, 14,
    27, 41, 56,  8, 25, 43, 62, 18, 39, 61, 20, 44
};

/* Lane permutation indices for π (pi) — same traversal as RHO. */
static const int PI[24] = {
    10,  7, 11, 17, 18,  3,  5, 16,  8, 21, 24,  4,
    15, 23, 19, 13, 12,  2, 20, 14, 22,  9,  6,  1
};

static inline uint64_t rotl64(uint64_t x, int n) {
    return (x << n) | (x >> (64 - n));
}

static void keccak_f1600(uint64_t s[25]) {
    uint64_t bc[5];
    for (int r = 0; r < KECCAK_ROUNDS; r++) {
        /* θ (theta): column parity, then mix neighboring columns. */
        for (int x = 0; x < 5; x++) {
            bc[x] = s[x] ^ s[x+5] ^ s[x+10] ^ s[x+15] ^ s[x+20];
        }
        for (int x = 0; x < 5; x++) {
            uint64_t t = bc[(x + 4) % 5] ^ rotl64(bc[(x + 1) % 5], 1);
            for (int y = 0; y < 25; y += 5) {
                s[x + y] ^= t;
            }
        }

        /* ρ (rho) and π (pi) combined: walk a 24-lane cycle, rotating and
         * permuting in one pass. */
        uint64_t t = s[1];
        for (int i = 0; i < 24; i++) {
            int j = PI[i];
            uint64_t tmp = s[j];
            s[j] = rotl64(t, RHO[i]);
            t = tmp;
        }

        /* χ (chi): nonlinear step, applied per row of five lanes. */
        for (int y = 0; y < 25; y += 5) {
            for (int x = 0; x < 5; x++) bc[x] = s[y + x];
            for (int x = 0; x < 5; x++) {
                s[y + x] ^= (~bc[(x + 1) % 5]) & bc[(x + 2) % 5];
            }
        }

        /* ι (iota): XOR a round constant into lane 0. */
        s[0] ^= RC[r];
    }
}

void ppv_shake128(const uint8_t *in, size_t in_len,
                  uint8_t *out, size_t out_len)
{
    uint64_t state[25] = {0};
    uint8_t *sb = (uint8_t *)state;
    const size_t rate = SHAKE128_RATE_BYTES;

    /* Absorb full rate-sized blocks. */
    while (in_len >= rate) {
        for (size_t i = 0; i < rate; i++) sb[i] ^= in[i];
        keccak_f1600(state);
        in += rate;
        in_len -= rate;
    }

    /* Absorb the final partial block, then apply the SHAKE padding rule.
     * FIPS 202 §6.2: pad with 1111_1 || 0* || 1, which after concatenation
     * with the SHA-3 vs SHAKE domain separator (1111 for SHAKE) becomes:
     *   first padding byte: 0x1F  (binary 0001 1111: 1 0 1 1 1 0 0 0
     *     in lane-byte LSB-first order = the SHAKE marker plus pad-start)
     *   last  padding byte (rate-1): 0x80  (the closing 1 bit). */
    for (size_t i = 0; i < in_len; i++) sb[i] ^= in[i];
    sb[in_len] ^= 0x1F;
    sb[rate - 1] ^= 0x80;

    /* Squeeze. The standard's sponge calls f BEFORE reading squeeze bytes,
     * so we permute first inside the loop. */
    while (out_len > 0) {
        keccak_f1600(state);
        size_t n = out_len < rate ? out_len : rate;
        memcpy(out, sb, n);
        out += n;
        out_len -= n;
    }
}
