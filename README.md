# MusicIP 1.96b headless, under Wine, in Docker

The Windows **MusicIP Mixer 1.96b** server run headless under Wine on `debian:trixie-slim`,
serving its HTTP API on port **10002** for Lyrion Music Server and similar clients. Real 2008
Windows binaries, a silent Xvfb, and nothing else — no VNC, no supervisord, no desktop.

Runs **unprivileged**, remaps its own account to your `PUID`/`PGID`, and keeps everything you care
about in **one flat persist folder**.

> For most people, MusicIP 1.8 native Linux containers are simpler. This is the enthusiast option:
> 1.96b handles multi-value tags in filters and recipes, and hi-res files, better.

## Run it

The built image is on Docker Hub — you do not need this repository to use it.

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
      - "127.0.0.1:10002:10002"    # for an LMS stack, delete this and use network_mode: host
    cap_drop: [ALL]
    cap_add: [CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID]
    volumes:
      - "/path/to/mip:/home/mip/.wine/drive_c/users/mip/AppData/Roaming/MusicIP/MusicIP Mixer"
      - "/path/to/music:/music:ro"
    logging:
      driver: json-file
      options: { max-size: "10m", max-file: "5" }
```

`docker logs mip` should end at `OK — API: idle`.

**Use `2.2` or later if your uid is not 1000.** Every earlier tag shipped a non-empty `/tmp` owned
by uid 1000 which the unprivileged user could not clear; on any other uid the server never starts.

## Build it

You supply the MusicIP binaries — **[`PAYLOAD.md`](PAYLOAD.md)** lists exactly which files, where
they go, and why each one is needed. Then, from the repository root:

```
docker build -f build-v2/Dockerfile -t musicip-wine:local .
```

## Read it

- **[`build-v2/README.md`](build-v2/README.md)** — the design document. One persist mount, symlinks
  baked at build time, why `cache=` is a literal path that must match the username baked into the
  image, and what the headless server binary can and cannot do compared to the desktop Mixer.
- **[`PAYLOAD.md`](PAYLOAD.md)** — the binaries you supply, and the ones deliberately left out.
- **[`CHANGELOG.md`](CHANGELOG.md)** — every image built, what changed between them, and a list of
  findings established by measurement that are not worth re-deriving.
- **[`build-v2/DOCKERHUB_OVERVIEW.md`](build-v2/DOCKERHUB_OVERVIEW.md)** — the user-facing guide:
  loading a library, moods, recipes, filters, path conversion, operations.

## What it cannot do

The headless server is a **subset** of the desktop Mixer, and two documented features are simply
absent from the binary:

- **Inline Power Search** (`filter=?expression`) — named filters only
- **Binary `.m3mood` moods** — `.m3u` moods only

Both confirmed by live test in each direction and by string analysis of the binaries. Neither is a
registration problem, and neither is a fault in your setup.

## Credits

MusicIP Mixer 1.96b is 2008 software from Predixis/MusicIP, discontinued and community-preserved.
This image only packages it.

The approach — `debian:trixie-slim` with Debian's own Wine, and the `MusicMagicServer.exe start`
launch — follows the path found by **[HB64](https://github.com/HB64/musicip-wine-1.9.b)**. This is
an independent build rather than a fork: different user model, single flat persist folder, baked
Wine prefix, whitelist payload, and `setpriv` in place of `gosu`.
