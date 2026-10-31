# Cloud Browser Desktop — real Chrome in the cloud (Render free)

Real headed Google Chrome running inside a Docker container on Render's
**free** tier — no laptop, no card, no Playwright, no screenshots.
Open one public URL in any browser, enter the VNC password, and drive
real Chrome exactly like the original: tabs, address bar, extensions
UI, downloads, logins.

This is the always-available twin of the screenshot-based cloud browser
(`https://cloud-browser-3vcw.onrender.com`, which keeps working as the
fallback). Same pattern: Render free service, sleeps after 15 min idle,
wakes on visit.

## How it works

```
browser ──HTTPS/wss──▶ Render edge ──HTTP/WS──▶ websockify :$PORT
   (noVNC web client,   (TLS terminated          serves /usr/share/novnc
    same port)            at the edge)             + proxies VNC over WS
                                                        │
                                                   x11vnc 127.0.0.1:5900
                                                   (password required)
                                                        │
                                              Xvfb :99  1280x720x24
                                                        │
                                              real headed Chrome
                                              (one window, about:blank)
```

No desktop environment, no window manager — Chrome is the only X
client. `start.sh` runs the sequence: Xvfb → Chrome (restart loop) →
x11vnc → websockify in the foreground as the main process. Everything
logs to stdout/stderr (Render logs are the only diagnostics).

## How to open it

1. Open the Render URL, e.g. `https://cloud-browser-desktop.onrender.com`
   (first load after idle takes 30–60s: the free instance has to wake,
   then Chrome has to start).
2. The page redirects to the noVNC client. It asks for the **VNC
   password** — read it from the Render dashboard → service →
   Environment → `VNC_PASSWORD` (auto-generated at deploy; never in
   this repo). Enter it and click Connect.
3. You are looking at a real Chrome desktop (1280×720, scaled to your
   window). Use the address bar, open tabs, install extensions from
   the Chrome Web Store, download files — it is Chrome.
4. noVNC controls are in the sidebar (the tab on the left edge):
   full-screen, clipboard (copy/paste between your machine and the
   remote Chrome goes through the clipboard button), Ctrl+Alt+Del,
   disconnect.

## RAM budget (512 MB total — the whole design)

| Component | Expected |
|---|---|
| Xvfb 1280×720×24 (framebuffer ≈ 3.7 MB + server) | ~15–25 MB |
| x11vnc | ~10–20 MB |
| websockify (Python 3) | ~20–35 MB |
| Chrome `--single-process`, blank page | ~120–180 MB |
| Chrome, one light/medium site (e.g. example.org, Wikipedia) | ~200–300 MB |
| **Total, 1 tab** | **~260–380 MB — fits** |
| Chrome, one heavy site (Facebook, YouTube) | ~350–500 MB — at the edge, may OOM |
| Chrome, 2 light tabs | ~350–450 MB — tight but possible |

Why it fits: `--single-process` merges the renderer into the browser
process (saves roughly 100 MB of duplicated overhead),
`--disable-gpu` removes the GPU process, `--disable-dev-shm-usage`
avoids the 64 MB Docker `/dev/shm` limit, `--disable-extensions` /
`--disable-background-networking` cut background work. There is no
swap: if Chrome grows past 512 MB, Render kills the container and it
restarts to a blank Chrome.

## Honest limits

- **1–2 light tabs max.** Heavy sites (Facebook, YouTube, Google Docs
  with big docs) can push Chrome past 512 MB and kill the container.
- **`--single-process` is fragile:** one bad tab crashing kills the
  whole Chrome. The restart loop brings it back (blank page), but
  that tab's work is lost.
- **Slow.** Render free is 0.1 CPU. Chrome software-rendering +
  VNC encoding on 0.1 CPU means a few frames per second on screen
  changes and sluggish typing. Usable, not snappy.
- **Sleeps after 15 min idle, wakes on visit** (Render free rule).
  Waking takes 30–60s. A sleep also ends the Chrome session.
- **Nothing persists.** Render free disk is ephemeral: logins,
  extensions, downloads and history are gone on restart/sleep.
  Every wake is a fresh Chrome.
- **No audio.** VNC carries no sound.
- **VNC password is 8 characters effective.** VNC auth (DES) uses
  only the first 8 characters of the password. The generated value
  can be longer — typing the full value still works, because only
  its first 8 characters are compared. Treat it as an 8-char secret.
- **The VNC port is localhost-only** (`-localhost`): only websockify
  inside the container can reach it. The public side is protected by
  the VNC password + Render's HTTPS. Anyone with the URL + password
  can drive the desktop — share both only with the intended user.
