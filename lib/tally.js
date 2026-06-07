// lib/tally.js
// The voting mechanism: threshold filter + allocation rule.
// See ../pizza-party-vote/README.md for the algorithm (spec is the source
// of truth) and docs/deterministic-sampling.md for the exact seed-to-draw
// procedure (SHAKE128 stream, integer weights via product-of-other-prices,
// per-draw byte budget for ≤ 2^-128 bias).
//
// Probability formula is votes × value (multiplication). Integer weights
// live in BigInt to avoid floating-point divergence between implementations.

import * as sha3 from "./sha3.js";

const DOMAIN = "ppv/draw/v1";

// Run the tally.
//   manifest: parsed manifest (already validated)
//   ballots:  array of parsed ballot objects (already validated)
//   seedBytes: Uint8Array of seed bytes from the manifest's seed protocol
//   manifestHashHex: uppercase hex SHA3-256 of the canonical manifest
// Returns:
//   { mode, selected: [option_id...], unspent (modes A/B), weights (mode C) }
export function run(manifest, ballots, seedBytes, manifestHashHex) {
    const votes = computeVotes(manifest, ballots);
    const filtered = applyThreshold(votes, manifest, ballots.length);
    const stream = makeStream(manifestHashHex, seedBytes);

    switch (manifest.rule.allocation) {
        case "A": return modeA(manifest, filtered, stream);
        case "B": return modeB(manifest, filtered, stream);
        case "C": return modeC(manifest, filtered, stream);
        default:
            throw new Error(`tally.run: unknown allocation mode "${manifest.rule.allocation}"`);
    }
}

// ── shared front end ─────────────────────────────────────────

function computeVotes(manifest, ballots) {
    const votes = new Map();
    for (const o of manifest.options) votes.set(o.id, 0);
    for (const b of ballots) {
        for (const a of b.approvals) {
            if (votes.has(a)) votes.set(a, votes.get(a) + 1);
        }
    }
    return votes;
}

function applyThreshold(votes, manifest, totalBallots) {
    const rule = manifest.rule.threshold;
    const out = new Map();
    if (rule.type === "absolute") {
        for (const [id, c] of votes) {
            if (c >= rule.value) out.set(id, c);
        }
    } else if (rule.type === "fraction") {
        // value is percent (1..100). votes/total >= value/100, i.e., votes*100 >= value*total.
        for (const [id, c] of votes) {
            if (c * 100 >= rule.value * totalBallots) out.set(id, c);
        }
    } else if (rule.type === "top-k") {
        const ranked = manifest.options
            .map((o, i) => ({ id: o.id, votes: votes.get(o.id) || 0, idx: i }))
            .filter((x) => x.votes > 0)
            .sort((a, b) => b.votes - a.votes || a.idx - b.idx);
        const k = Math.min(rule.value, ranked.length);
        for (let i = 0; i < k; i++) out.set(ranked[i].id, ranked[i].votes);
    } else {
        throw new Error(`tally: unknown threshold type "${rule.type}"`);
    }
    return out;
}

// ── byte stream from SHAKE128 ────────────────────────────────

function makeStream(manifestHashHex, seedBytes) {
    const domain = asciiBytes(DOMAIN);
    const manifestHashBytes = hexToBytes(manifestHashHex);
    const context = concatBytes(domain, manifestHashBytes, seedBytes);

    let buf = new Uint8Array(0);
    let pos = 0;
    const CHUNK = 4096;

    return {
        take(n) {
            const end = pos + n;
            if (end > buf.length) {
                const newSize = Math.max(end + CHUNK, buf.length * 2);
                buf = sha3.shake128_bytes(context, newSize);
            }
            const out = buf.slice(pos, end);
            pos = end;
            return out;
        },
    };
}

// ── per-draw procedure ───────────────────────────────────────

function drawFromWeights(weights, stream) {
    const S = weights.reduce((acc, w) => acc + w, 0n);
    if (S === 0n) throw new Error("drawFromWeights: zero total weight");
    const bits = bitLengthBigInt(S);
    const N = Math.ceil(bits / 8) + 16; // 128 bits of headroom → bias ≤ 2^-128
    const bytes = stream.take(N);
    const R = bytesToBigIntBE(bytes);
    const r = R % S;
    let prefix = 0n;
    for (let i = 0; i < weights.length; i++) {
        prefix += weights[i];
        if (r < prefix) return i;
    }
    throw new Error("drawFromWeights: walked past sum (invariant violation)");
}

// weight(option) = votes × slices × ∏_{j ≠ option in candidates} price(j)
function computeWeights(candidates, votesMap) {
    return candidates.map((o, i) => {
        let prod = 1n;
        for (let j = 0; j < candidates.length; j++) {
            if (j !== i) prod *= BigInt(candidates[j].price);
        }
        return BigInt(votesMap.get(o.id)) * BigInt(o.slices) * prod;
    });
}

