# MusicIP Mixer 1.96b — headless server under Wine.  BUILD v2.1.
#
#   debian:trixie-slim + Debian's distro Wine (win32) + Xvfb as a silent display.
#   No VNC, no fluxbox, no supervisord.
#
#   ONE persist mount: the MusicIP roaming folder.  It holds the cache, your own
#   registration key if you have one, Moods/, and TWO install-dir config files
#   (mmm.ini, recipes.xml) — symlinked into the install dir at BUILD time, so the
#   entrypoint never touches them.  Nothing MIP writes sits behind a file symlink.
#
#   CHANGES FROM v2.0 (the image running on the Debian host):
#     - register.key is no longer shipped.  Supply your own, or set key= in
#       mmm.ini.  MusicIP's own help says the SlimServer/LMS integration needs
#       no premium key, so this costs nothing for this image's purpose.
#     - Moods/ is created EMPTY in the persist folder instead of being left out.
#     - powerwords.txt is no longer seeded, persisted or symlinked — the headless
#       server provably does not read it.
#     - README.txt is seeded into the persist folder explaining all of the above.
#
#   The server runs UNPRIVILEGED as `mip`, whose UID/GID you choose at runtime
#   via PUID/PGID (default 1000:1000).  A small root init remaps that account,
#   fixes prefix ownership, seeds an empty persist folder, then drops privileges
#   with setpriv.  Bind mounts then "just work" on any host (Debian 1000:1000,
#   Synology e.g. 1027:65536) with no manual chown.
#
# Build context = PROJECT ROOT (needs ./mip_server_install_files).
FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive \
    WINEARCH=win32 \
    WINEPREFIX=/home/mip/.wine \
    WINEDLLOVERRIDES="mscoree=d;mshtml=d" \
    WINEDEBUG=fixme-all \
    DISPLAY=:99 \
    LANG=C.UTF-8 \
    HOME=/home/mip

