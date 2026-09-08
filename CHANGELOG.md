# MusicIP Docker image — changelog and lineage

Single reference for every MusicIP image built in this project: what it is, when it
was built, what changed, and where the artefact lives.

Upstream binaries are **identical across every image below** — MusicIP Mixer 1.96b
(2008). Verified by MD5: `mipcore.exe`, `MusicMagicServer.exe`, all four BASS DLLs,
`dnssd.dll`, `libexpat.dll`, `client.pem`, `root.pem` match byte-for-byte between
this project's builds and HB64's `musicip-wine-1.9.b`. **All differences between
images are packaging only.**

---

## Image lineage

### v0.9-personal — 29 Jun 2026
Artefact: `mip-images/musicip-1.96b_v0.9-personal_20260629.tar` · Tag `mip_server:latest` · 12 layers

First working headless build. Simplest design of the three.

- `USER docrusr` baked into the image — **no root phase at all**. No `usermod`,
  no `chown`, no `setpriv`, no capabilities required.
- Fixed UID/GID 1000. No `PUID`/`PGID` support.
- **`/config` pattern**, conditional: if `/config` is mounted, `mmm.ini` and
  `recipes.xml` are seeded there and symlinked into the install dir; if not, the
  baked defaults are used. Short mount path, no quoting needed.
- `register.key` seeded into the roaming folder if absent.
- Prefix baked at build time (`wineboot --init` during `docker build`).
- Launch: `MusicMagicServer.exe start` on a silent Xvfb.

Limitations: no `Moods` symlink (the "MIP reads Moods from the *install* dir"
finding came later), no `powerwords.txt`, and the source folder (`server_build/`)
no longer exists — recoverable only by extracting layers from the tar.

### v1.0-public — 7 Jul 2026
Artefact: `mip-images/musicip-1.96b_v1.0-public_20260707.tar` · Tag `musicip-wine:1.96b` · 12 layers
Published: `saysaar/musicip-1.96b-wine:1.0` / `:latest`

Reworked for public distribution. Traded the simplicity of v0.9 for portability.

- **Root init added** — `groupmod`/`usermod -o` remap `docrusr` to `PUID`/`PGID`,
  conditional `chown`, then `setpriv` drops to the unprivileged user and hands off
  to `run-server.sh`. Requires caps `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`,
  `SETGID`. This is what makes Synology (non-1000 UIDs) work with no manual chown.
  **Incomplete as written** — the remap itself was always correct, but from v2.0 the image also
  shipped a `/tmp` owned by uid 1000, which broke every non-1000 deployment until v2.2. See below.
- **`/config` dropped.** The entire Wine roaming folder became the single mount:
  `/home/docrusr/.wine/drive_c/users/docrusr/AppData/Roaming/MusicIP/MusicIP Mixer`
  — 78 characters, contains a space, needs quoting.
- Seeds `default.m3lib`, `Moods/`, `register.key` from baked defaults if absent.
- Custom `server/index.html` (8.4 KB) replacing the stock page.
- Source was **never committed** — recoverable only from the tar.

### v1.1-public — 26 Jul 2026
Artefact: `mip-images/musicip-1.96b_v1.1-public_20260726.tar` · Tag `musicip-wine:1.96b` · 15 layers
Not published.

Extends the v1.0 seed-and-symlink pattern to the two remaining config files.

- `mmm.ini` and `powerwords.txt` added to `/home/docrusr/defaults`, seeded into the
  persist folder if absent, and symlinked into the install dir — so both are now
  host-editable and survive container recreates. Previously baked into the image
  and not persistable.
- `mmm.ini` defaults changed: `restrict=1→0`, `style=100→0`, `variety=1→0`,
  `cpu=1→0` (Max processor load). These are only baselines — SugarCube and the
  playlist script send `style`, `variety` and `mixsize` explicitly per request.
- Verified on Docker Desktop: both symlinks resolve, both files seeded correctly
  into an empty persist folder, server reaches `API: idle` in 12s.
- **Not yet tested against a real (109k-song) library on Debian.**

Known caveat: `mmm.ini` is the only symlinked file MIP *writes* — the web UI's
"Update Settings" (`/server/updateMixSettings`) and processor dropdown
(`/server/updateProcessorUse`) both rewrite it. If MIP ever writes via
temp-then-rename, the symlink would be replaced by a real file and host edits
would silently stop taking effect. Judged acceptable in practice.

### v2.0 — Aug 2026
Deployed to Debian production. Published to Docker Hub.

