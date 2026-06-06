# lib/manifest.tcl
# Election manifest: load, validate, canonical hash.
# See docs/manifest-schema.md for the schema.

namespace eval ::ppp::manifest {
    namespace export load validate canonical_hash
}

proc ::ppp::manifest::load {path} {
    # Read manifest JSON from disk, return a Tcl dict.
    # Uses tcllib's json::json2dict.
    error "::ppp::manifest::load not implemented"
}

proc ::ppp::manifest::validate {manifest} {
    # Enforce schema:
    #   - version == "ppp/1"
    #   - election_id, title, description are non-empty strings
    #   - convener has name + uppercase-hex pgp_fingerprint
    #   - voters is non-empty list of {name, pgp_fingerprint}; fingerprints unique
    #   - options is non-empty list of {id, title, slices, price}; ids unique;
    #     slices and price are positive integers
    #   - rule.allocation in {A, B, C}
    #   - rule.threshold.type in {absolute, fraction, top-k} and value sane for type
    #   - rule.budget is a positive integer
    #   - rule.tie_break in {random, first, alphabetic}
    #   - schedule.voting_opens < schedule.voting_closes (ISO 8601 parseable)
    #   - seed.protocol in {nist-beacon, commit-reveal} with required fields
    # Throws on first invalid field with a human-readable message.
    error "::ppp::manifest::validate not implemented"
}

proc ::ppp::manifest::canonical_hash {manifest} {
    # Serialize the manifest dict per docs/canonical-json.md (RFC 8785 JCS,
    # restricted to the integer/string/boolean/array/object subset), then return
    # uppercase hex of SHA3-256 of those bytes.
    #
    # The byte-exact rules live in docs/canonical-json.md, not in this file.
    # If two implementations disagree on the hash, consult that spec and the
    # regression fixture in test/fixtures/canonical-json/.
    error "::ppp::manifest::canonical_hash not implemented"
}
