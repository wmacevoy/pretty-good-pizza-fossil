# Ballot schema

A ballot is a small JSON file committed to `ballots/<voter-fingerprint>.json`. Fossil's `clearsign` setting attaches the voter's PGP signature to the manifest of the check-in containing the ballot — that signature, not anything inside the ballot file itself, is the authentication.

## Fields

| Field | Type | Description |
|---|---|---|
| `version` | string | `"ppp/1"`. |
| `election_id` | string | Matches the manifest's `election_id`. |
| `manifest_hash` | string | SHA3-256 of the election manifest. Anchors the ballot to a specific election. |
| `voter_fingerprint` | string | Uppercase hex of the voter's PGP fingerprint. Must match the `ballots/<fingerprint>.json` filename and the clearsign signer. |
| `approvals` | array of strings | Option `id`s the voter approves. May be empty. |

## Validity rules

A ballot is valid iff all of the following hold:

1. The check-in's clearsign signature verifies against `voter_fingerprint`.
2. `voter_fingerprint` is in the manifest's voter roster.
3. `manifest_hash` matches the actual manifest hash.
4. `voting_opens ≤ check-in timestamp ≤ voting_closes`.
5. Every entry in `approvals` is a real `options[].id` in the manifest.

Rules 1–5 are per-ballot. **Equivocation** — a voter committing two contradictory ballots with the same `voter_fingerprint` but different `approvals` — is detected at tally time, not per ballot. The handling is documented in `lib/tally.tcl` and must be deterministic (suggested phase-1 default: reject the voter's ballots entirely and surface for convener review).

## Example

```json
{
  "version": "ppp/1",
  "election_id": "q3-grants-2026",
  "manifest_hash": "abc123def456...",
  "voter_fingerprint": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
  "approvals": ["proj-foo", "proj-bar"]
}
```

## Why the ballot file does not carry its own signature

Fossil's clearsign feature already signs the manifest of every check-in. Adding a second signature inside the ballot JSON would duplicate the trust root and create two ways for a ballot to be "valid" — exactly the kind of ambiguity that produces incident reports. If a verifier ever needs a portable ballot artifact (e.g., for audit outside Fossil), the CLI can emit a detached `gpg --output ballot.json.asc --detach-sign` copy on demand; it is not part of the protocol.