A clean rebuild, not a fork of v1.1: the design was re-derived from scratch, keeping only the
mechanics the running image had proven. `build-v2/README.md` is its design document and remains
authoritative.

- **User renamed `docrusr` -> `mip`**, and the install dir moved from `Program Files (x86)` to
  `Program Files` — idiomatic for a win32 prefix. Both appear in paths that must stay in sync:
  `cache=` in `mmm.ini` names the username literally, and getting it wrong makes MIP silently
  build a fresh empty cache with no error.
- **Symlinks baked at build time** rather than created at runtime — `mmm.ini`, `recipes.xml`,
  `powerwords.txt`, `Moods`. They dangle until the mount is populated, which is harmless.
- **`Moods/` never seeded or created.** Yours alone.
- **Payload trimmed** to 15 files plus `server/`.
- Locale purge; CRLF guard (`sed -i 's/\r$//'`); stale `/tmp/.X99-lock` removal added to
  `run-server.sh`; `XDG_RUNTIME_DIR` set.

### v2.1 — 21/22 Aug 2026
Built and verified on Docker Desktop. Published to Docker Hub; ran in Debian production.

Same design as v2.0, four packaging changes, each measured rather than reasoned.

- **Payload became a whitelist in the Dockerfile**, not a folder copy. Eight files:
  `MusicMagicServer.exe`, `mipcore.exe`, `AACTagReader.exe`, `dnssd.dll`, `libexpat.dll`,
  `mmm.ini`, `recipes.xml`, `server/`. The image boots to `OK — API: idle` in 5 s on those alone.
- **No `register.key` shipped.** Mixing works unregistered; users supply their own key.
- **No `powerwords.txt`** — the headless server never read it. The fourth symlink went with it.
- **No cache seeded at all.** A 0-byte `default.m3lib` half-works and is worse than none: MIP
  never adopts the file and the web UI shows a "cache modified on disk" notice that cannot clear.
  With no file at all, `cache=` names the path and MIP creates it on first use.
- **`Moods/` created empty** in the persist folder, and a `README.txt` seeded beside it.
- **The dead MusicIP online service blocked via the proxy settings** — `proxy=1` with
  `host=blackhole.invalid`, a reserved suffix that never resolves, turning every outbound attempt
  into an instant DNS failure. Whether it speeds anything up is **untested**.

### v2.2 — 8 Sep 2026
Published: `saysaar/musicip-1.96b-wine:2.2` and `:latest`, digest `sha256:1df952be…`.

**One bug fix, and it is the reason this version exists: the image only worked when `PUID` was
1000.** Present since v2.0; found on a Synology deployment (1027:65536).

- **The image shipped a populated `/tmp`.** The `wineboot --init` build layer runs as `USER mip`,
  uid 1000 at build time, leaving `.X99-lock`, `.X11-unix/` and a mode-0700 `wine-XXXXXX/` behind.
  Those were committed into the image. The apt layer's `rm -rf /tmp/*` runs *earlier* and cannot
  catch them, and `run-server.sh`'s own `rm` runs *after* `setpriv`, as the unprivileged user, so
  it fails with `Operation not permitted`.
- **Symptom:** the container starts, Xvfb comes up, then
  `wine: chdir to /tmp/wine-XXXXXX : Permission denied` and the 180 s readiness poll times out.
  The API never answers. Nothing in the log names `/tmp` as the problem.
- **Fix, two halves, either sufficient.** `entrypoint.sh` clears the X lock, X socket dir, wine
  temp dirs and stale runtime dirs while still root, immediately before `setpriv`, then recreates
  `/tmp/.X11-unix` mode 1777 — this self-heals a container built from any older image. The
  Dockerfile clears `/tmp/*` **and** `/tmp/.[!.]*` in its final layer so the junk is never
  shipped. `run-server.sh` unchanged.
- **Verified:** Docker Desktop at `PUID=1027 PGID=65536`, clean boot in 3 s; Docker Desktop at the
  default 1000, unchanged; Synology DSM with the real 109k cache and host networking, web UI up
  and a test mix returning tracks.
- **`docker-compose.debian.yml` corrected** — its persist-mount comment said
  `chown -R 1000:1000`, the same wrong assumption, in the file the Synology compose was copied
  from. Now `$PUID:$PGID`.
- **`DOCKERHUB_OVERVIEW.md`** gained a warning that tags before 2.2 fail on any uid but 1000.
  That page is hand-edited on Docker Hub — pushing an image does not update it.

**Why it hid for a month.** Every host until Synology ran at uid 1000, so `mip` owned the shipped
files and nothing surfaced. Not a Synology problem; Synology was the first host to expose it.

