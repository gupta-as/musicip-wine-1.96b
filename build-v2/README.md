# MusicIP 1.96b headless — build v2

A clean rebuild. Not a fork of v1.1: the design was re-derived from scratch, keeping only
mechanics proven by the running production image.

## Design in one page

**One persist mount.** The MusicIP roaming folder is the only thing you mount. It holds the
cache, the registration key, `Moods/`, and the three install-dir config files. Flat, one
subfolder:

```
/data/docker/mip/
├── Moods/            <- the only subfolder; yours, never seeded
├── default.m3lib     <- your real cache
├── mmm.ini
├── powerwords.txt
├── recipes.xml
└── register.key
```

Start it empty and the five files seed themselves. `Moods/` is never created or seeded —
supply it or run without.

**Four symlinks, baked at build time.** These must appear in the install dir next to the exe,
so the image links them out to the persist folder:

```
<install>/mmm.ini        -> <roaming>/mmm.ini
<install>/recipes.xml    -> <roaming>/recipes.xml
<install>/powerwords.txt -> <roaming>/powerwords.txt
<install>/Moods          -> <roaming>/Moods
```

`Moods` is the non-obvious one. On Windows MIP reads moods from
`%APPDATA%\MusicIP\MusicIP Mixer\Moods\`, but **in this container it does not** — confirmed
against a real cache: moods sitting in the persist folder alone are never applied, and
`&mood=<name>` only works once they are visible in the install dir. The link is harmless
if you keep no `Moods/` folder.

Capital `Moods` on both ends, matching the original MIP layout. HB64 uses lowercase `moods`;
Wine's `drive_c` is case-insensitive so either resolves. If moods ever stop applying, case
is the first thing to try.

They dangle at build time and resolve once the mount is populated. Symlinks bind by *path*,
so editing on the host works normally — unlike single-file bind mounts, which bind by inode
and silently serve a stale file after any editor that saves by rename (VS Code, vim, `sed -i`).

**Precedence to user-supplied files.** Seeding never overwrites. Anything already in the
persist folder wins, always.

**The cache path is a literal.** `mmm.ini` names it outright:

```ini
cache=c:\users\mip\AppData\Roaming\MusicIP\MusicIP Mixer\default.m3lib
```

This must agree with the compose mount path and with the username baked into the image.
Get it wrong and MIP does not error — it quietly builds a fresh empty cache inside the
container. It is the single most important line to keep in sync.

**PUID/PGID.** The account name `mip` is fixed; only the numeric id moves. A root init
remaps it, chowns the prefix *only if ownership differs*, seeds, then drops with `setpriv`.
The conditional chown matters here specifically because the cache lives in the mount.

## Build and run

```powershell
cd build-v2
docker compose up -d --build     # builds musicip-wine:2.0
docker logs mip                  # expect: OK — API: idle
# http://localhost:10002
```

Build context is the **project root** — it needs `mip_server_install_files/`.

Deploy to Debian with `docker-compose.debian.yml` (host-networked). Synology: same image,
set `PUID`/`PGID` from `id <your_user>`; check `uname -m` is `x86_64` first, since 32-bit
Wine cannot run on ARM models.

## Verify on first boot

1. `docker logs mip` → `OK — API: idle`, and no UNREGISTERED warning.
2. `ls -l "<install>/mmm.ini"` → still a symlink.
3. Web UI loads, Add Music prefilled `Z:\music`.
4. `curl 'http://localhost:10002/api/mix?song=…&size=5'` returns tracks.
5. **Moods** — a mood needs no seed, so this is enough:
   `http://localhost:10002/api/mix?sizetype=tracks&size=10&mood=<name>`
   Answered 2026-07 against a real cache: the install-dir symlink **is** required, and
   **only `.m3u` moods work headless.** Binary `.m3mood` neither lists nor mixes — author
   moods in `MusicMagicMixer.exe` on Windows and save them as `.m3u`.
   Confirmed working in one request: `mood` + `filter` + `style` + `variety` + `sizetype`.

Fastest way to run 1–3 without a music mount: drop a real `default.m3lib` into the persist
folder. MIP mixes from the acoustic data in the cache, not from the files, so a full library
is testable with nothing mounted at `/music`. Do not click Add Music or Refresh in that
state — MIP would scan, find nothing, and could mark tracks unanalysable.

## What changed from v1.1

| | v1.1 | v2 |
|---|---|---|
| Mounts | 1 (deep roaming path) | 1 (same path, `mip` not `docrusr`) |
| Symlinks | 4, created at runtime | 4, baked at build |
| Moods | seeded + symlinked into install dir | symlinked; never seeded or created |
| Cache seeding | seeded, cache path only | seeded, overridable |
| Install dir | `Program Files (x86)` | `Program Files` (idiomatic for a win32 prefix) |
| Payload | 24 files | 15 files + `server/` |
| Locale purge | no | yes |
| CRLF guard | no | yes |
| Stale X lock | no | `rm -f /tmp/.X99-lock` |
| `XDG_RUNTIME_DIR` | unset | set |

