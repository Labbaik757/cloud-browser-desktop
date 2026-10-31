# TEST REPORT — Cloud Browser Desktop

## Status: NOT run live — deploy-ready, needs the Render deploy to prove it

This VM has no Docker and no internet path for Chromium, so the image
could **not** be built or run here. Everything below is what was
verified without running it. The real test is the Render deploy (the
parent runs it next).

## What was verified

1. **`bash -n start.sh` — PASS.** No syntax errors.
   Also re-read line by line: startup order (Xvfb → socket wait →
   Chrome loop → x11vnc → port wait → websockify foreground),
   `PORT="${PORT:-6080}"` default, VNC_PASSWORD gate exits 1 with a
   clear stderr message when unset, password stored then `unset`,
   `chmod 600` on the passwd file, stale X-lock cleanup, 15s timeouts
   on both waits with explicit failure exits.
2. **Debian package names — verified by web search against Debian
   sources (packages.debian.org, Server World Debian 12 guide, a
   DeepWiki stack doc):**
   - `xvfb`, `x11vnc`, `novnc` — real bookworm packages. bookworm
     ships novnc `1:1.3.0-1`.
   - `python3-websockify` — the correct apt package name. There is
     NO plain `websockify` apt package in bookworm; the Dockerfile
     installs `python3-websockify` (provides `/usr/bin/websockify`).
   - `novnc` installs its client to `/usr/share/novnc` with
     `vnc.html` at the top level — confirmed by the package file
     list. No `index.html` ships with it, so `COPY index.html`
     there does not overwrite a package file.
   - `websockify --web=/usr/share/novnc 6080 localhost:5900` is the
     documented invocation (Server World, DeepWiki) — web server +
     VNC proxy on one port, `--web=DIR` confirmed in the websockify
     man page.
3. **`x11vnc -storepasswd <pass> <file>` — verified against the
   x11vnc man page:** two-argument form stores non-interactively
   and exits. Also confirmed: `-rfbauth`, `-forever`, `-shared`,
   `-localhost`, `-noxdamage`, `-rfbport` are all real flags; and
   VNC auth uses only the first 8 password characters (DES key).
4. **Chrome .deb URL** — `https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb`
   is the canonical direct-download URL used in standard Chrome
   Dockerfiles. The `dpkg -i || true` then `apt-get install -f -y`
   pattern is the standard way to resolve its dependencies.
5. **Chrome flags** — `--no-sandbox`, `--single-process`,
   `--disable-gpu`, `--disable-dev-shm-usage`, `--disable-extensions`,
   `--no-first-run`, `--disable-default-apps`,
   `--disable-background-networking`, `--window-size`,
   `--window-position`, `--user-data-dir`, `--no-default-browser-check`,
   `--disable-crash-reporter`, `--disable-breakpad` are all real
   Chrome switches. Chrome reads the display from the `DISPLAY`
   environment variable (exported in start.sh) — there is no
   `--display` flag, and none is used.
6. **`render.yaml`** — mirrors the proven `cloud-browser` service
   (Docker runtime, free plan, `healthCheckPath: /`,
   `generateValue: true` env var). Same shape that already deployed
   successfully for the screenshot cloud browser.
7. **Health check** — `GET /` is served by websockify from
   `/usr/share/novnc/index.html` (the redirect page), which returns
   200 with HTML. Render's health check only needs the 200.

## Unverified assumptions (must be proven by the Render deploy)

1. That the Docker build succeeds: package names are verified, but
   the exact dependency closure of the Chrome .deb on bookworm-slim
   (via `apt-get install -f`) has not been built here.
2. That websockify serves `index.html` for a bare `GET /` (directory
   request). Its mini-webserver is documented to serve files from
   `--web`; the index-for-directory behaviour is standard for it but
   was not observed here. If Render's health check fails, the fix is
   a tiny change (serve the redirect differently), not a redesign.
3. That noVNC 1.3.0 honours the `autoconnect=true&resize=scale&
   reconnect=true` URL params (standard noVNC params, but not
   observed against the Debian build).
4. That Render's edge proxies WebSocket (`wss`) connections to a
   free Docker service. Render documents WebSocket support on web
   services; the existing cloud browser only uses HTTP polling, so
   this is a new dependency for this service.
5. That Chrome `--single-process` starts and renders on Xvfb in this
   container (standard headless-X pattern, but the exact flag set
   has not been run here).
6. That `x11vnc -storepasswd` writes the file without prompting
   when both arguments are given (man-page confirmed, but not run).
7. That the whole stack fits in 512 MB in practice — the RAM math
   in README.md is an estimate (see table). The deploy must be
   watched: open example.org, then a heavier site, and check
   whether the container survives.
8. That Chrome's first-run behaviour with `--user-data-dir=/tmp/chrome-data`
   does not block on any dialog (mitigated by `--no-first-run` and
   `--no-default-browser-check`, but not observed).

## If the deploy fails, check in this order

1. Render build log: apt/dpkg errors (package name or Chrome .deb
   problem) → fix Dockerfile.
2. Runtime log: "VNC_PASSWORD is not set" → the env var did not get
   generated; set it manually in Render Environment.
3. Runtime log: "Xvfb did not create … in 15s" → Xvfb failed to
   start (check the log lines above it).
4. Runtime log: "x11vnc did not listen on 5900 in 15s" → x11vnc
   failed (password file or display problem).
5. Health check failing on `/` → websockify web-root behaviour
   (assumption 2 above).
6. Page loads but noVNC never connects → WebSocket through Render
   (assumption 4) or the VNC password prompt rejecting the value
   (remember: only the first 8 characters matter).
