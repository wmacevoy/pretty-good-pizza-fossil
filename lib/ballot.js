// lib/ballot.js
// Ballot: load, validate (per-ballot rules 1-5 from docs/ballot-schema.md).
// Equivocation (rule 6) is a tally-time concern, handled there.

import * as std from "std";
import * as cj from "./canonical-json.js";

const VERSION = "ppv/1";

export function load(path) {
    const f = std.open(path, "rb");
    if (f === null) throw new Error(`ballot.load: cannot open ${path}`);
    let raw;
    try {
        raw = f.readAsString();
    } finally {
        f.close();
    }
    return cj.parse(raw);
}

// Validate one ballot against the manifest and the surrounding context.
//   b: parsed ballot
//   manifest: parsed manifest (already validated)
//   manifestHash: SHA3-256 hex of the canonical manifest bytes
//   signerFingerprint: clearsign signer fingerprint, from Fossil check-in metadata
//   checkInTime: ISO 8601 timestamp of the Fossil check-in (UTC)
export function validate(b, manifest, manifestHash, signerFingerprint, checkInTime) {
    if (b.version !== VERSION) {
        throw new Error(`ballot: version must be "${VERSION}"`);
    }
    if (b.election_id !== manifest.election_id) {
        throw new Error(`ballot: election_id "${b.election_id}" does not match manifest`);
    }
    if (b.manifest_hash !== manifestHash) {
        throw new Error(`ballot: manifest_hash does not match the manifest`);
    }
    if (typeof b.voter_fingerprint !== "string") {
        throw new Error(`ballot: voter_fingerprint must be a string`);
    }
    if (b.voter_fingerprint !== signerFingerprint) {
        throw new Error(`ballot: voter_fingerprint ${b.voter_fingerprint} does not match clearsign signer ${signerFingerprint}`);
    }
    const rosterFps = new Set(manifest.voters.map((v) => v.pgp_fingerprint));
    if (!rosterFps.has(b.voter_fingerprint)) {
        throw new Error(`ballot: voter_fingerprint ${b.voter_fingerprint} is not on the manifest roster`);
    }
    if (!Array.isArray(b.approvals)) {
        throw new Error(`ballot: approvals must be an array`);
    }
    const optionIds = new Set(manifest.options.map((o) => o.id));
    b.approvals.forEach((id, i) => {
        if (typeof id !== "string") {
            throw new Error(`ballot: approvals[${i}] must be a string`);
        }
        if (!optionIds.has(id)) {
            throw new Error(`ballot: approvals[${i}]="${id}" is not a valid option id`);
        }
    });
    const opens = Date.parse(manifest.schedule.voting_opens);
    const closes = Date.parse(manifest.schedule.voting_closes);
    const at = Date.parse(checkInTime);
    if (isNaN(at)) {
        throw new Error(`ballot: checkInTime "${checkInTime}" is not a valid ISO 8601 timestamp`);
    }
    if (at < opens) {
        throw new Error(`ballot: cast at ${checkInTime}, before voting_opens ${manifest.schedule.voting_opens}`);
    }
    if (at > closes) {
        throw new Error(`ballot: cast at ${checkInTime}, after voting_closes ${manifest.schedule.voting_closes}`);
    }
}
