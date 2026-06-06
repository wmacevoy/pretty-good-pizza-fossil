# Threat model

**Status: Pinned.** Captures the at-rest encryption design for phase 2 of the build (custom Fossil with SQLCipher). `build/patches/fossil-db-key.patch` may now be written against this spec.

## Scope

This document covers **at-rest encryption of a voter's local Fossil clone** via SQLCipher. The cryptographic question is which threats the encryption layer is paying complexity to defend against, and how the key reaches `PRAGMA key`. Identity, ballot authenticity, sync integrity, and transport security are handled by other layers (Fossil clearsign, hash-chained manifests, LibreSSL TLS) and are out of scope here.

## Three trust modes

An election declares its trust mode in the manifest as `rule.privacy`. The custom Fossil binary supports all three modes; the manifest picks which one applies to a given election.

| Mode | `rule.privacy` | At-rest encryption | Use cases |
|---|---|---|---|
| Public | `"public"` | none (SQLCipher not engaged for this repo) | Open polls, transparent grants, anything meant to be world-readable |
| Group | `"group"` | shared key, multi-recipient gpg-encrypted to roster | Board votes with confidential deliberation, executive committees, anything where outsiders should not see drafts/notes but the roster mutually trusts each other |
| Individual | `"individual"` | per-voter key | DEFERRED. Future use case where peers do not trust each other. Not accepted in v1. |

Two roster invariants apply across all modes:

- **The convener is always a roster member.** They generate keys (mode 2) or otherwise bootstrap the election as a participant, not as a privileged external party. Avoids a special "convener role" with different permissions.
- **Rosters are frozen at genesis** — no add or remove of voters mid-election. A roster member who chooses not to participate simply submits no ballot, which is equivalent to all-zero approvals. This removes whole categories of key-management churn (no rotation on join/leave).

## Mode is genesis-locked

The trust mode is determined by `rule.privacy` in the manifest and is fixed for the life of the election. There is no protocol-level upgrade or downgrade path. Two reasons:

- **Public → group later cannot retroactively hide anything.** Plaintext content is already in clones, backups, peer caches, and possibly outside copies. Encrypting today does not unsay yesterday.
- **Group → public later** is technically possible (decrypt and republish) but is an out-of-band declassification by the roster, not a tool feature. The audience for the content grows; past privacy was bounded to "roster members during the election," which is unaffected.

To change a privacy posture, start a new election with a new manifest. Optionally reuse the roster and options by copying them into the new manifest at drafting time — that is just JSON authoring, not a protocol operation. The new election has a different `manifest_hash` and is, by design, a different election.

Group → public declassification is a documented one-time manual action: a roster member decrypts the repo locally and republishes the plaintext content. It is not a `fossil ppp` subcommand and should not become one.

## What lives in the local repo

| Artifact | Sensitivity | Why |
|---|---|---|
| Election manifest | Public | Already published; hash is the election's identifier. |
| Synced ballots | Public *to the group* | By design — this system targets public-ballot use cases. |
| Tallies, audit logs | Public | Verifiable from public inputs. |
| Wiki / forum content | Group-private (mode 2) or public (mode 1) | Discussion among voters. Sensitivity depends on the mode. |
| Draft ballots before submission | Voter-private | Reveals intent; could enable coercion or pre-emptive influence. |
| Local notes, scratch | Voter-private | Personal working notes about the election. |
| Unrevealed commit-reveal shares | Voter-private until reveal phase | Knowing a share before reveal enables seed prediction. |
| Voter's PGP private key | **Not in repo** | Lives in `gpg`'s keyring; protected separately by gpg-agent + passphrase. |

In mode 1 the assets that matter are largely public. In mode 2 the voter-private and group-private rows are what the encryption layer is paying complexity to protect.

## Threats: globally in scope (when encryption is engaged)

These are what mode 2 SQLCipher is paying complexity to defend against. Mode 1 disclaims them, by declaring the content public.

1. **Stolen laptop / device seizure.** Adversary has physical access to the disk while Fossil is not running. Without SQLCipher, they read drafts, notes, and group-private discussion as plaintext SQLite. With SQLCipher and the key wrapped under gpg, the DB file is opaque without a roster member's gpg secret key.
2. **Backup exposure.** The voter's machine backs up to iCloud, Time Machine, Restic, an external drive. An attacker who compromises the backup target gets historical clone snapshots. SQLCipher renders the backup contents inert without the gpg key.
3. **Multi-user workstation hygiene.** Another local account, or a process running as another user, can read the Fossil repo if file permissions are loose. SQLCipher is a second layer behind correct filesystem permissions, not a replacement.

## Threats: globally out of scope

SQLCipher is **not** a defense against these in any mode. Documenting so users do not over-trust the encryption layer:

