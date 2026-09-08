#!/usr/bin/env bash
# Root init.  Remap `mip` to PUID/PGID, fix ownership, seed the persist folder,
# then drop privileges with setpriv and hand off to run-server.sh.
#
# Deliberately does NOT: create symlinks (baked at build), put anything INTO
# Moods/ (yours alone), ship a register.key, or ever overwrite a file you have
# put in the persist folder.
set -u

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
ROAMING="/home/mip/.wine/drive_c/users/mip/AppData/Roaming/MusicIP/MusicIP Mixer"
DEF="/opt/defaults"

ts(){ date -u +%H:%M:%S; }
echo "[$(ts)] init (uid $(id -u)) — target mip ${PUID}:${PGID}"

# --- 1. Remap the service account.  Idempotent; -o permits a non-unique id.
if [ "$(id -g mip)" != "$PGID" ]; then groupmod -o -g "$PGID" mip; fi
if [ "$(id -u mip)" != "$PUID" ]; then usermod  -o -u "$PUID" -g "$PGID" mip; fi

# --- 2. Own the Wine prefix, but ONLY when ownership actually differs.
# Unconditional chown -R here would walk the mounted cache on every single boot.
if [ "$(stat -c '%u:%g' /home/mip)" != "$PUID:$PGID" ]; then
  echo "[$(ts)] chown /home/mip -> ${PUID}:${PGID}"
  chown -R "$PUID:$PGID" /home/mip
fi

# --- 3. Seed the persist folder.  PRECEDENCE TO USER-SUPPLIED FILES: anything
# already present is left strictly alone.  Delete a file and it comes back next
# boot with the default; to have "no recipes", leave an EMPTY recipes.xml.
mkdir -p "$ROAMING"
for f in mmm.ini recipes.xml README.txt; do
  if [ ! -e "$ROAMING/$f" ]; then
    echo "[$(ts)] seeding $f"
    cp "$DEF/$f" "$ROAMING/$f" 2>/dev/null || true
  fi
done
# register.key is NOT seeded — none is shipped.  The user drops their own here,
# or sets key= in mmm.ini.  See the warning below.
#
# default.m3lib is NOT seeded either.  A 0-byte placeholder half-works: music
# adds and mixes run, but MIP never adopts the file, never writes to it, and the
# web UI shows a "modified on disk" notice that cannot clear until /api/flush.
# cache= in mmm.ini names the path and MIP creates the file on first use —
# confirmed 2026-08-22: created and written 45 s after Add Music, no flush needed.
#
# Moods/ is created EMPTY if absent, and never populated.  The install-dir
# symlink points at it, so an existing (if empty) folder shows the user exactly
# where their .m3u moods go.  Binary .m3mood does NOT work headless.
mkdir -p "$ROAMING/Moods"
chown -R "$PUID:$PGID" "$ROAMING" 2>/dev/null || true

# --- 4. Loud warning if registration would silently fall back to unregistered.
if [ ! -s "$ROAMING/register.key" ] \
   && ! grep -qE '^key=.+' "$ROAMING/mmm.ini" 2>/dev/null; then
  echo "[$(ts)] WARNING: no register.key and no key= in mmm.ini — running UNREGISTERED"
fi

# --- 5. Clear stale /tmp state while STILL ROOT.  The image build runs
# `wineboot` as uid 1000, so the shipped /tmp already contains an X lock and a
# wine temp dir owned by 1000 and mode-restricted to their owner.  Any previous
# container run leaves the same.  When PUID is anything other than 1000, `mip`
# cannot remove them and wine dies with
#   wine: chdir to /tmp/wine-XXXXXX : Permission denied
# — Xvfb comes up, the server never starts, the API never answers.  Root can
# always clear them.  A no-op when /tmp is already clean.  The rm in
# run-server.sh runs post-setpriv and CANNOT do this; leave it, it is harmless.
rm -rf /tmp/.X99-lock /tmp/.X11-unix /tmp/wine-* /tmp/.wine-* /tmp/runtime-* 2>/dev/null || true
mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix
chmod 1777 /tmp 2>/dev/null || true

echo "[$(ts)] dropping to mip and starting server"
exec setpriv --reuid mip --regid mip --init-groups /home/mip/run-server.sh