# Debian's distro Wine (small, maintained) + headless X deps.
# curl/procps/x11-utils are kept deliberately: the readiness poll and the
# startup status line are the only diagnostics this image has.
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      wine wine32:i386 \
      xvfb xauth x11-utils curl procps ca-certificates \
 && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* \
           /usr/share/doc/* /usr/share/man/* /usr/share/info/* \
           /usr/share/locale/* /tmp/*

# Service account.  Created at 1000:1000; remapped to PUID/PGID at runtime.
# The NAME is fixed — it appears in the Wine profile path and in mmm.ini's
# cache= line, and must never vary.  Only the numeric id moves.
RUN groupadd -g 1000 mip \
 && useradd -u 1000 -g 1000 -m -s /usr/sbin/nologin mip

# Build the 32-bit Wine prefix as `mip`, at image-build time.
# (Baked, not built at runtime: instant reproducible first start, no wineboot
# that can fail on a recreate.  Costs ~228 MB; deliberate.)
USER mip
RUN xvfb-run -a sh -c 'wineboot --init; wineserver -w'
RUN mkdir -p "/home/mip/.wine/drive_c/Program Files/MusicIP/MusicIP Mixer" \
             "/home/mip/.wine/drive_c/users/mip/AppData/Roaming/MusicIP/MusicIP Mixer"
USER root

# Program payload -> install dir.  WHITELIST, not a folder copy: the payload
# folder keeps the full stock install, and only what the headless server needs
# is packed.  Adding a file back is one line here — the payload is untouched.
#
# WHY EACH ONE IS HERE
#   MusicMagicServer.exe  the server
#   mipcore.exe           the engine
#   AACTagReader.exe      named inside MusicMagicServer.exe (UTF-16) — AAC tags
#   dnssd.dll             STATIC IMPORT of MusicMagicServer.exe.  Not optional:
#                         missing = the loader refuses to start the program,
#                         regardless of tivo=0 / upnp=0.  Read from the PE
#                         import table, not inferred.
#   libexpat.dll          STATIC IMPORT — XML, i.e. recipes.xml
#   mmm.ini, recipes.xml  removed again below and symlinked to the mount
#   server/               the web UI
COPY --chown=1000:1000 [ \
  "mip_server_install_files/Program_Files/MusicMagicServer.exe", \
  "mip_server_install_files/Program_Files/mipcore.exe", \
  "mip_server_install_files/Program_Files/AACTagReader.exe", \
  "mip_server_install_files/Program_Files/dnssd.dll", \
  "mip_server_install_files/Program_Files/libexpat.dll", \
  "mip_server_install_files/Program_Files/mmm.ini", \
  "mip_server_install_files/Program_Files/recipes.xml", \
  "/home/mip/.wine/drive_c/Program Files/MusicIP/MusicIP Mixer/"]
COPY --chown=1000:1000 ["mip_server_install_files/Program_Files/server/", \
                        "/home/mip/.wine/drive_c/Program Files/MusicIP/MusicIP Mixer/server/"]

# DELIBERATELY NOT PACKED — all present in the payload folder, none in the image.
#
#   MusicMagicMixer.exe   the desktop GUI.  Not referenced by the server or by
#   bass.dll              mipcore in ASCII or UTF-16.  The Mixer statically
#   basscd.dll            imports BASS.dll + BASSCD.dll and loads the rest via
#   bassflac.dll          the wildcard "bass*.dll", so these four exist only to
#   basswma.dll           serve it.  All five go back together or not at all —
#                         needed if the headless-Mixer experiment is ever built.
#
#   powerwords.txt        The server holds the filename, but power words are
#                         measured dead on this binary WITH the file present:
#                         /api/mix?filter=<word> -> HTTP 500.  Shipping it only
#                         implies a feature that does not exist.
#
#   client.pem            TLS certs for music.predixis.com, dead since 2009.
#   root.pem              Named in the server binary, so it will look for them;
#                         a failed open on an already-impossible connection is
#                         the expected outcome.  THIS IS THE ONE UNTESTED
#                         OMISSION — if the server misbehaves, add these back
#                         first, before suspecting anything else.
#
#   ConnectionManager1.xml, ContentDirectory1.xml, discover.html,
#   mDNSResponder.exe, TiVoBeaconApi.dll, MusicMagicMixer.url, unins001.*
#                         UPnP/TiVo/installer leftovers.  None were in the
#                         payload that built v2.0, which has served a 109k
#                         library in production for a month.

# Seed defaults, stashed OUTSIDE the mount so the entrypoint can populate an
# empty persist folder.  A bind mount shadows anything the image places at the
# mount path, so these CANNOT simply be baked there.
COPY --chown=1000:1000 ["mip_server_install_files/Program_Files/mmm.ini",         "/opt/defaults/mmm.ini"]
COPY --chown=1000:1000 ["mip_server_install_files/Program_Files/recipes.xml",     "/opt/defaults/recipes.xml"]
# register.key is NOT shipped.  The user supplies their own in the persist
# folder, or sets key= in mmm.ini.  entrypoint.sh warns at boot if neither.
#
# Plain-English note seeded into the persist folder.  It lives at the payload
# ROOT, not in either subfolder: those two mirror real Windows locations
# (install dir / roaming dir) and this file belongs to neither.
COPY --chown=1000:1000 ["mip_server_install_files/persist_README.txt",            "/opt/defaults/README.txt"]

# Install-dir entries that live in the persist mount, symlinked at BUILD time.
# Dangling here — a symlink resolves by PATH on every open, so they come alive
# the moment the mount is populated.
#
# Moods is the non-obvious one.  On Windows MIP reads moods from
# %APPDATA%\MusicIP\MusicIP Mixer\Moods\, but IN THIS CONTAINER it does not —
# confirmed 2026-07 against a real cache: moods in the persist folder alone are
# never applied; mixing with &mood=<name> only works once Moods is visible in
# the INSTALL dir.  Hence this link.  Harmless if you keep no Moods/ folder.
#
# Capital `Moods` on BOTH ends, matching the original MIP layout on Windows.
# HB64 happens to use lowercase `moods`; Wine's drive_c is case-insensitive so
# either resolves.  If moods ever stop applying, case is the first thing to try.
RUN cd "/home/mip/.wine/drive_c/Program Files/MusicIP/MusicIP Mixer" \
 && R="/home/mip/.wine/drive_c/users/mip/AppData/Roaming/MusicIP/MusicIP Mixer" \
 && rm -f mmm.ini recipes.xml \
 && ln -s "$R/mmm.ini"     mmm.ini \
 && ln -s "$R/recipes.xml" recipes.xml \
 && ln -s "$R/Moods"       Moods

# powerwords.txt is NOT persisted, seeded or symlinked.  The headless server
# does not resolve power words at all — /api/mix?filter=<powerword> returns
# HTTP 500, /api/songs returns "No such filter" (measured; the official help
# documents the file with no such caveat).  Persisting it only invited users
# to edit a file that does nothing.
#
# The stock 770-byte file stays in the install dir, untouched, exactly as a
# real MusicIP install has it.  Deleting it would save nothing and has never
# been tested.

# Init (runs as root) + server launcher (runs as the dropped user).
COPY ["build-v2/entrypoint.sh",  "/usr/local/bin/entrypoint.sh"]
COPY --chown=1000:1000 ["build-v2/run-server.sh", "/home/mip/run-server.sh"]
# CRLF insurance — this repo is checked out on Windows.  A stray \r turns the
# shebang into `/usr/bin/env bash\r` and the container dies with a useless error.
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh /home/mip/run-server.sh \
 && chmod 0755 /usr/local/bin/entrypoint.sh /home/mip/run-server.sh

# /tmp must ship EMPTY.  The wineboot layer above runs as uid 1000 and leaves an
# X lock, an X socket dir and a wine temp dir behind, all owned by 1000 and
# mode-restricted to their owner.  Committed into the image, they make the
# container unusable for anyone whose PUID is not 1000: the dropped user cannot
# remove them and wine fails with "chdir to /tmp/wine-XXXXXX : Permission
# denied".  The earlier apt cleanup runs BEFORE wineboot and cannot catch these.
# entrypoint.sh clears them at boot as well; this stops them being shipped.
RUN rm -rf /tmp/* /tmp/.[!.]* 2>/dev/null || true

EXPOSE 10002
# Starts as root ONLY to remap the account, then drops (see entrypoint.sh).
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
