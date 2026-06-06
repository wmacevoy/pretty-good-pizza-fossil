// lib/shell.js
// Helpers for shelling out to system tools (openssl, gpg) with stdin input
// and stdout capture. Uses temp files for binary safety and simplicity.
// Same dependency posture as the Tcl predecessor: we trust system openssl
// and gpg rather than linking crypto/PGP libraries into the JS runtime.

import * as std from "std";
import * as os from "os";

function randomTmpPath(prefix) {
    const stamp = `${Date.now()}-${Math.floor(Math.random() * 1e9)}`;
    return `/tmp/${prefix}-${stamp}`;
}

function writeInputFile(path, input) {
    const f = std.open(path, "wb");
    if (f === null) throw new Error(`cannot open ${path} for write`);
    try {
        if (input == null) return;
        if (typeof input === "string") {
            f.puts(input);
        } else if (input instanceof Uint8Array) {
            f.write(input.buffer, 0, input.length);
        } else {
            throw new Error("input must be string, Uint8Array, or null");
        }
    } finally {
        f.close();
    }
}

function readOutputFileAsString(path) {
    const f = std.open(path, "rb");
    if (f === null) throw new Error(`cannot open ${path} for read`);
    try {
        return f.readAsString();
    } finally {
        f.close();
    }
}

function readOutputFileAsBytes(path) {
    const f = std.open(path, "rb");
    if (f === null) throw new Error(`cannot open ${path} for read`);
    try {
        // Seek to end to get size
        f.seek(0, std.SEEK_END);
        const size = f.tell();
        f.seek(0, std.SEEK_SET);
        const buf = new ArrayBuffer(size);
        const n = f.read(buf, 0, size);
        return new Uint8Array(buf, 0, n);
    } finally {
        f.close();
    }
}

// Run argv with `input` piped to stdin; return stdout as a UTF-8 string.
// Throws on nonzero exit.
export function runForString(argv, input) {
    const tmpIn = randomTmpPath("ppv-in");
    const tmpOut = randomTmpPath("ppv-out");
    writeInputFile(tmpIn, input);
    try {
        const fdIn = os.open(tmpIn, os.O_RDONLY);
        const fdOut = os.open(tmpOut, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600);
        try {
            const rc = os.exec(argv, { stdin: fdIn, stdout: fdOut });
            if (rc !== 0) {
                throw new Error(`${argv[0]} exited with status ${rc}`);
            }
        } finally {
            os.close(fdIn);
            os.close(fdOut);
        }
        return readOutputFileAsString(tmpOut);
    } finally {
        try { std.remove(tmpIn); } catch (e) {}
        try { std.remove(tmpOut); } catch (e) {}
    }
}

// Same as runForString, but returns stdout as a Uint8Array (for binary tools
// like `openssl dgst -binary`).
export function runForBytes(argv, input) {
    const tmpIn = randomTmpPath("ppv-in");
    const tmpOut = randomTmpPath("ppv-out");
    writeInputFile(tmpIn, input);
    try {
        const fdIn = os.open(tmpIn, os.O_RDONLY);
        const fdOut = os.open(tmpOut, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600);
        try {
            const rc = os.exec(argv, { stdin: fdIn, stdout: fdOut });
            if (rc !== 0) {
                throw new Error(`${argv[0]} exited with status ${rc}`);
            }
        } finally {
            os.close(fdIn);
            os.close(fdOut);
        }
        return readOutputFileAsBytes(tmpOut);
    } finally {
        try { std.remove(tmpIn); } catch (e) {}
        try { std.remove(tmpOut); } catch (e) {}
    }
}