1. **Live endpoint compromise.** Malware on the voter's machine while Fossil is running can read SQLCipher's in-memory key, prompt the user for the gpg passphrase via a fake dialog, or exfiltrate decrypted query results.
2. **RAM extraction / cold-boot attacks.** While Fossil holds the key in memory, an attacker with privileged access can recover it.
3. **Forgery, equivocation, or repo rewriting by a peer.** Handled by Fossil's hash chain and clearsign.
4. **Network interception during sync.** Handled by LibreSSL TLS in the same custom Fossil binary.
5. **Public-ballot semantics.** Synced ballots are visible to every voter in the roster by design.
6. **Sybil, eligibility, or coercion attacks on the voting layer.** Different threat surface entirely.

## Mode 1 — Public

Manifest sets `rule.privacy = "public"`. SQLCipher is compiled into the binary but **not engaged** for this repo. `db_open` skips `PRAGMA key`; the database file is plain SQLite, readable by anyone with filesystem access. The mode declares that nothing in the repo needs hiding.

### In scope at the encryption layer

Nothing. The encryption layer disclaims the threats above for public-mode repos.

### Operational notes

Voters in a public-mode election should still set sane filesystem permissions on their clone (`chmod 0700` the clone directory) — basic hygiene, not crypto.

## Mode 2 — Group

Manifest sets `rule.privacy = "group"`. The repo is encrypted with a single SQLCipher master key `K`, distributed once to the closed roster via gpg's multi-recipient encrypt and never rotated for membership reasons (because the roster does not change).

### Mechanism

1. **At `fossil ppp init`** (convener side): generate a cryptographically random 256-bit key `K` (source pinned below). Encrypt `K` to every roster member's gpg public key in one operation:

   ```
   gpg --encrypt --armor \
       --recipient FP_CONVENER \
       --recipient FP_VOTER_1 ... --recipient FP_VOTER_N \
       --output keys/master.key.asc <<< "<K as hex>"
   ```

   Commit `keys/master.key.asc` to the repo as part of the genesis commit. The convener's clearsign on the genesis commit covers this blob.

2. **At every `fossil open`** (any roster member): invoke `gpg --decrypt keys/master.key.asc` to recover `K`. gpg-agent handles the passphrase prompt and smart-card interaction. Pass `K` to SQLCipher via `PRAGMA key = "x'<K hex>'";`. Zeroize the in-memory copy of `K` after `PRAGMA key` returns.

3. **Threats addressed**: an attacker who is not a roster member and does not hold a roster member's gpg secret key cannot read the repo, even with full physical access to the disk.

4. **Threats not addressed**: any roster member can decrypt the repo. By design. If you do not trust your peers with the contents, mode 2 is the wrong choice — use mode 3 when it lands.

### Convener init-time UX

The convener's gpg key signs the genesis manifest (via clearsign) and serves as one of the recipients in the multi-recipient encrypt of `K`. The same key must be used for both, and it must be one of the manifest's roster fingerprints (per the convener-on-roster invariant).

On `fossil ppp init <manifest.json>`, the tool:

1. Walks the manifest's roster fingerprints and identifies which entries have a usable secret key in the convener's keyring (not expired, not revoked, secret-key part available or smart-card connected).
2. If **exactly one** match, presents a confirmation prompt:
   `Sign genesis as 7A4B…XX <Alice convener@example.com> (expires 2027-06-30)? [Y/n]`.
3. If **multiple** matches, presents a numbered chooser of all matching keys (fingerprint + uid + expiry).
4. If **zero** matches, errors: `your gpg keyring has no secret key for any roster fingerprint; either edit the manifest to add yours, or import the matching secret key.`

The confirmation prompt is **unconditional** at init — voters at first-open skip the prompt when only one key matches because their stakes are lower and their frequency higher, but the convener is signing the genesis manifest, which is the highest-stakes operation in the protocol. A one-time speed bump is appropriate.

After confirmation, the same key is used both for the clearsign of the genesis commit and as one of the `--recipient` slots in the multi-recipient gpg encrypt of `K`.

### First-open UX

On first `fossil open` of a mode-2 clone:

1. Read the manifest, identify the roster.
2. Identify which gpg keys in the voter's keyring match the roster. If exactly one matches, proceed with it. If multiple match, present a chooser (fingerprint + uid + expiry) and ask the voter to confirm. If none match, warn that the voter is not on the roster and proceed read-only (they can browse a public-mode clone or audit but cannot decrypt a group-mode clone).
3. Decrypt `keys/master.key.asc` using the chosen key.

The chooser sidesteps the silent-wrong-key footgun ("I cloned, voted, came back the next day, can't decrypt"). The not-on-roster warning sidesteps the silent-non-member confusion ("I cloned but nothing works").

### Hardware tokens

A roster member whose gpg private key lives on a YubiKey (or equivalent smart card) gets a stronger threat model automatically: a stolen laptop is useless without the token, because the gpg-decrypt step requires the card. No code path differs — `gpg --decrypt` handles smart cards transparently via gpg-agent. **Recommended posture for high-value elections; not mandatory.**

