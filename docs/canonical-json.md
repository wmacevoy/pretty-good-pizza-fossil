# Canonical JSON

This spec defines the byte-exact serialization used to hash the election manifest. Every implementation must produce the same bytes for the same logical manifest; otherwise `manifest_hash` diverges and ballots no longer verify.

## Standard

The canonicalization is **RFC 8785 (JSON Canonicalization Scheme, JCS)**, restricted to a subset of JSON types defined below.

JCS is short, normative, and has reference implementations in C, Python, JavaScript, Go, and Java. Adopting it instead of inventing a new scheme means future auditors can verify by reading RFC 8785, not by reading us.

## Permitted JSON types

The manifest and ballot schemas are restricted to:

- **string** (UTF-8)
- **integer** (no decimal point, no exponent)
- **boolean** (`true` / `false`)
- **array** (ordered list; canonicalization preserves order)
- **object** (key-value map; canonicalization sorts keys by UCS code point)

Explicitly **forbidden**:

- **Floating-point numbers.** Every numeric field is an integer by schema. The one place a fraction is conceptually present is `threshold.value` when `threshold.type` is `"fraction"`; even there it is an integer numerator with an implicit denominator (`{"type": "fraction", "value": 5}` means 5%, denominator 100; spelled out in `manifest-schema.md`).
- **`null`.** Express absence by omitting the field or using an empty array, not `null`.
- **Embedded JSON-encoded strings.** All structured data lives in proper JSON fields, never in stringified blobs.

These restrictions sidestep the corner cases where JCS would otherwise need to make policy choices (IEEE 754 number formatting, null vs. missing-key equivalence).

## Procedure to compute `manifest_hash`

1. Load the manifest as a logical JSON value.
2. Validate it against the schema (in particular: numeric fields are integers).
3. Apply JCS to produce canonical UTF-8 bytes.
4. Compute SHA3-256 of those bytes.
5. Encode as uppercase hexadecimal (40 hex digits per byte pair, no spaces).

## Worked example

Logical input:

```json
{
  "version": "ppv/1",
  "election_id": "tiny",
  "options": [
    {"id": "x", "slices": 1, "price": 10},
    {"id": "y", "slices": 1, "price": 20}
  ]
}
```

Canonical bytes (one line; keys sorted; no whitespace; array order preserved):

```
{"election_id":"tiny","options":[{"id":"x","price":10,"slices":1},{"id":"y","price":20,"slices":1}],"version":"ppv/1"}
```

`manifest_hash` = `SHA3-256(<those bytes>)` rendered as uppercase hex.

The exact hex digest for this input will be added as `test/fixtures/canonical-json/tiny.expected` once the canonicalizer is implemented. That fixture is the source of truth for byte-level disputes between implementations.

## Failure mode and recovery

If two implementations disagree on `manifest_hash` for the same logical input, the regression fixture catches it on the first run. Resolution is to read RFC 8785 against the implementation that disagrees with the reference output; do not attempt to reconcile by changing the reference.