## Server binary vs Mixer binary — the limits of this image

The official help documents the API as belonging to **`MusicMagicMixer.exe`**, the GUI app
("In order to use this API, you must have a running copy of the MusicIP Mixer"). This image
runs **`MusicMagicServer.exe`**, the headless service binary, which is a **subset**. Two
documented features are absent from it:

| Feature | Mixer | Server (this image) |
|---|---|---|
| Inline Power Search, `filter=?expr` | works | `No such filter` |
| Binary `.m3mood` moods | works, listed as `Name (m3mood)` | `invalid request or internal error` |

Confirmed 2026-07 both ways: `?composer=Rudy Martinez` succeeds against a registered Windows
Mixer API, and fails in the container. Binary moods fail identically on Docker Desktop and on
the Debian production host against the real 109k library — so it is the binary, not the
platform or the cache. String analysis agrees — `Power Search` / `powersearch`
appear only in `MusicMagicMixer.exe`, never in `MusicMagicServer.exe` or `mipcore.exe`, and
`.m3mood` appears 8× in the Mixer against 1× in the server.

**Not a registration problem — settled for binary moods.** `.m3mood` files do not work under
`MusicMagicServer.exe` **with a licence key present**. Retested with
`key=<a valid key>` in `mmm.ini` and again on a registered production instance:
no change, same failure. Creating an `.m3mood` needs a key; reading one does not. Do not
re-investigate this.

Inline Power Search is *less* settled. It too fails in the container with a key set, but the
Windows instance it was compared against is both *Mixer* and *registered*, so binary-vs-licence
was never separated for that feature alone. Running `MusicMagicServer.exe start` on the
registered Windows install would do it. The string analysis above makes the binary the likely
cause either way.

**Future avenue.** `MusicMagicMixer.exe` is kept in the payload and the container already has
an Xvfb it could draw on. Running the Mixer headless instead of the server would plausibly
give Power Search and binary moods over HTTP — which for SugarCube means composing filters
per request instead of hand-authoring named filters in advance, and reviving `setSongField`
custom fields (`field "bpm"` is Power Search syntax). Untested; the Mixer may want more of
Wine and may raise dialogs nothing can dismiss.

## Carried forward — proven mechanics, do not re-derive

- `MusicMagicServer.exe start` is the launch. Bare exe → Error 1063; `mipcore.exe` → banner, exit 0.
- A real but **invisible** Xvfb is required; a null display driver makes the app exit.
- Debian distro Wine, `win32`. WineHQ was ~4 GB for no benefit.
- `cache=` is a literal path, not a discovered one.
- **Moods must be visible in the install dir.** True in this container and in HB64's, and
  *not* true of MIP on Windows — so the Windows layout is not a guide here. Retested
  2026-07 against a real cache after being challenged; the original finding held.
- **Only `.m3u` moods work headless — licence or no licence.** Binary `.m3mood` files neither
  list nor mix, even when named explicitly — `&mood=Gentle` returns `MusicIP API error -
  invalid request or internal error`. Registration is **not** the cause and this is settled,
  not inferred: retested with `key=<a valid key>` set in `mmm.ini`, and observed
  again on a registered instance. Same failure both times. The Windows desktop app
  does support them, listing them as `Gentle (m3mood)` — the server simply does not.
  This *corrects* `MIP_1.9_Undocumented_Reference.md` §H, which records `&mood=Gentle`
  mixing successfully against a binary mood, and `kickoff-build.md` item 3, which concluded
  "ship the binary `.m3mood` moods … no Windows test needed".
- Per the official help: moods belong in "the Moods subdirectory **where the MusicIP Mixer
  is installed**" — the install dir is documented behaviour, not a container quirk.
- **Mount the folder, never the single cache file.** Single-file bind mounts bind by inode, so
  they break whenever the file is replaced rather than written in place.
- **No Reload Cache button.** The help documents `/server/reload` for running the GUI Mixer and the
  headless server together against one cache, so the server can pick up the GUI's changes. That
  cannot happen in this image — there is no GUI, and the Mixer binary is not packed. The notice
  itself stays: the only thing that can raise it here is someone replacing the cache file from
  outside, and the fix for that is to stop the container first. The endpoint is untouched.
- Music must be `/music` on both sides so Wine maps `Z:\music`.
- `getStatus` reads `idle` even when wedged. Real liveness is a genuine `/api/mix`.
- **LMS does not need restarting after a MIP restart.** Confirmed repeatedly in practice,
  2026-08. Older project docs assert the opposite; that was most likely a quirk of the original
  SugarCube build, not LMS binding to MIP at startup. Cold-boot start order is untested.
