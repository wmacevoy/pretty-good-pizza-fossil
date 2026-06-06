# lib/ballot.tcl
# Ballot file: load, validate (per-ballot rules only).
# Equivocation detection is the tally layer's job, not this one.
# See docs/ballot-schema.md.

namespace eval ::ppp::ballot {
    namespace export load validate
}

proc ::ppp::ballot::load {path} {
    # Read ballot JSON from disk, return a Tcl dict.
    error "::ppp::ballot::load not implemented"
}

proc ::ppp::ballot::validate {ballot manifest manifest_hash signer_fingerprint check_in_time} {
    # Apply rules 1-5 from docs/ballot-schema.md:
    #   1. signer_fingerprint matches ballot.voter_fingerprint
    #   2. voter_fingerprint is in manifest.voters
    #   3. ballot.manifest_hash == manifest_hash
    #   4. manifest.schedule.voting_opens <= check_in_time <= voting_closes
    #   5. every approvals[i] is a real option id in manifest.options
    #
    # check_in_time is the Fossil check-in timestamp (UTC). The caller is
    # responsible for plumbing it in from `fossil json timeline` or similar;
    # do not read clock here, since clock-at-validation is not the same as
    # clock-at-check-in.
    #
    # Throws on first violation. Returns silently on valid ballot.
    error "::ppp::ballot::validate not implemented"
}
