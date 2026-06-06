// lib/tally.js
// The voting mechanism itself: threshold filter + allocation rule.
// See ../pretty-good-pizza/README.md for the algorithm (the spec is the
// source of truth) and docs/deterministic-sampling.md for the exact seed-to-draw
// procedure (SHAKE128 stream, integer weights via product-of-other-prices,
// per-draw byte budget for ≤ 2^-128 bias).
//
// Probability formula is votes × value (multiplication). Earlier spec drafts
// had division; that was corrected and the multiplication is intentional.
//
// Integer weights live in BigInt to avoid floating-point divergence between
// implementations.

// run --
//   manifest: parsed manifest (already validated)
//   ballots:  array of validated ballot objects
//   seed:     Uint8Array of seed bytes from the manifest's seed protocol
// returns:
//   { mode, selected: [option_id...], weights: {option_id: weight}, unspent, trace }
export function run(manifest, ballots, seed) {
    throw new Error("tally.run: not implemented");
}
