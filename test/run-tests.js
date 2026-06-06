#!/usr/bin/env qjs
// Test harness. Add real cases as implementation lands.

import * as std from "std";
import * as os from "os";
import * as cj from "../lib/canonical-json.js";
import * as manifest from "../lib/manifest.js";
import * as ballot from "../lib/ballot.js";
import * as tally from "../lib/tally.js";

function hexToBytes(hex) {
    hex = hex.trim();
    const out = new Uint8Array(hex.length / 2);
    for (let i = 0; i < out.length; i++) {
        out[i] = parseInt(hex.substr(i * 2, 2), 16);
    }
    return out;
}

function runTallyFixture(dir) {
    const m = manifest.load(`${dir}/manifest.json`);
    manifest.validate(m);
    const mh = manifest.canonicalHash(m);
    const [entries] = os.readdir(`${dir}/ballots`);
    const ballots = entries
        .filter((e) => e.endsWith(".json"))
        .sort()
        .map((e) => ballot.load(`${dir}/ballots/${e}`));
    const seed = hexToBytes(readFile(`${dir}/seed.hex`));
    return tally.run(m, ballots, seed, mh);
}

// Resolve repo root by walking up from this script's path.
function repoRoot() {
    const p = scriptArgs[0];
    const dir = p.substring(0, p.lastIndexOf("/"));
    return dir + "/..";
}

const REPO = repoRoot();

let passed = 0;
let failed = 0;

function test(name, fn) {
    try {
        fn();
        passed++;
        std.out.puts(`ok:   ${name}\n`);
    } catch (e) {
        failed++;
        std.out.puts(`FAIL: ${name} -- ${e.message}\n`);
    }
}

function readFile(path) {
    const f = std.open(path, "rb");
    if (f === null) throw new Error(`cannot open ${path}`);
    try {
        return f.readAsString();
    } finally {
        f.close();
    }
}

function expectThrow(fn, hint) {
    try {
        fn();
    } catch (e) {
        return e;
    }
    throw new Error(`expected throw (${hint})`);
}

// ── canonical-json round-trip ──────────────────────────────────

test("canonical-json: parse primitives", () => {
    if (cj.parse('"hi"') !== "hi") throw new Error("string");
    if (cj.parse("42") !== 42) throw new Error("int");
    if (cj.parse("-7") !== -7) throw new Error("neg int");
    if (cj.parse("true") !== true) throw new Error("true");
    if (cj.parse("false") !== false) throw new Error("false");
});

test("canonical-json: rejects floats", () => {
    const e = expectThrow(() => cj.parse("3.14"), "float");
    if (!e.message.includes("floating-point")) throw e;
});

test("canonical-json: rejects nulls", () => {
    const e = expectThrow(() => cj.parse("null"), "null");
    if (!e.message.includes("null is forbidden")) throw e;
});

test("canonical-json: tiny fixture canonical bytes match", () => {
    const fix = `${REPO}/test/fixtures/canonical-json`;
    const raw = readFile(`${fix}/tiny.json`);
    const parsed = cj.parse(raw);
    const canonical = cj.encode(parsed);
    const expected = readFile(`${fix}/tiny.canonical`).replace(/\n$/, "");
    if (canonical !== expected) {
        throw new Error(`bytes mismatch:\n   got: ${canonical}\n   exp: ${expected}`);
    }
});

test("canonical-json: tiny fixture SHA3-256 matches", () => {
    const fix = `${REPO}/test/fixtures/canonical-json`;
    const raw = readFile(`${fix}/tiny.json`);
    const parsed = cj.parse(raw);
    const hash = manifest.canonicalHash(parsed);
    const expected = readFile(`${fix}/tiny.sha3-256`).trim();
    if (hash !== expected) {
        throw new Error(`hash mismatch: got ${hash}, expected ${expected}`);
    }
});

// ── stub modules still error ───────────────────────────────────

test("manifest.load errors on missing file", () => {
    expectThrow(() => manifest.load("/nonexistent/manifest.json"), "missing file");
});

test("ballot.load errors on missing file", () => {
    expectThrow(() => ballot.load("/nonexistent/ballot.json"), "missing file");
});

// ── tally: end-to-end against frozen sampling fixtures ─────────

for (const name of ["mode-c-boundary-tie", "mode-a-replacement", "mode-b-no-replacement"]) {
    test(`tally: ${name} matches expected.json`, () => {
        const dir = `${REPO}/test/fixtures/sampling/${name}`;
        const got = runTallyFixture(dir);
        const expected = JSON.parse(readFile(`${dir}/expected.json`));
        const gotS = JSON.stringify(got);
        const expS = JSON.stringify(expected);
        if (gotS !== expS) {
            throw new Error(`mismatch:\n   got: ${gotS}\n   exp: ${expS}`);
        }
    });
}

std.out.puts(`\n${passed} passed, ${failed} failed\n`);
std.exit(failed > 0 ? 1 : 0);
