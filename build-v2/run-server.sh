#!/usr/bin/env bash
# Runs as the unprivileged `mip` (post-setpriv).  Brings up a silent Xvfb and
# launches the MusicIP server in console mode, then holds the container open.
set -u
export HOME=/home/mip
export WINEPREFIX=/home/mip/.wine
export WINEARCH=win32
export WINEDLLOVERRIDES="mscoree=d;mshtml=d"
export WINEDEBUG="${WINEDEBUG:-fixme-all}"
export DISPLAY=:99
export XDG_RUNTIME_DIR="/tmp/runtime-$(id -u)"

INSTALL="/home/mip/.wine/drive_c/Program Files/MusicIP/MusicIP Mixer"
URL="http://localhost:10002/api/getStatus"

ts(){ date -u +%H:%M:%S; }
echo "[$(ts)] server as $(id -un 2>/dev/null || id -u) $(id -u):$(id -g)"

mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"

# --- 1. Silent display sink.  A real but invisible X server is REQUIRED — with
# a null/black-hole driver the app cannot create its window and exits.
# Clear a stale lock first, or Xvfb refuses to start ("server already running").
rm -f /tmp/.X99-lock
Xvfb :99 -screen 0 1024x768x16 -nolisten tcp >/dev/null 2>&1 &
for _ in $(seq 1 50); do xdpyinfo -display :99 >/dev/null 2>&1 && break; sleep 0.2; done
echo "[$(ts)] Xvfb :99 up"

# --- 2. The launch.  The 'start' argument is what runs the server in console
# mode.  Bare MusicMagicServer.exe gives Error 1063 (wants the service
# controller); mipcore.exe alone just prints a banner and exits 0.
echo "[$(ts)] wine MusicMagicServer.exe start"
wine "$INSTALL/MusicMagicServer.exe" start 2>&1 | sed 's/^/  [mms] /' &

# --- 3. Wait for the API, then report once.  POLL, don't guess: a large cache
# (109k tracks) takes well over a minute to load, and a fixed sleep just makes
# the log lie.  NOTE: getStatus reads 'idle' even on a wedged server — this is a
# breadcrumb, not a health check.  Real liveness is a genuine /api/mix returning
# tracks (tools/mip_probe.py).
ready=""
for i in $(seq 1 180); do
  if curl -fsS "$URL" >/dev/null 2>&1; then
    ready="$i"
    break
  fi
  sleep 1
done
if [ -n "$ready" ]; then
  echo "[$(ts)] OK — API: $(curl -fsS "$URL")  (ready after ${ready}s)"
else
  echo "[$(ts)] API not responding after 180s — check the [mms] lines above"
fi
ps -ef | grep -iE 'MusicMagicServer|wineserver|Xvfb' | grep -v grep || true

# --- 4. Hold the container open (the server runs under wineserver).
echo "[$(ts)] holding"
exec tail -f /dev/null