---

## Reference: HB64 `musicip-wine-1.9.b` (`hb1964/musicip-wine-1.9.b`)

Source snapshot in `HB64_1.2/`. Not a fork — this project's builds adopted
two of HB64's choices (the `debian:trixie-slim` + distro-Wine base, and the
`MusicMagicServer.exe start` launch method) but the rest is independent.

| | HB64 | This project |
|---|---|---|
| User / prefix | `wineuser`, `~/.wine32`, `Program Files/MusicIP` | `docrusr`, `~/.wine`, `Program Files (x86)/MusicIP/MusicIP Mixer` |
| Prefix build | at **every** container start | baked at image build |
| PUID/PGID | `useradd` at runtime + unconditional `chown -R` | `usermod -o` remap + conditional `chown` |
| Payload | 10 files (trimmed) | full install dir + roaming defaults |
| `register.key` | **not shipped** — user supplies their own | bundled, user-overridable |
| Locale | generates `en_US.UTF-8` (but never sets `ENV LANG`) | `C.UTF-8` |
| `curl` / `procps` | not installed | installed, used for a startup healthcheck |
| Startup | two hardcoded `sleep`s (8s), no server logging | polls `xdpyinfo`, logs server output, curls the API |
| Extras | GitHub Actions CI, LMS Moods-Mixer patches, docs | prebuilt tar, compose files |

**The table above describes v1.0**, not the current image. Since v2.0 the right-hand column reads:
user `mip`, prefix `~/.wine`, install dir `Program Files/MusicIP/MusicIP Mixer`; payload a
whitelist of eight files rather than the full install dir; and `register.key` **not shipped**,
matching HB64. The prefix-build, PUID and startup rows are still accurate.

HB64 additionally ships patched `Slim/Plugin/MusicMagic/{Plugin,Importer}.pm` that
translate `Z:\music` → `/music` for the LMS **Moods Mixer**. Not needed for
SugarCube, which has its own Dynamic Path Conversion. Not adopted here.

---

## Established facts (do not re-investigate)

- **`key=` in `mmm.ini` `[services]` is the literal registration key string**, not a
  path — confirmed in the official help doc. `register.key` (a 58-byte
  length-prefixed binary record wrapping `<a valid key>`) is the
  alternative mechanism, and the one this project uses. Deliberately left blank in
  `mmm.ini` so a user's own `register.key` in the mount can override the bundled one,
  and so a config edit can never silently de-register the server.
- **MIP reads `Moods` from the INSTALL dir, not the roaming folder.** Files placed in
  roaming `Moods/` were invisible to `/api/moods`. Hence the symlink.
- **Single-file bind mounts must not be used** for `mmm.ini` / `recipes.xml` /
  `powerwords.txt`. They are already symlinked out to the persist folder — mount the
  folder, edit them there. A single-file bind mount would replace the symlink with a
  busy mount point.
- **Two mounts only**: the persist folder, and `/music:ro` (must be `/music` so Wine
  maps it to `Z:\music` and it matches what LMS sees).
- **`en_US.UTF-8` vs `C.UTF-8`**: both are UTF-8, so encoding is identical. Differences
  are collation order and — the part that could matter — which ANSI codepage Wine
  picks for MIP's 2008-era Win32 `*A` API calls. Untested; irrelevant for an
  ASCII-only library.
- **`/tmp` must ship empty, and must be cleaned by root at boot.** Anything left there by a build
  step running as uid 1000 is unremovable by any other `PUID`. Added v2.2.
- **Only `.m3u` moods work headless.** Binary `.m3mood` files neither list nor mix under
  `MusicMagicServer.exe` — `&mood=X` returns an internal error. The desktop Mixer reads them; the
  server does not, and registration is not the cause. Retested both ways.
- **Inline Power Search (`filter=?expr`) does not work headless.** Named filters only. Like binary
  moods, it is a Mixer feature absent from the server binary.
- **`getStatus` reads `idle` even on a wedged server.** The only honest liveness test is an
  `/api/mix` that returns tracks. This is why the image ships no healthcheck.
- **LMS does not need restarting after a MIP restart.** Confirmed repeatedly in practice, 2026-08.
  Older docs in this project assert the opposite; that was most likely a quirk of the original
  SugarCube build. Cold-boot start order remains untested.
- **`mmm.ini` is rewritten only when a setting is saved from the web UI**, and MIP then writes its
  complete key set. Hand edits survive restarts, adds and scans untouched.

---

## Tagging policy