The trade-off voters should understand: a YubiKey is one token per device. Voters with multiple machines either keep a single token they plug in everywhere, or wrap multiple subkeys onto multiple tokens. Both are standard gpg operation; neither needs new code in this project.

### Key lifecycle

Because the roster is frozen at genesis, mode-2 key management has no membership-driven churn:

- **Rotation is on-demand only**, triggered by suspected compromise of `K`. The convener generates `K'`, re-encrypts it to the same roster, commits the new `keys/master.key.asc`, and locally issues SQLCipher's `PRAGMA rekey` to re-encrypt the DB with `K'`. Each voter, on next open, picks up the new blob and re-keys their local clone.
- **No periodic rotation cadence is mandated.** Drafts and unrevealed shares have short shelf lives; forced rotation adds cost without clear payoff at this stage.
- **Loss of one voter's gpg key**: that voter is locked out of their local clone. They re-clone from a peer once they have a working gpg key again. `K` is unchanged; other voters are unaffected.

### Master-key randomness source

`K` is 32 bytes from LibreSSL's `RAND_bytes()` (the binary already links libcrypto). Naming the source explicitly so independent verifiers reading the convener's init step know what they would have to challenge to dispute it.

### Operational notes

- File-mode `0600` on `keys/master.key.asc` is not required (the file is itself encrypted, and is committed to a synced repo), but `0700` on the clone directory remains sensible.
- A roster member whose machine is fully compromised exposes `K` from RAM. The other roster members' machines are still safe at rest, but everything in the repo prior to compromise is potentially in the attacker's hands via the compromised peer. This is inherent to any shared-key system.

## Mode 3 — Individual (deferred)

Out of v1 scope. Sketch for future reference: each voter has their own key, no key sharing; appropriate when peers do not trust each other but still want to vote on a common set of options. The mechanism would resemble per-voter PGP-wrap of a per-voter SQLCipher key, with no shared blob in the repo. The build should reject `rule.privacy = "individual"` for v1 with an explanatory error message so the door is open without implementing it.

## What this implies for `build/build-fossil.sh`

`build/patches/fossil-db-key.patch` should:

1. Read `rule.privacy` from the manifest at `db_open` time. The manifest is the genesis artifact and is always accessible via Fossil's blob store before any encrypted DB access.
2. If `rule.privacy == "public"`, skip `PRAGMA key` entirely. Behaves as stock Fossil + SQLite.
3. If `rule.privacy == "group"`, locate `keys/master.key.asc` (committed to the repo) and shell out to `gpg --decrypt --output - keys/master.key.asc` to recover `K`. No `--batch` flag — that lets `gpg-agent` broker interactive passphrase entry and smart-card prompts when needed. Read decrypted bytes from gpg's stdout; check exit code; issue `PRAGMA key = "x'<K hex>'";` and zeroize the in-memory copy of `K`.
4. If `rule.privacy == "individual"`, error out with "individual mode not supported in this build of fossil-ppp; see docs/threat-model.md mode 3."
5. Honor the `FOSSIL_PPP_KEY` env var as a mode-2 escape hatch: if set, use its value directly as `K` and skip the gpg-decrypt step. Documented as testing/CI-only; the README must flag that this defeats the at-rest protection while the variable is in the process environment.

The patch is small (~50-80 lines once gpg-shellout error handling is included). The trickier parts are robustly invoking `gpg-agent` (so the user is not re-prompted on every operation) and handling the not-on-roster case in step 1 of the first-open UX.

## Resolved decisions

- **Cross-platform target → PGP-wrap is the encryption-key UX**, not OS keychain. OS keychain integration deferred indefinitely.
- **Roster is frozen at genesis. The convener is always a roster member.** No add/remove churn; abstention is a no-op (zero approvals).
- **Mode is genesis-locked.** No protocol-level upgrade/downgrade. Changing privacy posture requires a new election with a new manifest.
- **Mode 2 uses gpg's multi-recipient encrypt** for a single shared `K`, stored at `keys/master.key.asc` in the repo. Not per-voter wrapped copies, not OS-specific storage.
- **Convener init-time UX always confirms the signing key**, even when only one roster fingerprint matches. The genesis signature is unrecoverable; the one-time speed bump is appropriate.
- **Voter first-open UX uses a roster-aware chooser** when the voter has multiple matching gpg keys; warns and proceeds read-only when the voter has none. No confirmation prompt when exactly one key matches — lower stakes, higher frequency than init.
- **gpg invocation is by shell-out**, not libgpgme link. Zero new build deps, process isolation, agent-mediated UX. Exact invocation: `gpg --decrypt --output - keys/master.key.asc`, no `--batch`.
- **Hardware tokens are documented as a free upgrade** in modes 2 and 3, not mandatory.
- **Key rotation is on-demand only** (suspected compromise). No mandated cadence, no membership-driven rotation.
