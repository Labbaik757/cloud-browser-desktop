# Cloud Browser Desktop — real headed Google Chrome streamed via noVNC
#
# Debian bookworm-slim base. No desktop environment: Chrome is the only
# X client, running on Xvfb. x11vnc mirrors the framebuffer, websockify
# serves the noVNC web client AND the VNC websocket proxy on the single
# port Render exposes ($PORT). No Playwright, no screenshots, no polling.
#
# RAM is the whole design: 512 MB total on Render free. See README.md
# for the budget. Chrome runs --single-process with the GPU off.

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# xvfb: virtual X server. x11vnc: VNC server for a real X display.
# novnc: browser VNC client (static files in /usr/share/novnc).
# python3-websockify: WebSocket-to-TCP proxy + mini web server
#   (the Debian binary package is python3-websockify; there is no
#   plain "websockify" apt package in bookworm).
# curl + ca-certificates: download the Chrome .deb over HTTPS.
# procps: ps/top for diagnostics via Render logs.
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    x11vnc \
    novnc \
    python3-websockify \
    curl \
    ca-certificates \
    procps \
 && curl -fsSL -o /tmp/google-chrome-stable_current_amd64.deb \
    https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
 && dpkg -i /tmp/google-chrome-stable_current_amd64.deb || true \
 && apt-get install -f -y \
 && rm -f /tmp/google-chrome-stable_current_amd64.deb \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# start.sh: Xvfb -> Chrome (restart loop) -> x11vnc -> websockify (foreground).
COPY start.sh /app/start.sh
# Landing page for GET / (Render health check + user entry point):
# redirects to the noVNC client with autoconnect + scaled view.
COPY index.html /usr/share/novnc/index.html

RUN chmod +x /app/start.sh

# No fixed EXPOSE: Render assigns the port via $PORT at runtime.
CMD ["/app/start.sh"]