The app version `1.96b` is fixed — it is in the repository name. Tags track **packaging** revisions
only, as `MAJOR.MINOR` plus `latest`.

- **MINOR** = safe changes; an existing compose keeps working.
- **MAJOR** = anything that breaks a user's compose (a changed mount path, a renamed user).
- **Version tags are immutable.** Never re-push a tag that exists.
- **`latest` moves to the newest** — and is worth holding back until the new tag has run somewhere
  real. `2.2` was pushed first, verified on Synology, and only then did `latest` follow.

## Stability record

- **Stress tested, 2026-07.** Hundreds of sequential mixes through the nightly playlist export.
  Stable under normal load; ran clean in production for days.
- **One known way to wedge it, and it is contrived:** delete a track *while MIP is examining it*,
  then `refresh`. The result is empty mixes and a `getStatus` that still reads `idle`. Fix: restore
  the file, or restart the container. Not worth engineering around.
- **`/server/reload` returning "Server is busy" is a truer liveness signal than `getStatus`** — but
  a real `/api/mix` returning tracks is the only honest one.

*Both sections salvaged from `MIP_PROJECT_STATE.md` before it was deleted on 2026-09-08. The rest of
that file described the v1.0 image — `docrusr`, `Program Files (x86)`, a bundled `register.key`, a
0-byte cache being "rejected", and LMS binding to MIP at startup — all since superseded or
disproved.*

---

## Repository restructure — 26 Jul 2026

Renamed for clarity; `git mv` used throughout so history follows.

| Before | After |
|---|---|
| `public_build/` | `build-v1.1-public/` |
| `musicip-wine-1.9.b-master/` | `HB64_1.2/` |
| `HB64_dockerfile.txt` | *(unchanged — still at repo root)* |
| `PROJECT_STATE.md`, `HOST_AND_STACK_NOTES.md`, `MIP_1.9_Undocumented_Reference.md` | `docs/` |
| `MIP_Build_Kickoff.md`, `MIP_Experiment_Kickoff.md`, `SugarCube_Mod_Kickoff.md` | `docs/kickoff-build.md`, `docs/kickoff-experiment.md`, `docs/kickoff-sugarcube.md` |
| `Help_MIP_1.9.docx` | `docs/Help_MIP_1.9_official.docx` |
| `mip_probe.py` | `tools/mip_probe.py` |
| three `*.tar` files | `D:\Documents\coding\mip-images\` (outside the repo) |

`mip_server_install_files/` deliberately **not** renamed — every `COPY` line in the
Dockerfile references it by name.

Baseline commit before the restructure is tagged `v1.1-pre-restructure`.

### Git notes

- `.gitignore` excludes the MusicIP binaries, `register.key`, `*.m3lib`, `*.tar` and
  the whole `mip_server_install_files/` payload. Anyone cloning gets the build
  recipe but must supply their own binaries and key.
- Seven DLLs (`bass*.dll`, `dnssd.dll`, `libexpat.dll`, `TiVoBeaconApi.dll`) were
  committed *before* that ignore rule existed, so git still tracks them. `.gitignore`
  does not apply retroactively. Harmless, but they are the files that keep appearing
  as "modified".
- `register.key` has never been tracked, in any commit.

---

## Open items

1. ~~Test on Debian against the real 109k-song library.~~ **Done** — v2.0 ran in production
   against the real cache; ready in ~17 s.
2. Decide the `/config` inversion: make `/config` the real persist directory and
   symlink Wine's roaming path to it, giving a short unquoted mount path on both
   Debian and Synology while keeping the `PUID`/`PGID` root init. Breaking change to
   the mount path. **Still open.**
3. ~~Add `RUN sed -i 's/\r$//'` to the Dockerfile as CRLF insurance.~~ **Done** in v2.0.
4. ~~Synology deployment — never attempted.~~ **Done, 8 Sep 2026.** `uname -m` was `x86_64`;
   DSM ACLs were never the obstacle; the blocker was the `/tmp` bug fixed in v2.2. Working with
   the real cache over host networking.
5. Consider a bare git remote on the Debian host for off-machine backup. **Still open.**
6. **Debian is still on 2.1** — working, and carrying the v2.2 bug latently because its uid is
   1000. Upgrade when convenient: `/api/flush` first, then recreate (never restart).
7. **Paste `DOCKERHUB_OVERVIEW.md` into the Hub Overview page.** It is hand-edited there and does
   not follow a push.
8. **GitHub still undecided.** The tracked BASS DLLs remain the blocker; a fresh repo with no
   history is still the likely answer.
