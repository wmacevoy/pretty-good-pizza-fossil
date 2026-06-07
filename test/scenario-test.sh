#!/usr/bin/env bash
set -euo pipefail
# Federated scenario test: three voters in three independent workspaces.
# Demonstrates determinism + independent verification.
#
# What this exercises:
#   - 3 ephemeral GPG identities in separate GNUPGHOMEs (simulating 3 machines)
#   - mode=public election; `ppv init` builds + commits the genesis
#   - 3 ballots cast independently
#   - 3 independent `ppv tally` runs produce byte-identical results
#
# What this does NOT exercise (deferred):
#   - Fossil sync over HTTP/HTTPS between distinct hosts (uses a shared .fossil
#     file as the federation substrate; sync correctness is upstream Fossil's
#     concern, not ours).
#   - mode=group SQLCipher round-trip (would need the custom fossil-ppv binary
#     and the gpg-encrypted master key — covered by build smoke tests).

REPO=$(cd "$(dirname "$0")/.." && pwd)
# Use /tmp directly: gpg-agent's UNIX socket path must fit in ~108 bytes,
# and macOS's default /var/folders/<long>/T/ blows that budget.
TMP=$(TMPDIR=/tmp mktemp -d /tmp/ppv-XXXXXX)
cleanup() {
    # Try to kill child gpg-agents per GNUPGHOME so the temp dir is removable.
    for d in "$TMP"/gnupg-*; do
        [ -d "$d" ] && GNUPGHOME="$d" gpgconf --kill all 2>/dev/null || true
    done
    rm -rf "$TMP"
}
trap cleanup EXIT

# ── tooling: put built fossil-ppv on PATH as 'fossil' ───────────
mkdir -p "$TMP/bin"
if [ -x "$REPO/build/dist/fossil-ppv" ]; then
    ln -sf "$REPO/build/dist/fossil-ppv" "$TMP/bin/fossil"
elif command -v fossil >/dev/null 2>&1; then
    : # use system fossil
else
    echo "ERR: no fossil binary available (neither build/dist/fossil-ppv nor system fossil)" >&2
    exit 1
fi
export PATH="$TMP/bin:$PATH"
echo "==> using fossil: $(command -v fossil) ($(fossil version 2>&1 | head -1))"

# ── 3 ephemeral GPG identities ──────────────────────────────────
echo "==> generating 3 ephemeral GPG keys"
gen_key() {
    local voter=$1
    local G="$TMP/gnupg-$voter"
    mkdir -p "$G"; chmod 700 "$G"
    printf 'allow-loopback-pinentry\n' > "$G/gpg-agent.conf"
    printf 'batch\npinentry-mode loopback\n' > "$G/gpg.conf"
    GNUPGHOME="$G" gpg --batch --passphrase '' --quick-generate-key \
            "$voter Test <$voter@scenario.test.local>" default default never \
            >> "$TMP/gpg.log" 2>&1 \
        || { echo "ERR: gpg key gen failed for $voter (rc=$?); log tail:" >&2; \
             tail -10 "$TMP/gpg.log" >&2; exit 1; }
    GNUPGHOME="$G" gpg --list-secret-keys --with-colons 2>/dev/null \
        | awk -F: '/^fpr/{print $10; exit}'
}
FP_ALICE=$(gen_key alice); echo "   alice: $FP_ALICE"
FP_BOB=$(gen_key bob);     echo "   bob:   $FP_BOB"
FP_CAROL=$(gen_key carol); echo "   carol: $FP_CAROL"

fp_for() {
    case "$1" in
        alice) echo "$FP_ALICE" ;;
        bob)   echo "$FP_BOB" ;;
        carol) echo "$FP_CAROL" ;;
    esac
}
approvals_for() {
    case "$1" in
        alice) echo "x y" ;;
        bob)   echo "x" ;;
        carol) echo "y" ;;
    esac
}

# ── manifest ────────────────────────────────────────────────────
echo "==> building manifest"
NOW_YEAR=$(date +%Y)
cat > "$TMP/manifest.json" <<EOF
{
  "version": "ppv/1",
  "election_id": "scenario-${RANDOM}",
  "title": "Scenario test",
  "description": "Federated 3-voter scenario test.",
  "convener": {"name": "Alice", "pgp_fingerprint": "${FP_ALICE}"},
  "voters": [
    {"name": "Alice", "pgp_fingerprint": "${FP_ALICE}"},
    {"name": "Bob",   "pgp_fingerprint": "${FP_BOB}"},
    {"name": "Carol", "pgp_fingerprint": "${FP_CAROL}"}
  ],
  "options": [
    {"id": "x", "title": "Option X", "slices": 1, "price": 10},
    {"id": "y", "title": "Option Y", "slices": 1, "price": 20}
  ],
  "rule": {
    "threshold": {"type": "absolute", "value": 1},
    "allocation": "A",
    "budget": 30,
    "tie_break": "random",
    "privacy": "public"
  },
  "schedule": {
    "voting_opens":  "${NOW_YEAR}-01-01T00:00:00Z",
    "voting_closes": "${NOW_YEAR}-12-31T23:59:59Z"
  },
  "seed": {
    "protocol": "nist-beacon",
    "pulse_url":       "https://example/scenario",
    "pulse_timestamp": "${NOW_YEAR}-12-31T23:59:59Z"
  }
}
EOF

