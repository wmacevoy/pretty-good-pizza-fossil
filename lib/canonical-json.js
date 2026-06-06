// lib/canonical-json.js
// Restricted-subset JSON parser and canonical encoder per RFC 8785 (JCS).
// See docs/canonical-json.md for the subset definition.
//
// JSON.parse handles parsing; we add a subset check (no nulls, no floats)
// and a canonical re-emitter (sorted keys, no whitespace, minimal escapes).
//
// Integer precision: JSON.parse returns numbers as JS doubles. For values
// within Number.MAX_SAFE_INTEGER, this is exact. The manifest schema bounds
// integer fields well within that range; runtime-computed sampling weights
// use BigInt natively and never round-trip through JSON.parse.

export function parse(text) {
    const v = JSON.parse(text);
    assertSubset(v, []);
    return v;
}

function assertSubset(v, path) {
    const here = path.length ? path.join(".") : "<root>";
    if (v === null) {
        throw new Error(`canonical-json: null is forbidden in this subset (at ${here})`);
    }
    if (typeof v === "number") {
        if (!Number.isInteger(v)) {
            throw new Error(`canonical-json: floating-point numbers are forbidden (at ${here})`);
        }
        return;
    }
    if (typeof v === "string" || typeof v === "boolean" || typeof v === "bigint") return;
    if (Array.isArray(v)) {
        v.forEach((c, i) => assertSubset(c, [...path, `[${i}]`]));
        return;
    }
    if (typeof v === "object") {
        for (const k of Object.keys(v)) {
            assertSubset(v[k], [...path, k]);
        }
        return;
    }
    throw new Error(`canonical-json: unsupported type at ${here}: ${typeof v}`);
}

export function encode(v) {
    if (typeof v === "string") return encodeString(v);
    if (typeof v === "boolean") return v ? "true" : "false";
    if (typeof v === "number") {
        if (!Number.isInteger(v)) {
            throw new Error(`canonical-json: cannot encode non-integer number ${v}`);
        }
        return String(v);
    }
    if (typeof v === "bigint") return v.toString();
    if (Array.isArray(v)) {
        return "[" + v.map(encode).join(",") + "]";
    }
    if (typeof v === "object" && v !== null) {
        // Sort keys by UCS code point. JS default string compare uses UTF-16
        // code unit order, which matches UCS-2 codepoint order for the BMP.
        // All our schema keys are ASCII, so this is equivalent to UCS order.
        const keys = Object.keys(v).sort();
        const parts = keys.map((k) => `${encodeString(k)}:${encode(v[k])}`);
        return "{" + parts.join(",") + "}";
    }
    if (v === null) throw new Error("canonical-json: null is forbidden");
    throw new Error(`canonical-json: unsupported type for encode: ${typeof v}`);
}

function encodeString(s) {
    let out = '"';
    for (let i = 0; i < s.length; i++) {
        const c = s.charCodeAt(i);
        const ch = s[i];
        if (ch === '"') out += '\\"';
        else if (ch === "\\") out += "\\\\";
        else if (c === 0x08) out += "\\b";
        else if (c === 0x09) out += "\\t";
        else if (c === 0x0a) out += "\\n";
        else if (c === 0x0c) out += "\\f";
        else if (c === 0x0d) out += "\\r";
        else if (c < 0x20) out += "\\u" + c.toString(16).padStart(4, "0");
        else out += ch;
    }
    out += '"';
    return out;
}
