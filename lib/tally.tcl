# lib/tally.tcl
# The voting mechanism itself: threshold filter + allocation rule.
# See ../pretty-good-pizza/README.md for the spec. The spec is the source of truth.

namespace eval ::ppp::tally {
    namespace export run
}

# ::ppp::tally::run --
#
#   Compute the election result deterministically.
#
# Arguments:
#   manifest - parsed manifest dict (already validated)
#   ballots  - list of validated ballot dicts (already filtered for validity;
#              equivocation handled before this call)
#   seed     - binary seed bytes (from manifest's seed protocol; the same input
#              must produce the same output across every implementation)
#
# Returns:
#   A dict: {
#     mode: "A" | "B" | "C"
#     selected: list of option ids (for A and B; includes repeats for A)
#     weights: dict option_id -> integer weight (for C)
#     unspent: integer remaining budget
#     trace: list of per-draw records (for verifier auditing)
#   }
#
# Shared front end:
#   1. votes(option) = sum_voter approval(voter, option)
#   2. Apply rule.threshold to zero out below-threshold options.
#
# Allocation modes A, B, and C plus the exact seed-to-draw mapping are
# specified in docs/deterministic-sampling.md. That spec is the source of
# truth for byte-level reproducibility; this implementation is a translation
# of it. In particular:
#   - Integer weight construction uses the product-of-other-prices trick to
#     stay in exact integers (no floating point at any step).
#   - Stream = SHAKE128("ppp/draw/v1" || manifest_hash || seed).
#   - Each draw consumes ceil(bits(S)/8) + 16 bytes, big-endian, mod S.
#   - Probability is proportional to votes * value (multiplication). The
#     correction from division to multiplication is documented in the spec
#     and must be preserved.
# Cross-implementation regression lives in test/fixtures/sampling/.
proc ::ppp::tally::run {manifest ballots seed} {
    error "::ppp::tally::run not implemented"
}