# ── alice (convener) inits the election ─────────────────────────
echo "==> alice: ppv init"
GNUPGHOME="$TMP/gnupg-alice" PPV_YES=1 \
    "$REPO/bin/ppv" init "$TMP/manifest.json" "$TMP/ws-alice" >/dev/null

# Sanity: the genesis .fossil now exists.
ELECTION_ID=$(awk -F'"' '/"election_id"/{print $4; exit}' "$TMP/manifest.json")
REPO_FILE="$TMP/ws-alice/${ELECTION_ID}.fossil"
[ -f "$REPO_FILE" ] || { echo "ERR: ${REPO_FILE} not created"; exit 1; }
echo "   genesis: ${REPO_FILE}"

# ── simulate sync: clone alice's repo to bob and carol ──────────
echo "==> simulating sync to bob and carol"
for voter in bob carol; do
    mkdir -p "$TMP/ws-$voter"
    # Copy the .fossil file (simulating a fossil clone). Each voter opens it
    # in their own working directory.
    cp "$REPO_FILE" "$TMP/ws-$voter/${ELECTION_ID}.fossil"
    (cd "$TMP/ws-$voter" && fossil open "${ELECTION_ID}.fossil" >/dev/null)
done

# ── each voter casts a ballot from their own workspace ──────────
echo "==> casting ballots"
for voter in alice bob carol; do
    AP=$(approvals_for $voter)
    echo "   $voter approves: $AP"
    (
        cd "$TMP/ws-$voter"
        GNUPGHOME="$TMP/gnupg-$voter" \
            "$REPO/bin/ppv" vote $AP >/dev/null
    )
done

# ── propagate everyone's ballots to all workspaces ──────────────
echo "==> propagating ballots (simulating bidirectional sync)"
mkdir -p "$TMP/all-ballots"
for voter in alice bob carol; do
    cp "$TMP/ws-$voter/ballots/$(fp_for $voter).json" "$TMP/all-ballots/"
done
for voter in alice bob carol; do
    cp "$TMP"/all-ballots/*.json "$TMP/ws-$voter/ballots/"
done

# ── seed: shared across the three workspaces ────────────────────
SEED=$(openssl rand -hex 32)
for voter in alice bob carol; do
    echo "$SEED" > "$TMP/ws-$voter/seed.hex"
done

# ── each voter tallies independently ────────────────────────────
echo "==> running independent tallies"
for voter in alice bob carol; do
    "$REPO/bin/ppv" tally "$TMP/ws-$voter" 2>/dev/null
done

# ── compare results ─────────────────────────────────────────────
echo "==> comparing results"
A_SHA=$(shasum -a 256 "$TMP/ws-alice/result.json" | awk '{print $1}')
B_SHA=$(shasum -a 256 "$TMP/ws-bob/result.json"   | awk '{print $1}')
C_SHA=$(shasum -a 256 "$TMP/ws-carol/result.json" | awk '{print $1}')
echo "   alice: $A_SHA"
echo "   bob:   $B_SHA"
echo "   carol: $C_SHA"

if [ "$A_SHA" != "$B_SHA" ] || [ "$B_SHA" != "$C_SHA" ]; then
    echo
    echo "FAIL: tallies diverged"
    echo "--- alice ---"; cat "$TMP/ws-alice/result.json"
    echo "--- bob ---";   cat "$TMP/ws-bob/result.json"
    echo "--- carol ---"; cat "$TMP/ws-carol/result.json"
    exit 1
fi

# ── each voter runs ppv verify against their workspace ──────────
echo "==> independent verifications"
for voter in alice bob carol; do
    if ! "$REPO/bin/ppv" verify "$TMP/ws-$voter" 2>/dev/null; then
        echo "FAIL: $voter verify failed"
        exit 1
    fi
done

echo
echo "PASS: three independent tallies match byte-for-byte and verify succeeds in all three workspaces."
echo
cat "$TMP/ws-alice/result.json"
