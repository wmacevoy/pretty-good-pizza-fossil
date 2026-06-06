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
    needString(m.version, "version");
    if (m.version !== VERSION) {
        throw new Error(`manifest: unsupported version "${m.version}"; expected "${VERSION}"`);
    }
    needString(m.election_id, "election_id");
    needString(m.title, "title");
    needString(m.description, "description");

    needObject(m.convener, "convener");
    needFingerprint(m.convener.pgp_fingerprint, "convener.pgp_fingerprint");
    needString(m.convener.name, "convener.name");

    needNonEmptyArray(m.voters, "voters");
    const fps = new Set();
    m.voters.forEach((v, i) => {
        needString(v.name, `voters[${i}].name`);
        needFingerprint(v.pgp_fingerprint, `voters[${i}].pgp_fingerprint`);
        if (fps.has(v.pgp_fingerprint)) {
            throw new Error(`manifest: duplicate voter fingerprint ${v.pgp_fingerprint}`);
        }
        fps.add(v.pgp_fingerprint);
    });
    if (!fps.has(m.convener.pgp_fingerprint)) {
        throw new Error(`manifest: convener fingerprint not in voters roster`);
    }

    needNonEmptyArray(m.options, "options");
    const ids = new Set();
    m.options.forEach((o, i) => {
        needString(o.id, `options[${i}].id`);
        needString(o.title, `options[${i}].title`);
        needPositiveInt(o.slices, `options[${i}].slices`);
        needPositiveInt(o.price, `options[${i}].price`);
        if (ids.has(o.id)) {
            throw new Error(`manifest: duplicate option id "${o.id}"`);
        }
        ids.add(o.id);
    });

    needObject(m.rule, "rule");
    const r = m.rule;
    needObject(r.threshold, "rule.threshold");
    if (!["absolute", "fraction", "top-k"].includes(r.threshold.type)) {
        throw new Error(`manifest: rule.threshold.type must be absolute|fraction|top-k`);
    }
    needPositiveInt(r.threshold.value, "rule.threshold.value");
    if (!["A", "B", "C"].includes(r.allocation)) {
        throw new Error(`manifest: rule.allocation must be A|B|C`);
    }
    needPositiveInt(r.budget, "rule.budget");
    if (!["random", "first", "alphabetic"].includes(r.tie_break)) {
        throw new Error(`manifest: rule.tie_break must be random|first|alphabetic`);
    }
    if (!["public", "group", "individual"].includes(r.privacy)) {
        throw new Error(`manifest: rule.privacy must be public|group|individual`);
    }
    if (r.privacy === "individual") {
        throw new Error(`manifest: rule.privacy="individual" is not supported in v1; see docs/threat-model.md mode 3`);
    }

    needObject(m.schedule, "schedule");
    needString(m.schedule.voting_opens, "schedule.voting_opens");
    needString(m.schedule.voting_closes, "schedule.voting_closes");
    if (Date.parse(m.schedule.voting_opens) >= Date.parse(m.schedule.voting_closes)) {
        throw new Error(`manifest: schedule.voting_opens must precede voting_closes`);
    }

    needObject(m.seed, "seed");
    if (!["nist-beacon", "commit-reveal"].includes(m.seed.protocol)) {
        throw new Error(`manifest: seed.protocol must be nist-beacon|commit-reveal`);
    }
}

export function canonicalHash(m) {
    const bytes = cj.encode(m);
    return sha3.sha3_256_hex(bytes);
}

// ── small validation helpers ─────────────────────────────────────
// Each takes the value to check and a label used in the error message.

function needString(v, label) {
    if (typeof v !== "string" || v.length === 0) {
        throw new Error(`manifest: ${label} must be a non-empty string`);
    }
}

function needObject(v, label) {
    if (typeof v !== "object" || v === null || Array.isArray(v)) {
        throw new Error(`manifest: ${label} must be an object`);
    }
}

function needNonEmptyArray(v, label) {
    if (!Array.isArray(v) || v.length === 0) {
        throw new Error(`manifest: ${label} must be a non-empty array`);
    }
}

function needPositiveInt(v, label) {
    if (typeof v !== "number" || !Number.isInteger(v) || v <= 0) {
        throw new Error(`manifest: ${label} must be a positive integer`);
    }
}

function needFingerprint(v, label) {
    if (typeof v !== "string" || !/^[0-9A-F]+$/.test(v) || v.length < 40) {
        throw new Error(`manifest: ${label} must be an uppercase-hex PGP fingerprint (>= 40 chars)`);
    }
}
