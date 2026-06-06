// lib/gpg.js
// gpg shell-outs: list secret keys, multi-recipient encrypt.
// Same dependency posture as the rest of the CLI: trust system `gpg`, no
// libgpgme link.

import { runForString } from "./shell.js";

// Returns a list of { fingerprint, uid, expired } for the convener/voter's
// gpg secret keys. The list reflects what's in the local keyring at this
// moment (including smart-card-resident keys via gpg-agent).
//
// Filters out expired keys (expiration date in the past). Does NOT filter
// revoked keys here; gpg surfaces revocation through trust validity flags
// that are domain-specific and best handled at the caller's policy layer.
export function listUsableSecretKeys() {
    const out = runForString(
        ["gpg", "--list-secret-keys", "--with-colons", "--fixed-list-mode"],
        null
    );
    const keys = [];
    let cur = null;
    for (const line of out.split("\n")) {
        const fields = line.split(":");
        const rec = fields[0];
        if (rec === "sec") {
            if (cur && cur.fingerprint) keys.push(cur);
            const expiresStr = fields[6] || "";
            const expiresSec = expiresStr ? Number(expiresStr) : 0;
            const expired = expiresSec > 0 && expiresSec * 1000 < Date.now();
            cur = { fingerprint: null, uid: null, expired };
        } else if (rec === "fpr" && cur && !cur.fingerprint) {
            cur.fingerprint = fields[9];
        } else if (rec === "uid" && cur && !cur.uid) {
            cur.uid = fields[9];
        }
    }
    if (cur && cur.fingerprint) keys.push(cur);
    return keys.filter((k) => k.fingerprint && !k.expired);
}

// Encrypt the given string (typically hex bytes) to multiple PGP recipients,
// writing armored output to outPath. Uses --trust-model always because the
// convener's keyring may not have signed every roster member's key; the
// caller has already verified roster membership at the schema level.
export function encryptToRecipients(input, recipients, outPath) {
    if (!Array.isArray(recipients) || recipients.length === 0) {
        throw new Error("gpg.encryptToRecipients: at least one recipient required");
    }
    const args = [
        "gpg",
        "--encrypt", "--armor",
        "--trust-model", "always",
        "--output", outPath,
        "--yes", // overwrite outPath if it exists; convener is replacing the blob
    ];
    for (const fp of recipients) {
        args.push("--recipient", fp);
    }
    // runForString writes stdin to a temp file then redirects; gpg reads
    // plaintext from stdin, writes ciphertext to --output. Output capture
    // is irrelevant here, but the routine throws on nonzero exit.
    runForString(args, input);
}
