# Deterministic sampling

This spec defines the exact procedure for converting a seed into the sequence of draws used by the stochastic allocation modes. Determinism is required: `ppp verify` re-runs this procedure from public inputs and must produce the same output byte-for-byte.

## Inputs

- `seed`: raw bytes produced by the manifest's seed protocol (NIST beacon pulse value, or the concatenation of revealed commit-reveal shares).
- `manifest_hash`: the manifest hash as raw bytes (the uppercase hex of `manifest_hash` decoded to bytes).
- The validated ballot set, used to compute integer weights.

## Stream construction

The draw stream is **SHAKE128** seeded with a domain-separated context:

```
stream = SHAKE128(domain || manifest_hash || seed)
```

where `domain` is the ASCII bytes `ppp/draw/v1` (11 bytes, no terminator). `||` is byte concatenation.

Rationale:

- SHAKE128 is the SHA-3 extendable-output function. Since the protocol already requires SHA3-256 for `manifest_hash`, no new primitive is introduced.
- The `domain` label binds the stream to this protocol version. A future `ppp/draw/v2` produces a different stream from the same seed.
- `manifest_hash` binds the stream to this specific election. A leaked seed from one election cannot be reused to pre-compute draws for another.

## Weight construction

For allocation modes A and B, the unnormalized probability of each candidate is:

```
P(option) ∝ votes(option) × slices(option) / price(option)
```

To stay in exact integers and avoid floating-point divergence between implementations, weights are computed as:

```
weight(option) = votes(option) × slices(option) × (∏_{j in candidates, j ≠ option} price(j))
```

— that is, multiply through by the product of every other candidate's price, clearing all denominators simultaneously. The result is an integer proportional to the true rational probability, with relative ratios preserved exactly.

Every standard implementation (Tcl 8.5+, Python, Go, JavaScript with `BigInt`, Java with `BigInteger`) has arbitrary-precision integers; this places no special burden on verifiers.

For phase-1 elections (≤ 50 options, prices bounded by the natural problem size) the integers stay reasonable. If a future use case violates this assumption, the spec should be revised to use an explicit rational-number representation rather than ad-hoc floating point.

After the threshold filter, below-threshold options have `votes = 0`, so their weight is `0` and they cannot be drawn — no special handling is needed.

## Per-draw procedure

For each draw:

1. Build the candidate set (mode-specific; see below).
2. Compute integer weights as in "Weight construction."
3. Let `S` = sum of weights. If `S == 0` (every candidate has zero weight), terminate the loop: no further selections can be made.
4. Let `bits` = the bit length of `S` (`floor(log2(S)) + 1`, or 1 if `S == 1`).
5. Let `N` = `ceil(bits / 8) + 16`. The 16 bytes (128 bits) of headroom keep the bias of modular reduction below `2^-128`, which is cryptographically negligible.
6. Consume the next `N` bytes from `stream`. Interpret them as a big-endian unsigned integer `R`.
7. Compute `r = R mod S`.
8. Walk the cumulative prefix sums of the weights in the manifest's `options` order. The selected option is the first one whose prefix sum strictly exceeds `r`.

Stream bytes are consumed left-to-right and never reused; a later draw cannot read bytes that an earlier draw consumed.

## Mode A: stochastic with replacement

```
selected ← []
M ← rule.budget
loop:
    candidates ← { option : votes(option) > 0 AND price(option) ≤ M }
    if candidates is empty: break
    weights ← weight(option) for option in candidates
    if sum(weights) == 0: break
    draw using per-draw procedure
    append drawn option to selected
    M ← M − price(drawn)
return {selected, unspent: M}
```

The same option may be drawn repeatedly.

## Mode B: stochastic without replacement

Same as mode A, but the drawn option is also removed from the candidate set permanently before the next iteration. Loop terminates when the budget is exhausted or no remaining candidate satisfies `price ≤ M`.

## Mode C: deterministic weighted top-M

Mode C does **not** consume the draw stream for option selection. Procedure:

1. After threshold filtering, sort candidates by `votes(option)` descending.
2. Take the first `M = rule.budget` options. (`M` is the number of seats.)
3. Each selected option carries voting weight equal to its `votes(option)`.

Tie-breaking applies when two candidates straddle the cutoff at position `M` with equal `votes` (see below). Tie-breaking is the only step in mode C that can consume the draw stream, and only if `tie_break == "random"`.

## Tie-breaking

When two or more options are tied on the relevant ordering key:

- `tie_break = "first"`: keep the one that appears earlier in the manifest's `options` array (input order).
- `tie_break = "alphabetic"`: keep the one whose `id` sorts earlier by UCS code point.
- `tie_break = "random"`: invoke the per-draw procedure with weights `1` for each tied option. The draw stream is shared with modes A/B; the stream construction does not depend on the allocation mode, so re-running with the same seed always re-resolves ties identically.

## Cross-implementation regression fixture

`test/fixtures/sampling/` will contain frozen `(seed, manifest, ballots)` triples and the expected output for each allocation mode. Any implementation must reproduce the documented output byte-for-byte. The fixture is the source of truth for spec compliance disputes.