// ── mode A: stochastic with replacement ──────────────────────

function modeA(manifest, votes, stream) {
    const selected = [];
    let M = BigInt(manifest.rule.budget);
    while (true) {
        const candidates = manifest.options.filter(
            (o) => votes.has(o.id) && BigInt(o.price) <= M
        );
        if (candidates.length === 0) break;
        const weights = computeWeights(candidates, votes);
        if (weights.reduce((a, w) => a + w, 0n) === 0n) break;
        const idx = drawFromWeights(weights, stream);
        const drawn = candidates[idx];
        selected.push(drawn.id);
        M -= BigInt(drawn.price);
    }
    return { mode: "A", selected, unspent: Number(M) };
}

// ── mode B: stochastic without replacement ──────────────────

function modeB(manifest, votes, stream) {
    const selected = [];
    const remaining = new Set(manifest.options.filter((o) => votes.has(o.id)).map((o) => o.id));
    let M = BigInt(manifest.rule.budget);
    while (true) {
        const candidates = manifest.options.filter(
            (o) => remaining.has(o.id) && BigInt(o.price) <= M
        );
        if (candidates.length === 0) break;
        const weights = computeWeights(candidates, votes);
        if (weights.reduce((a, w) => a + w, 0n) === 0n) break;
        const idx = drawFromWeights(weights, stream);
        const drawn = candidates[idx];
        selected.push(drawn.id);
        remaining.delete(drawn.id);
        M -= BigInt(drawn.price);
    }
    return { mode: "B", selected, unspent: Number(M) };
}

// ── mode C: deterministic weighted top-M ─────────────────────

function modeC(manifest, votes, stream) {
    const M = manifest.rule.budget;
    const ranked = manifest.options
        .map((o, i) => ({ option: o, votes: votes.get(o.id) || 0, idx: i }))
        .filter((x) => x.votes > 0);
    ranked.sort((a, b) => b.votes - a.votes || a.idx - b.idx);

    if (M >= ranked.length) {
        return resultC(ranked.map((x) => x.option.id), votes);
    }

    const cutoff = ranked[M - 1].votes;
    const next = ranked[M].votes;
    if (next < cutoff) {
        return resultC(ranked.slice(0, M).map((x) => x.option.id), votes);
    }

    // Tied at the boundary. Find the tied group and break ties.
    let tieStart = M - 1;
    while (tieStart > 0 && ranked[tieStart - 1].votes === cutoff) tieStart--;
    let tieEnd = M;
    while (tieEnd < ranked.length && ranked[tieEnd].votes === cutoff) tieEnd++;

    const above = ranked.slice(0, tieStart);
    const tied = ranked.slice(tieStart, tieEnd);
    const seatsForTied = M - above.length;

    let chosenTied;
    const tb = manifest.rule.tie_break;
    if (tb === "first") {
        chosenTied = tied.slice(0, seatsForTied);
    } else if (tb === "alphabetic") {
        const sorted = [...tied].sort((a, b) =>
            a.option.id < b.option.id ? -1 : a.option.id > b.option.id ? 1 : 0
        );
        chosenTied = sorted.slice(0, seatsForTied);
    } else if (tb === "random") {
        chosenTied = [];
        const pool = [...tied];
        const poolWeights = pool.map(() => 1n);
        for (let k = 0; k < seatsForTied; k++) {
            const idx = drawFromWeights(poolWeights, stream);
            chosenTied.push(pool[idx]);
            pool.splice(idx, 1);
            poolWeights.splice(idx, 1);
        }
    } else {
        throw new Error(`tally: unknown tie_break "${tb}"`);
    }

    const selected = [...above, ...chosenTied].map((x) => x.option.id);
    return resultC(selected, votes);
}

function resultC(selectedIds, votes) {
    const weights = {};
    for (const id of selectedIds) weights[id] = votes.get(id);
    return { mode: "C", selected: selectedIds, weights };
}

// ── byte helpers ─────────────────────────────────────────────

function asciiBytes(s) {
    const out = new Uint8Array(s.length);
    for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
    return out;
}

function hexToBytes(hex) {
    if (hex.length % 2 !== 0) throw new Error("hexToBytes: odd-length input");
    const out = new Uint8Array(hex.length / 2);
    for (let i = 0; i < out.length; i++) {
        out[i] = parseInt(hex.substr(i * 2, 2), 16);
    }
    return out;
}

function concatBytes(...arrs) {
    let total = 0;
    for (const a of arrs) total += a.length;
    const out = new Uint8Array(total);
    let pos = 0;
    for (const a of arrs) {
        out.set(a, pos);
        pos += a.length;
    }
    return out;
}

function bytesToBigIntBE(bytes) {
    let r = 0n;
    for (const b of bytes) r = (r << 8n) | BigInt(b);
    return r;
}

function bitLengthBigInt(x) {
    if (x === 0n) return 1;
    return x.toString(2).length;
}
