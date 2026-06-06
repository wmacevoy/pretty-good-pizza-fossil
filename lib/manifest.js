// lib/manifest.js
// Election manifest: load, validate, canonical hash.
// See docs/manifest-schema.md and docs/canonical-json.md.

import * as std from "std";
import * as cj from "./canonical-json.js";
import * as sha3 from "./sha3.js";

const VERSION = "ppv/1";

export function load(path) {
    const f = std.open(path, "rb");
    if (f === null) throw new Error(`manifest.load: cannot open ${path}`);
    let raw;
    try {
        raw = f.readAsString();
    } finally {
        f.close();
    }
    return cj.parse(raw);
}

export function validate(m) {
    // Enforce docs/manifest-schema.md. Throws on first violation with a
    // human-readable message. Caller may rely on the throw vs. return-success
    // distinction; we never partial-succeed.
    requireString(m, "version");
    if (m.version !== VERSION) {
        throw new Error(`manifest: unsupported version "${m.version}"; expected "${VERSION}"`);
    }
    requireString(m, "election_id");
    requireString(m, "title");
    requireString(m, "description");

    requireObject(m, "convener");
    requireFingerprint(m.convener, "convener.pgp_fingerprint");
    requireString(m.convener, "name");

    requireNonEmptyArray(m, "voters");
    const fps = new Set();
    m.voters.forEach((v, i) => {
        requireString(v, `voters[${i}].name`);
        requireFingerprint(v, `voters[${i}].pgp_fingerprint`);
        if (fps.has(v.pgp_fingerprint)) {
            throw new Error(`manifest: duplicate voter fingerprint ${v.pgp_fingerprint}`);
        }
        fps.add(v.pgp_fingerprint);
    });
    if (!fps.has(m.convener.pgp_fingerprint)) {
        throw new Error(`manifest: convener fingerprint not in voters roster`);
    }

    requireNonEmptyArray(m, "options");
    const ids = new Set();
    m.options.forEach((o, i) => {
        requireString(o, `options[${i}].id`);
        requireString(o, `options[${i}].title`);
        requirePositiveInt(o, `options[${i}].slices`);
        requirePositiveInt(o, `options[${i}].price`);
        if (ids.has(o.id)) {
            throw new Error(`manifest: duplicate option id "${o.id}"`);
        }
        ids.add(o.id);
    });

    requireObject(m, "rule");
    const r = m.rule;
    requireObject(r, "threshold");
    if (!["absolute", "fraction", "top-k"].includes(r.threshold.type)) {
        throw new Error(`manifest: rule.threshold.type must be absolute|fraction|top-k`);
    }
    requirePositiveInt(r.threshold, "threshold.value");
    if (!["A", "B", "C"].includes(r.allocation)) {
        throw new Error(`manifest: rule.allocation must be A|B|C`);
    }
    requirePositiveInt(r, "budget");
    if (!["random", "first", "alphabetic"].includes(r.tie_break)) {
        throw new Error(`manifest: rule.tie_break must be random|first|alphabetic`);
    }
    if (!["public", "group", "individual"].includes(r.privacy)) {
        throw new Error(`manifest: rule.privacy must be public|group|individual`);
    }
    if (r.privacy === "individual") {
        throw new Error(`manifest: rule.privacy="individual" is not supported in v1; see docs/threat-model.md mode 3`);
    }

    requireObject(m, "schedule");
    requireString(m.schedule, "voting_opens");
    requireString(m.schedule, "voting_closes");
    if (Date.parse(m.schedule.voting_opens) >= Date.parse(m.schedule.voting_closes)) {
        throw new Error(`manifest: schedule.voting_opens must precede voting_closes`);
    }

    requireObject(m, "seed");
    if (!["nist-beacon", "commit-reveal"].includes(m.seed.protocol)) {
        throw new Error(`manifest: seed.protocol must be nist-beacon|commit-reveal`);
    }
}

export function canonicalHash(m) {
    const bytes = cj.encode(m);
    return sha3.sha3_256_hex(bytes);
}

// ── small validation helpers ─────────────────────────────────────

function requireString(obj, fieldPath) {
    const v = resolvePath(obj, fieldPath);
    if (typeof v !== "string" || v.length === 0) {
        throw new Error(`manifest: ${fieldPath} must be a non-empty string`);
    }
}

function requireObject(obj, fieldPath) {
    const v = resolvePath(obj, fieldPath);
    if (typeof v !== "object" || v === null || Array.isArray(v)) {
        throw new Error(`manifest: ${fieldPath} must be an object`);
    }
}

function requireNonEmptyArray(obj, fieldPath) {
    const v = resolvePath(obj, fieldPath);
    if (!Array.isArray(v) || v.length === 0) {
        throw new Error(`manifest: ${fieldPath} must be a non-empty array`);
    }
}

function requirePositiveInt(obj, fieldPath) {
    const v = resolvePath(obj, fieldPath);
    if (typeof v !== "number" || !Number.isInteger(v) || v <= 0) {
        throw new Error(`manifest: ${fieldPath} must be a positive integer`);
    }
}

function requireFingerprint(obj, fieldPath) {
    const v = resolvePath(obj, fieldPath);
    if (typeof v !== "string" || !/^[0-9A-F]+$/.test(v) || v.length < 40) {
        throw new Error(`manifest: ${fieldPath} must be an uppercase-hex PGP fingerprint (>= 40 chars)`);
    }
}

function resolvePath(obj, fieldPath) {
    // "a.b.c" or top-level "field". Bracketed paths not needed yet.
    const parts = fieldPath.split(".");
    let cur = obj;
    for (const p of parts) {
        if (cur == null) return undefined;
        cur = cur[p];
    }
    return cur;
}
