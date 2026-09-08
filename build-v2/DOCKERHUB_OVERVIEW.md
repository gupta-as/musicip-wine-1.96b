# MusicIP 1.96b — headless server in Docker

> **Note:** For most people, MusicIP 1.8 (Linux-native) containers are preferred — simpler to set up
> and use. This is the enthusiast option: it allows multi-value tags in filters and recipes, and
> handles hi-res files better.

The Windows **MusicIP 1.96b** standalone server, run headless under Wine, serving its HTTP API on
**port 10002**. Real Windows binaries wrapped in `debian:trixie-slim` with Debian's own Wine and a
silent Xvfb. No VNC, no supervisord. Runs **unprivileged**.

## What you need

- Music in a single folder, mounted read-only.
- A folder to persist your cache and recipes.
- LMS with the **SugarCube** plugin — that's the chief purpose.
- A **Windows machine with the MusicIP desktop app** if you want filters or moods. The headless
  server can use them but cannot create them.

## Quick start

Save the compose below, set the two `/path/to/…` mounts and your `PUID`/`PGID`, then
`docker compose up -d` and browse `http://localhost:10002`.

```yaml
services:
  mip:
    image: saysaar/musicip-1.96b-wine:latest
    container_name: mip
    restart: unless-stopped
    environment:
      - PUID=1000            # your data's owner — run `id <user>`  (Synology e.g. 1027)
      - PGID=1000            #                                       (Synology e.g. 65536)
      - TZ=America/New_York
    ports:
      - "127.0.0.1:10002:10002"    # LMS stack: delete this and use  network_mode: host
    cap_drop: [ALL]
    cap_add: [CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID]
    volumes:
      - "/path/to/mip:/home/mip/.wine/drive_c/users/mip/AppData/Roaming/MusicIP/MusicIP Mixer"
      - "/path/to/music:/music:ro"
    logging:
      driver: json-file
      options: { max-size: "10m", max-file: "5" }
```

It also runs bare, with nothing mounted at all.

## PUID / PGID

Set these to whoever owns your data — `id <user>`. Debian is usually `1000/1000`, Synology something
like `1027/65536`. The container remaps its own account to match, so **no chown needed**.

> **Use `2.2` or later if your uid is not 1000.** Every tag before `2.2` shipped a non-empty `/tmp`
> owned by uid 1000, which the unprivileged user could not clear. On any other uid the server never
> starts: `docker logs` shows Xvfb coming up, then
> `wine: chdir to /tmp/wine-XXXXXX : Permission denied`, then the readiness poll timing out. `latest`
> is fixed; if you pinned an older tag, move to `2.2`.

## The persist folder

Mount the **folder**, never individual files. On first run it is seeded with `mmm.ini`,
`recipes.xml` and a `README.txt` explaining every file in it, plus an empty `Moods/`. Nothing you put
there is ever overwritten, and deleting a file brings the default back on the next start.

Two things are deliberately **not** shipped:

- **No cache.** MusicIP creates `default.m3lib` itself the first time you add music.
- **No registration key.** Mixing works unregistered — MusicIP's own documentation states the
  SlimServer/LMS integration needs no premium key. If you have one, drop your `register.key` into the
  persist folder or add a `key=` line to `[services]` in `mmm.ini`, then restart.

## The music mount

Read-only, and the container side **must** be `/music`. Wine maps that to `Z:\music`, and those are
the paths written into your cache. If you use LMS, its music path must match.

## How-to

**Load your library.** Click **Add Music** in the web UI, then **Start Validation** once the tracks
are listed. The server does the full acoustic analysis itself and writes it to the cache.

If your Windows machine is the stronger one, you can analyse there instead and copy the cache in —
provided the paths match. Change your Windows music drive letter to `Z:` first. The default Windows
cache lives at:

`C:\Users\<YOU>\AppData\Roaming\MusicIP\MusicIP Mixer\default.m3lib`

**Always replace files in the persist folder with the container stopped.**

**Saving the cache.** MusicIP holds the cache in memory and does not write it immediately. After
adding or analysing music, `http://<host>:10002/api/flush` forces a save and returns `1`. Do that
before stopping the container, or the work may be lost.

**SugarCube path conversion.** In the plugin's settings:

```
MusicIP Port:                     10002
Host location:                    localhost (or 127.0.0.1)
Enable Dynamic Path Conversion:   checked
DPC (LMS)      Set #1 Destination: /music
DPC (MusicIP)  Set #1 Source:      Z:\music
```

**Recipes.** Edit `recipes.xml` in the persist folder — the bundled file has worked examples. Recipes
are read at **startup only**, so restart to apply changes. Choosing which recipe to use happens per
request and needs no restart. If a recipe never appears, the XML is malformed: check every tag is
closed and that `<`, `>` and `&` are escaped inside conditions.

**Filters** are built in the Windows desktop app and stored inside the cache, so they travel with
`default.m3lib` when you copy it in.

**Moods** go in `Moods/` as `.m3u` playlists; the filename becomes the mood name. Binary `.m3mood`
files do **not** work in the headless server — only the desktop app reads those. **A licence key
makes no difference**: tested both with and without one, `&mood=<binary mood>` fails either way.
Creating an `.m3mood` needs a key; reading one does not, and the headless server cannot read them
at all. Save your moods as `.m3u` in the desktop app.

## What this build cannot do

The headless server is a subset of the desktop Mixer. Absent from it:

- Inline Power Search (`filter=?expression`) — named filters only
- Binary `.m3mood` moods
- Power words — `powerwords.txt` is not read, so no shorthand filter aliases

These are limits of the server binary, not of your setup or your licence.

## Operations

```bash
docker logs -f mip                          # startup and server output
curl http://127.0.0.1:10002/api/getStatus   # idle | adding | analyzing
curl http://127.0.0.1:10002/api/recipes     # list recipes
curl http://127.0.0.1:10002/api/flush       # write the cache to disk
```

There is no healthcheck by design: `getStatus` reads `idle` even on a wedged server, so the only
honest test is a real `/api/mix` that returns tracks.

## Security

Runs as your unprivileged `PUID:PGID`. A brief root init remaps the account and drops privileges via
`setpriv`, with `cap_drop: ALL` and a minimal capability set. No outbound features, and MusicIP's
long-dead online service is disabled in the shipped `mmm.ini`.

## Credits

MusicIP Mixer 1.96b is 2008 software from Predixis/MusicIP, discontinued and community-preserved.
This image only packages it. The approach — Debian's own Wine plus the `MusicMagicServer.exe start`
launch — follows the path found by
[HB64](https://github.com/HB64/musicip-wine-1.9.b); the image itself is an independent build.
