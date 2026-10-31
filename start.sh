#!/bin/bash
# Cloud Browser Desktop — startup sequence.
#
#   Xvfb :99 (1280x720x24) -> real headed Chrome (restart loop)
#     -> x11vnc on 127.0.0.1:5900 (password required)
#     -> websockify in the FOREGROUND on $PORT (serves the noVNC web
#        client and proxies the VNC websocket on the same port).
#
# websockify is the main process (exec): if it exits, the container
# exits and Render restarts it. Everything logs to stdout/stderr —
# Render logs are the only diagnostics.
#
# Required env: VNC_PASSWORD (Render generates it via render.yaml).
# If it is unset, the container refuses to start — same rule as the
# cloud browser's token. The password is stored once with
# x11vnc -storepasswd and never written to any file in the repo.

set -e

# ---- 1. Auth gate -------------------------------------------------------
if [ -z "${VNC_PASSWORD:-}" ]; then
  echo "ERROR: VNC_PASSWORD is not set. Set it (Render generates it via render.yaml) and restart." >&2
  exit 1
fi

PORT="${PORT:-6080}"
DISPLAY_NUM=99
VNC_PASSWD_FILE="/tmp/vncpasswd"

# ---- 2. Store the VNC password ------------------------------------------
# -storepasswd <pass> <file> is non-interactive and exits after writing.
# NOTE: VNC auth uses only the first 8 characters of the password
# (DES key) — a longer generated value still works, only its first
# 8 characters are compared. The file is obfuscated, not encrypted:
# keep it chmod 600 and in /tmp (never in the repo).
x11vnc -storepasswd "$VNC_PASSWORD" "$VNC_PASSWD_FILE"
chmod 600 "$VNC_PASSWD_FILE"
unset VNC_PASSWORD
echo "VNC password stored."

# ---- 3. Clean stale X locks (fresh container, but harmless) -------------
rm -f "/tmp/.X${DISPLAY_NUM}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM}"

# ---- 4. Start Xvfb --------------------------------------------------------
Xvfb ":${DISPLAY_NUM}" -screen 0 1280x720x24 -ac -nolisten tcp &
echo "Xvfb started (pid $!) on :${DISPLAY_NUM} (1280x720x24)."

# ---- 5. Wait for the X socket (max ~15s) ---------------------------------
for i in $(seq 1 30); do
  if [ -S "/tmp/.X11-unix/X${DISPLAY_NUM}" ]; then
    echo "X socket ready."
    break
  fi
  sleep 0.5
  if [ "$i" = "30" ]; then
    echo "ERROR: Xvfb did not create /tmp/.X11-unix/X${DISPLAY_NUM} in 15s. Exiting." >&2
    exit 1
  fi
done

export DISPLAY=":${DISPLAY_NUM}"

# ---- 6. Chrome restart loop (background) ----------------------------------
# One window, 1280x720, about:blank. --single-process merges the
# renderer into the browser process (saves ~100 MB on 512 MB RAM).
# --disable-dev-shm-usage: /dev/shm in Docker is only 64 MB, Chrome
# would crash on it; /tmp is used instead. --no-sandbox: required
# because Chrome runs as root in the container.
(
  while true; do
    echo "Starting Chrome..."
    google-chrome-stable \
      --no-sandbox \
      --single-process \
      --disable-gpu \
      --disable-dev-shm-usage \
      --disable-extensions \
      --no-first-run \
      --disable-default-apps \
      --disable-background-networking \
      --no-default-browser-check \
      --disable-crash-reporter \
      --disable-breakpad \
      --window-size=1280,720 \
      --window-position=0,0 \
      --user-data-dir=/tmp/chrome-data \
      about:blank
    echo "Chrome exited; restarting in 2s."
    sleep 2
  done
) &
echo "Chrome supervisor started."

# Give Chrome a moment to create its window before VNC starts polling.
sleep 2

# ---- 7. x11vnc ------------------------------------------------------------
# -localhost: only websockify (same container) can reach the VNC port.
# -forever -shared: stay up across client disconnects, allow reconnects.
# -noxdamage: avoids X DAMAGE artefacts with Xvfb.
x11vnc -display ":${DISPLAY_NUM}" -forever -shared -localhost -noxdamage \
  -rfbport 5900 -rfbauth "$VNC_PASSWD_FILE" -quiet &
echo "x11vnc started on 127.0.0.1:5900."

# ---- 8. Wait for the VNC port (max ~15s) ----------------------------------
for i in $(seq 1 30); do
  if (exec 3<>/dev/tcp/127.0.0.1/5900) 2>/dev/null; then
    echo "VNC port 5900 listening."
    break
  fi
  sleep 0.5
  if [ "$i" = "30" ]; then
    echo "ERROR: x11vnc did not listen on 5900 in 15s. Exiting." >&2
    exit 1
  fi
done

# ---- 9. websockify in the foreground (main process) -----------------------
# Serves the noVNC client from /usr/share/novnc AND proxies VNC over
# WebSocket on the same port. Render terminates TLS at the edge, so
# the container speaks plain HTTP/WS. --heartbeat keeps the socket
# alive through Render's proxy. Binds 0.0.0.0 by default.
echo "Starting websockify on port ${PORT} (web root /usr/share/novnc, VNC target localhost:5900)."
exec websockify --web=/usr/share/novnc --heartbeat 30 "${PORT}" localhost:5900
