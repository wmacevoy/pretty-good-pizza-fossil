# Walkthrough: Alice, Bob, and Carol plan a surprise party

A worked example. Alice, Bob, and Carol are throwing a surprise birthday party for their friend Dave. They have $50 to spend on decorations and they want to actually agree on what to buy — without one person railroading the others, and with the result being checkable after the fact ("wait, why did we end up with a piñata?").

The decoration options they're considering:

| id | item | slices | price |
|---|---|---|---|
| `balloons` | A bag of helium balloons | 1 | $10 |
| `streamers` | Crepe-paper streamers | 1 | $8 |
| `banner` | "Happy birthday Dave" banner | 1 | $15 |
| `photo-booth` | Photo booth with props | 1 | $25 |
| `fairy-lights` | String of fairy lights | 1 | $20 |
| `pinata` | Birthday piñata | 1 | $30 |

This is a single-instance allocation (you buy one piñata, not two), so they'll use **mode B** (stochastic, without replacement): each item gets at most one slot in the final shopping list, and the order of selection is weighted by how many people approved it.

## Before they start

Each of them has a PGP keypair already (it's their identity for the protocol). They've exchanged fingerprints over a side channel — text, signal, in person — so Alice can put them in the manifest.

Alice's keyring shows her fingerprint:

```
$ gpg --list-secret-keys --with-colons | awk -F: '/^fpr/{print $10; exit}'
A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1
```

Bob and Carol do the same and send Alice their fingerprints. (For this walkthrough we'll use repeating-letter fingerprints to keep it readable; real fingerprints are 40 hex characters.)

## Step 1 — Alice drafts the manifest

Alice creates `manifest.json` in a fresh directory:

```json
{
  "version": "ppv/1",
  "election_id": "daves-surprise-party",
  "title": "Decorations for Dave's surprise party",
  "description": "Pick decorations within a $50 budget. Mode B without replacement so we don't double up.",
  "convener": {
    "name": "Alice",
    "pgp_fingerprint": "A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1"
  },
  "voters": [
    {"name": "Alice", "pgp_fingerprint": "A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1"},
    {"name": "Bob",   "pgp_fingerprint": "B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0"},
    {"name": "Carol", "pgp_fingerprint": "CA40CA40CA40CA40CA40CA40CA40CA40CA40CA40"}
  ],
  "options": [
    {"id": "balloons",     "title": "Helium balloons",     "slices": 1, "price": 10},
    {"id": "streamers",    "title": "Crepe streamers",     "slices": 1, "price": 8},
    {"id": "banner",       "title": "Happy birthday banner","slices": 1, "price": 15},
    {"id": "photo-booth",  "title": "Photo booth + props", "slices": 1, "price": 25},
    {"id": "fairy-lights", "title": "Fairy lights",        "slices": 1, "price": 20},
    {"id": "pinata",       "title": "Birthday piñata",     "slices": 1, "price": 30}
  ],
  "rule": {
    "threshold": {"type": "absolute", "value": 1},
    "allocation": "B",
    "budget": 50,
    "tie_break": "random",
    "privacy": "public"
  },
  "schedule": {
    "voting_opens":  "2026-06-01T00:00:00Z",
    "voting_closes": "2026-06-07T23:59:59Z"
  },
  "seed": {
    "protocol": "nist-beacon",
    "pulse_url":       "https://beacon.nist.gov/beacon/2.0/pulse/time/2026-06-08T00:00:00Z",
    "pulse_timestamp": "2026-06-08T00:00:00Z"
  }
}
```

A few things to notice:

- `threshold.type = "absolute", value = 1` — any item with at least one approval is eligible. They're a small group; nobody wants a higher bar.
- `allocation = "B"` — stochastic without replacement, so the piñata appears at most once.
- `tie_break = "random"` — if two items tie on votes, the seed decides. Reproducible after the fact.
- `privacy = "public"` — everyone in the group can see everyone's ballot. Friends, not adversaries.
- `seed.protocol = "nist-beacon"` — the random seed will come from the NIST randomness beacon at a specific timestamp **after voting closes**. Until then nobody can predict the draws; after that anyone can fetch the same pulse and verify the same result.

## Step 2 — Alice initializes the election

```
$ ppv init manifest.json daves-party/
```

The CLI:

1. Validates the manifest (schema, fingerprints, schedule, etc.).
2. Looks at Alice's gpg keyring, finds her key matches the roster, confirms with her that she wants to sign the genesis as that key.
3. Sets up `daves-party/` with `manifest.json` and an empty `ballots/`.
4. Auto-invokes `fossil init`, `fossil open`, `fossil setting clearsign on`, `fossil add manifest.json`, and `fossil ci`.

She now has `daves-party/daves-surprise-party.fossil` — a Fossil repo containing the signed genesis commit.

## Step 3 — Bob and Carol get the repo

Alice sends Bob and Carol the `daves-surprise-party.fossil` file. The realistic options:

- **Shared cloud drive** (iCloud, Dropbox, Syncthing): copy `daves-surprise-party.fossil` to a folder all three have access to. Each opens a working copy pointing at the shared file.
- **One-time file transfer** (`scp`, AirDrop, USB stick, email): each person gets their own copy of the file.
- **Fossil HTTP server with user accounts**: Alice runs `fossil server --port 8080 daves-surprise-party.fossil`, creates accounts for Bob and Carol with `fossil user new bob "Bob" bobpass` and `fossil user capabilities bob v`, and they clone via `fossil clone http://bob:bobpass@alices-ip:8080/`. This is what a homeserver-style deployment uses, but it adds setup steps that distract from the protocol. See Fossil's docs for details.

The walkthrough below assumes each voter has their own copy of `daves-surprise-party.fossil`. Bob opens his:

```
$ mkdir daves-party && cd daves-party
$ fossil open ../daves-surprise-party.fossil
```

Carol does the same. They each now have a working copy with `manifest.json` visible.

## Step 4 — Each of them votes

Bob has a strong opinion about banners:

```
$ cd daves-party
$ ppv vote banner streamers balloons
```

The CLI:

1. Loads the manifest, validates that `banner`, `streamers`, and `balloons` are real option ids.
2. Looks at Bob's gpg keyring, finds his secret key matches a roster fingerprint, picks it silently (there's only one match).
3. Builds the ballot JSON: `{version, election_id, manifest_hash, voter_fingerprint, approvals: [...]}`.
4. Writes `ballots/B0B0B0B0...B0B0B0B0.json`.
5. Auto-invokes `fossil add` and `fossil ci`. The commit is clearsigned with Bob's PGP key.
6. If a sync URL is configured, attempts to push back to it. Otherwise the ballot lives in Bob's local `.fossil` until aggregated (see step 5).

Carol approves fewer things:

```
$ ppv vote photo-booth fairy-lights
```

Alice — who got the deal on streamers — approves a lot:

```
$ ppv vote balloons streamers banner fairy-lights
```

After all three have voted, each voter's working copy has their own ballot file. They now need to pool everyone's ballots into a single tally-able repo. With separate `.fossil` files this is a one-time aggregation: Bob and Carol send their `ballots/*.json` files to Alice (any channel — email, shared folder, etc.), Alice drops them into her `daves-party/ballots/`, then runs `fossil add` and `fossil ci` on them. After that she resends the merged `.fossil` to Bob and Carol so they can verify.

With a Fossil HTTP server + user accounts (the homeserver-style path mentioned above) this aggregation happens automatically via `fossil sync`. The voting protocol doesn't care which transport you use; it only cares that everyone ends up with the same set of public ballot files.

## Step 5 — Voting closes; somebody runs the tally

Voting closes June 7 at midnight UTC. June 8, the NIST beacon publishes a pulse value at the timestamp the manifest pointed at. Whoever runs the tally fetches the pulse:

```
$ curl -s "https://beacon.nist.gov/beacon/2.0/pulse/time/2026-06-08T00:00:00Z" \
    | jq -r '.pulse.outputValue' \
    | tr 'A-Z' 'a-z' \
    > seed.hex
```

(The CLI's NIST-beacon fetcher is a follow-up; for now this happens by hand.)

Then:

```
$ ppv tally
wrote ./result.json: mode B, 3 selected, 5 unspent
```

`result.json` lands in the working dir. It's also committed and synced so the group can see it.

```json
{
  "mode": "B",
  "selected": ["banner", "streamers", "balloons"],
  "unspent": 17
}
```

(Your exact result depends on the seed and the votes; the point is everyone gets the same result from the same inputs.)

## Step 6 — Everyone verifies

Alice sends the merged `.fossil` (now containing all three ballots and the `result.json` she just produced) back to Bob and Carol. They each refresh their working copy and run:

```
$ ppv verify
OK: ./result.json matches recomputed tally
```

Bob runs `ppv verify` from his clone with the same `seed.hex`. Carol runs it from hers. All three see `OK`. The decision is settled and checkable: nobody had to trust the person who ran the tally — everyone can re-run from the same public inputs.

The shopping list: banner, streamers, balloons. $33 of $50 spent. $17 left over. Dave is going to be surprised.

## What the protocol actually achieved

- **No coin-flip dictator.** Even though the algorithm is stochastic, the randomness is bound to the manifest hash and a public seed nobody could predict in advance. After-the-fact, anyone can re-derive the result.
- **No coalition lockout.** Bob and Alice both approved banner and streamers; Carol approved different things. The algorithm didn't just take the majority's whole slate — Carol's approvals carried weight in the probability of getting drawn next.
- **No mandatory trust in a tallier.** The tally output is just `result.json`. Everyone re-runs the same tally from the same inputs and confirms the same output.
- **No mandatory trust in a server.** Fossil sync is peer-to-peer. Alice's machine doesn't have to be up forever; the repo lives on every voter's clone.

## Where to go from here

- [`docs/manifest-schema.md`](manifest-schema.md) — full schema reference for when you want to draft your own.
- [`docs/threat-model.md`](threat-model.md) — the public/group/individual trust modes, and what each protects against. Surprise parties are firmly in the "public" lane; board votes for a sensitive committee would use "group".
- [`../pizza-party-vote/README.md`](../pizza-party-vote/README.md) — the algorithm spec, if you want to know why probability is proportional to `votes × value` and what the three allocation modes are for.
