# Future: ppv homeserver

Captured as a sketch from design discussion. Not part of the v1 voting deliverable; lives here so we can pick it up after voting is done.

## The idea

A "homeserver" model that turns ppv-the-protocol into ppv-the-product for non-technical users. Each user has a tiny always-on node (Pi Zero 2 W, or a cheap VPS) that holds their Fossil repos and exposes a browser-friendly UI. Peers sync server-to-server using Fossil's native protocol. The model is operationally similar to Matrix/Mastodon: federated, not centralized.

The voting protocol is just one of the things a homeserver might host. The model also enables peer-private journaling, shared chronicles, and any other Fossil-as-substrate use case.

## Why a Pi Zero 2 W is enough

- Cortex-A53 has ARMv8 crypto extensions; SQLCipher AES is fast.
- 512MB RAM is plenty for a single-user-or-small-group homeserver.
- Network and idle power (~0.7-3W) are well within battery / solar / USB budget.
- Storage cap is the real constraint, not CPU: 32GB microSD covers years of personal use plus backups for a handful of friend-peers. Industrial SD or USB SSD addresses the long-term reliability concern.

## Architecture sketch

Four services per homeserver, all small:

1. **`fossil-ppv server`** — the custom Fossil binary as an HTTP server. Listens on the Tailscale (or self-hosted Headscale) interface only; never exposed to the public internet. Handles peer-to-peer sync via Fossil's protocol and serves the web UI to the owner's browser.
2. **WebSocket bridge** — small daemon (could be ~100 lines of QuickJS) that holds open WSS connections to the owner's browser(s), watches the repo for new artifacts, and pushes change-notifications. Browser-to-server uses WSS so the owner sees peer updates without polling.
3. **`rest-server`** — restic's REST backend. Provides encrypted-blob backup endpoint for friends to push their private `.efossil` snapshots to. Holds opaque ciphertext only.
4. **Backup cron** — periodic `fossil backup` → `restic backup` to a friend-peer's `rest-server`. Atomic snapshot, encrypted-at-rest, deduplicated and incremental.

Plus **tailscaled** for the mesh networking layer. Each Pi gets a stable address regardless of NAT; ACLs limit which peers can reach which services.

## The two sync paths

The peers-mirror-everything story splits into two channels because shared and private repos have different access semantics:

- **Shared repos** sync via Fossil's native protocol. Mode 2 with a roster of trusted peers means every peer's Pi holds the full content. Lose one Pi, the data lives on the others. RAID-1 across peers, for free.
- **Private repos** are backed up as opaque blobs via restic, not synced as Fossil artifacts. Backup peers hold ciphertext only; they can't read your private journal even if you trust them enough to be your backup. Lose your Pi entirely → pull the latest ciphertext snapshot back from a backup peer, decrypt locally with your gpg key, you're back.

## What to ship

The smallest interesting bundle is an SD card image with:

- `fossil-ppv`, the WebSocket bridge, `rest-server`, and `tailscaled` running as systemd services.
- A first-boot wizard guided from the user's phone (via Tailscale's pairing URL flow).
- A pre-installed browser PWA that the owner opens at `https://<pi-hostname>.taili.net/ppv/`.

For non-technical users without a friend who can DIY the SD card route: a hosted "homeserver-as-a-service" offering, where the operator runs Pis-equivalent on the user's behalf. User's keys stay in their browser; operator sees only ciphertext. Same trust model as self-hosting, none of the setup.

## Why this isn't part of v1

The voting protocol stands on its own as a CLI + custom Fossil binary. Federation works today through any HTTP-reachable Fossil sync target. The homeserver model adds operational polish (PWA UX, push notifications, atomic backups, mesh networking) that's worth its own focused effort rather than being entangled with finishing voting.

## Open questions for when we pick this up

- Is the canonical "homeserver" image based on Raspberry Pi OS, Alpine, or NixOS? (Reproducibility argues for Nix; familiarity argues for Pi OS.)
- Self-hosted Headscale vs. Tailscale-the-service for the mesh layer. Self-hosted preserves the "no central authority" property but is more setup work.
- WebSocket bridge as a Fossil patch (more invasive, less to deploy) vs. a separate daemon (simpler, one more service).
- Browser PWA architecture: is it a `bin/ppv` JS module compiled for browser execution, or a separate codebase that shares schemas only?
