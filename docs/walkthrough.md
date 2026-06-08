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
    "privacy": "group"
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
- `privacy = "group"` — **this is what keeps the surprise a surprise.** The Fossil clone is stored as a SQLCipher-encrypted database; the manifest, ballots, decision, and any wiki/forum notes are opaque ciphertext on disk. Only the three of them (Alice, Bob, Carol) hold the gpg keys that can unlock it. If Dave finds Alice's laptop, copies the `.efossil` file, even mounts her backup — without one of the roster's gpg secret keys he gets random bytes. (The alternative, `privacy = "public"`, leaves the repo as plain SQLite; appropriate for open polls, not surprise parties. See [`docs/threat-model.md`](threat-model.md) for the full design.)
- `seed.protocol = "nist-beacon"` — the random seed will come from the NIST randomness beacon at a specific timestamp **after voting closes**. Until then nobody can predict the draws; after that anyone can fetch the same pulse and verify the same result.

## Step 2 — Alice initializes the election

```
$ ppv init manifest.json daves-party/
```

For a mode-group election the CLI:

1. Validates the manifest (schema, fingerprints, schedule, etc.).
2. Looks at Alice's gpg keyring, finds her key matches the roster, confirms with her that she wants to sign the genesis as that key.
3. **Generates a 256-bit random master key `K`.** This is the SQLCipher key the encrypted Fossil DB will be unlocked with. Held only in RAM during the init step.
4. **Multi-recipient gpg-encrypts `K`** to all three roster fingerprints — Alice's, Bob's, and Carol's. The result is `daves-party/keys/master.key.asc`: ASCII-armored ciphertext that any one of them can decrypt with their own gpg secret key, but nobody else can. After writing the file, the CLI zeroizes its in-memory copy of `K`.
5. Sets up `daves-party/` with `manifest.json`, `keys/master.key.asc`, and an empty `ballots/`.
6. Prints the manual `fossil-ppv` commands Alice runs to create the encrypted genesis. (Mode group can't auto-invoke `fossil init` like mode public does: SQLCipher cannot retroactively encrypt a plaintext DB, so the repo file must be created by the patched `fossil-ppv` binary in encrypted form from the start.)

Alice runs the printed commands:

```
$ cd daves-party
$ fossil-ppv init daves-surprise-party.efossil
$ fossil-ppv open daves-surprise-party.efossil
$ fossil-ppv setting clearsign on
$ fossil-ppv add manifest.json keys/
$ fossil-ppv ci -m "genesis: daves-surprise-party"
```

(If `fossil-ppv` is symlinked to `fossil` on PATH — the install doc's default — these all read as plain `fossil` commands.)

She now has `daves-party/daves-surprise-party.efossil` — note the **`.efossil` extension** (Fossil's convention for SEE-encrypted repos). It is a SQLCipher database from byte zero. Anyone opening it without `keys/master.key.asc` plus a roster gpg key sees random noise. Anyone opening it with both gets a normal Fossil repo containing the signed genesis commit.

### What just happened, in one paragraph

Alice produced a random key, locked it in a box that only Alice/Bob/Carol can open (the gpg multi-recipient encrypt), put the box inside the Fossil repo, and then encrypted the whole repo with the key from the box. Any one roster member can open the box (gpg-decrypt with their own secret key), pull the master key out, and use it to unlock the repo. An outsider with both the box and the repo file still can't read anything: they need a gpg secret key from one of the three to open the box first. That is the entire surprise-party guarantee.

## Step 3 — Bob and Carol get the repo

Alice sends Bob and Carol the `daves-surprise-party.efossil` file. Sending the encrypted file over an untrusted channel is fine — that's the whole point. The realistic options:

- **Shared cloud drive** (iCloud, Dropbox, Syncthing): the file on the cloud provider's servers is opaque ciphertext. They cannot read it. Dave, with cloud access to Alice's drive, cannot read it either.
- **One-time file transfer** (`scp`, AirDrop, USB stick, email): same story; intermediaries see ciphertext.
- **Fossil HTTP server with user accounts**: Alice runs `fossil-ppv server --port 8080 daves-surprise-party.efossil`, creates accounts for Bob and Carol, and they clone via `fossil-ppv clone http://...`. The HTTP transport carries SQLCipher pages; sniffing the wire doesn't reveal plaintext either.

The walkthrough below assumes each voter has their own copy of `daves-surprise-party.efossil`. Bob opens his:

```
$ mkdir daves-party && cd daves-party
$ fossil-ppv open ../daves-surprise-party.efossil
```

On this **first open**, `fossil-ppv` reads `keys/master.key.asc` from inside the repo's blob store, shells out to `gpg --decrypt` to recover the master key, and uses it for SQLCipher's `PRAGMA key`. gpg-agent prompts Bob for the passphrase to his secret PGP key (or, if his key lives on a YubiKey, asks him to touch it). After that, the working copy looks just like a normal Fossil checkout: `manifest.json` is visible, `keys/master.key.asc` is visible, and so on.

Carol does the same on her machine. Each of them now has a decrypted working copy. If either of them walks away from their laptop, the SQLCipher key is held only in the running `fossil-ppv` process; the file on disk stays encrypted at rest.

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

After all three have voted, each voter's working copy has their own clearsigned ballot file. They now need to pool everyone's ballots into a single tally-able repo. With separate `.efossil` files this is a one-time aggregation: Bob and Carol send their `ballots/*.json` files to Alice (any channel — the JSON files are not themselves secret since they live inside the encrypted repo only to keep the *whole transcript* hidden from Dave, but each individual ballot is clearsigned plaintext from the voter's perspective), Alice drops them into her `daves-party/ballots/`, then runs `fossil-ppv add` and `fossil-ppv ci` on them. After that she resends the merged `.efossil` to Bob and Carol so they can verify.

With a Fossil HTTP server + user accounts this aggregation happens automatically via `fossil-ppv sync`. The voting protocol doesn't care which transport you use; it only cares that everyone ends up with the same set of ballot files inside the shared encrypted repo.

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

Alice sends the merged `.efossil` (now containing all three ballots and the `result.json` she just produced) back to Bob and Carol. They each refresh their working copy and run:

```
$ ppv verify
OK: ./result.json matches recomputed tally
```

Bob runs `ppv verify` from his clone with the same `seed.hex`. Carol runs it from hers. All three see `OK`. The decision is settled and checkable: nobody had to trust the person who ran the tally — everyone can re-run from the same inputs.

The shopping list: banner, streamers, balloons. $33 of $50 spent. $17 left over. Dave is going to be surprised — both because they did all this without him hearing about it, and because the encrypted Fossil clones on three laptops never gave him a way to find out.

## What the protocol actually achieved

- **No coin-flip dictator.** Even though the algorithm is stochastic, the randomness is bound to the manifest hash and a public seed nobody could predict in advance. After-the-fact, anyone can re-derive the result.
- **No coalition lockout.** Bob and Alice both approved banner and streamers; Carol approved different things. The algorithm didn't just take the majority's whole slate — Carol's approvals carried weight in the probability of getting drawn next.
- **No mandatory trust in a tallier.** The tally output is just `result.json`. Everyone re-runs the same tally from the same inputs and confirms the same output.
- **No mandatory trust in a server.** Fossil sync is peer-to-peer. Alice's machine doesn't have to be up forever; the repo lives on every voter's clone.
- **No leak to outsiders.** The plan, the ballots, the deliberation notes, the result — every byte of the repo is SQLCipher-encrypted at rest with a key only the roster's three gpg keys can unwrap. Dave can stumble onto the `.efossil` file in shared cloud storage and learn nothing.

## Where to go from here

- [`docs/manifest-schema.md`](manifest-schema.md) — full schema reference for when you want to draft your own.
- [`docs/threat-model.md`](threat-model.md) — the three privacy modes (public / group / individual), what each protects against, and the full SQLCipher key-derivation design. The "group" mode this walkthrough used is the one fully implemented in v0.1.0; "individual" is documented but deferred.
- [`../pizza-party-vote/README.md`](../pizza-party-vote/README.md) — the algorithm spec, if you want to know why probability is proportional to `votes × value` and what the three allocation modes are for.
