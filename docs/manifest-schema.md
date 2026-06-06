# Election manifest schema

The election manifest is the genesis artifact of an election. It is committed once at election creation, clearsigned by the convener, and never modified. Its hash identifies the election across all clones, and every ballot references it.

## Format

A single JSON file at `manifest.json` in the repo root. Canonicalized (sorted keys, no insignificant whitespace, UTF-8) before hashing.

## Fields

| Field | Type | Description |
|---|---|---|
| `version` | string | Schema version. Currently `"ppp/1"`. |
| `election_id` | string | Human-readable slug. Not a trust root, just a label. |
| `title` | string | Display title. |
| `description` | string | Free text. |
| `convener` | object | `{name, pgp_fingerprint}`. The party who created and signed the manifest. |
| `voters` | array of `{name, pgp_fingerprint}` | Closed roster of eligible voters. |
| `options` | array of `{id, title, slices, price}` | Choices being voted on. `id` is a stable slug. |
| `rule` | object | See below. |
| `schedule` | object | `{voting_opens, voting_closes}`, ISO 8601 timestamps. |
| `seed` | object | Seed protocol; see below. |

### `rule`

| Field | Type | Description |
|---|---|---|
| `threshold` | object | `{type, value}`. `type` is one of `"absolute"`, `"fraction"`, `"top-k"`. |
| `allocation` | string | `"A"` (stochastic with replacement), `"B"` (stochastic without replacement), `"C"` (deterministic weighted top-M). |
| `budget` | integer | `M` in the spec — money, seats, or awards. |
| `tie_break` | string | `"random"` (uses seed), `"first"`, or `"alphabetic"`. |

### `seed`

For phase 1, two protocols are supported:

- **NIST beacon.** `{"protocol": "nist-beacon", "pulse_url": "...", "pulse_timestamp": "..."}`. Seed = SHA3-256 of the NIST randomness beacon pulse at `pulse_timestamp`. The pulse value is fetched and committed at tally time. Unpredictable until after `voting_closes`.
- **Commit-reveal.** `{"protocol": "commit-reveal", "share_deadline": "...", "reveal_deadline": "..."}`. Each voter commits `H(share)` before `share_deadline` and reveals before `reveal_deadline`. Seed = SHA3-256 of the concatenation of revealed shares in fingerprint order. Trust-minimizing but requires voter participation.

## Manifest hash

```
manifest_hash = SHA3-256(canonical_json(manifest))
```

A voter who has the wrong `manifest_hash` is voting in a different election. The hash is the cryptographic identifier of the election; the `election_id` slug is for humans.

## Example

```json
{
  "version": "ppp/1",
  "election_id": "q3-grants-2026",
  "title": "Q3 2026 community grants",
  "description": "Selecting projects to fund from the Q3 pool.",
  "convener": {
    "name": "Convener",
    "pgp_fingerprint": "0000000000000000000000000000000000000000"
  },
  "voters": [
    {"name": "Alice", "pgp_fingerprint": "AAAA...AAAA"},
    {"name": "Bob",   "pgp_fingerprint": "BBBB...BBBB"},
    {"name": "Carol", "pgp_fingerprint": "CCCC...CCCC"}
  ],
  "options": [
    {"id": "proj-foo", "title": "Foo Project", "slices": 1, "price": 5000},
    {"id": "proj-bar", "title": "Bar Project", "slices": 1, "price": 7500},
    {"id": "proj-baz", "title": "Baz Project", "slices": 1, "price": 10000}
  ],
  "rule": {
    "threshold": {"type": "absolute", "value": 2},
    "allocation": "B",
    "budget": 12500,
    "tie_break": "random"
  },
  "schedule": {
    "voting_opens": "2026-07-01T00:00:00Z",
    "voting_closes": "2026-07-15T23:59:59Z"
  },
  "seed": {
    "protocol": "nist-beacon",
    "pulse_url": "https://beacon.nist.gov/beacon/2.0/pulse/time/2026-07-16T00:00:00Z",
    "pulse_timestamp": "2026-07-16T00:00:00Z"
  }
}
```
