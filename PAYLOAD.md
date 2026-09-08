# The payload — what you must supply

This repository ships **no MusicIP binaries**. They are licensed 2008 software and are not
redistributable here. To build the image you supply them yourself, from a MusicIP Mixer 1.96b
installation you already have.

## Where it goes

Create a folder `mip_server_install_files/` **at the root of this repository** — beside
`build-v2/`, not inside it. The Docker build context is the repository root for exactly this
reason.

```
<repo root>/
├── build-v2/                     <- this repository
└── mip_server_install_files/     <- you supply, git-ignored
    ├── persist_README.txt
    └── Program_Files/
        ├── MusicMagicServer.exe
        ├── mipcore.exe
        ├── AACTagReader.exe
        ├── dnssd.dll
        ├── libexpat.dll
        ├── mmm.ini
        ├── recipes.xml
        └── server/               <- the web UI folder, entire
```

That is the complete list. Nine items: seven files, one folder, plus `persist_README.txt`
alongside `Program_Files/`. Everything else in a stock MusicIP installation is deliberately
**not** packed.

## Where to get them

From `C:\Program Files (x86)\MusicIP\MusicIP Mixer\` on a Windows machine with MusicIP 1.96b
installed. Copy the seven files and the `server/` folder from there into `Program_Files/`.

`persist_README.txt` is not a MusicIP file — it is the note seeded into a user's persist folder
explaining what each file in it is for. Write your own, or leave it out and delete the matching
`COPY` line from the Dockerfile.

## Why these and not others

- **`MusicMagicServer.exe`** — the server. `MusicMagicServer.exe start` is the launch; a bare
  invocation gives Error 1063 and `mipcore.exe` alone prints a banner and exits 0.
- **`mipcore.exe`** — the analysis engine the server calls.
- **`AACTagReader.exe`** — named inside `MusicMagicServer.exe` as a UTF-16 string.
- **`dnssd.dll`, `libexpat.dll`** — **static imports** of `MusicMagicServer.exe`, read from its PE
  import table. The loader refuses to start without them, `tivo=0` and `upnp=0` notwithstanding.
  A disabled feature does not make its DLL removable.
- **`mmm.ini`, `recipes.xml`** — copied into the install dir, then removed and symlinked out to the
  persist folder so they are host-editable.
- **`server/`** — the web UI.

## Deliberately not packed

`MusicMagicMixer.exe`, the five BASS DLLs (`bass.dll`, `basscd.dll`, `bassflac.dll`,
`basswma.dll`, plus what the wildcard `bass*.dll` pulls in), `TiVoBeaconApi.dll`, `client.pem`,
`root.pem`, `powerwords.txt`, `register.key`.

The image boots to `OK — API: idle` in about five seconds without any of them. BASS is
Mixer-only: no reference to `bass*.dll` exists in `MusicMagicServer.exe` or `mipcore.exe` in
either ASCII or UTF-16, and no `BASS_` symbols. `powerwords.txt` is never read by the headless
server. No registration key is shipped and none is needed — mixing works unregistered.

**If you ever pack `MusicMagicMixer.exe`, all five BASS files go back together or not at all** —
the Mixer statically imports `BASS.dll` and `BASSCD.dll` and loads the rest through the wildcard.

## Reading the binaries yourself

Most filenames in this build are stored as **UTF-16, not ASCII** — `aactagreader`, `powerwords`,
`register.key` and `.m3mood` are all invisible to an ASCII-only string search. Search both
encodings before concluding a file is unused.

## Build

```
docker build -f build-v2/Dockerfile -t musicip-wine:local .
```

Run from the repository root. The trailing `.` is the build context and it must be the root, not
`build-v2/`.
