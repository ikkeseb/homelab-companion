# Scene-RAR vs flat-MKV release layouts in arr-stack imports

Sonarr or Radarr reports a download as "completed" but never
imports it. The queue parks the item in `warning` state. The
release folder contains `.rar` and `.r00`–`.r18` files, no `.mkv`.
Some release-packaging conventions ship the video inside split
RAR archives — a Usenet-era artifact — while others ship a flat
`.mkv` at the release-folder root. The arr-stack importer only
handles the flat case out of the box.

## Symptom

Queue item stuck in `warning` with the message
`No files found eligible for import`. The download folder on
disk contains the split-archive layout:

```
release-name.r00
release-name.r01
…
release-name.rar
release-name.sfv
release-name.nfo
Sample/
```

No `.mkv` at the release root. The download client reports the
download as complete (it sees the files it was asked to fetch).
Sonarr/Radarr poll the folder, find no extractable media, and
park the queue item.

## Root cause

Two release-packaging conventions exist side by side in the
arr-stack ecosystem — *scene* and *non-scene* (often called P2P)
— and the arr-stack importer only handles one of them out of
the box.

**Scene releases (split-RAR layout).** The `.mkv` is packed
inside split RAR archives, historically 95 MB per part — the
legacy of Usenet's per-article size limit. The convention has
outlived Usenet itself. The actual `.mkv` does not exist on disk
until `unrar x` runs against the archive set.

**Non-scene / P2P releases (flat-MKV layout).** The `.mkv` is
shipped directly at the release-folder root. No archive, no
extraction step. This is what Sonarr/Radarr queue importers
expect by default.

The arr-stack importer scans the release folder, sees only
`.rar` archives in the scene case, and concludes there's nothing
to import. The error message is generic. Nothing in the surface
explains the layout difference between the two release
conventions.

There's a second-order cost when seeding is kept active after
import: the `.rar` archive set (~1.8 GB for a typical 1080p
episode) and the extracted `.mkv` (~1.8 GB) both have to coexist
on disk. Compared to a flat-MKV release at ~1.8 GB total, the
same content in scene-RAR form takes roughly 2×. Disk planning
has to account for that doubling on the scene portion of the
library.

### Diagnosis

```bash
ls -la /downloads/<release>/
# Scene / split-RAR: .r00, .r01, ..., .rar, .sfv, .nfo, Sample/
# Non-scene / flat:  <name>.mkv at root

# Sonarr/Radarr error string in the queue UI:
# "No files found eligible for import"

# After unpackerr extracts, the same folder shows both:
ls -la /downloads/<release>/
# .rar set still present (so the download client keeps its files)
# AND <name>.mkv now visible at root
```

Release-name patterns are not reliable predictors of layout.
The same group has been observed shipping scene-RAR for one
release and flat for another. Inspect the folder contents,
don't infer from the name.

## Fix

Run `golift/unpackerr` as a sidecar in the media stack. It polls
the Sonarr/Radarr queue APIs every ~2 minutes, finds items in
`warning` with the "No files found eligible" error, and runs
`unrar x` against the download directory. The extracted `.mkv`
lands next to the RAR set, the arr-stack queue importer retries
on its own schedule, and the import unblocks.

```yaml
services:
  unpackerr:
    image: golift/unpackerr:latest
    container_name: unpackerr
    user: ${PUID}:${PGID}
    volumes:
      - /data/Media/Downloads:/data/Media/Downloads
    environment:
      - TZ=${TZ:-UTC}
      - UN_SONARR_0_URL=http://sonarr:8989
      - UN_SONARR_0_API_KEY=${SONARR_API_KEY}
      - UN_SONARR_0_PATHS_0=/data/Media/Downloads
      - UN_SONARR_0_PROTOCOLS=torrent
      - UN_RADARR_0_URL=http://radarr:7878
      - UN_RADARR_0_API_KEY=${RADARR_API_KEY}
      - UN_RADARR_0_PATHS_0=/data/Media/Downloads
      - UN_RADARR_0_PROTOCOLS=torrent
    restart: unless-stopped
```

**Critical:** `PATHS_0` must match where the download client
**actually lands files** (the download directory), not where
Sonarr/Radarr stores the imported library. These are different
paths. Mismatch is the single most common unpackerr
misconfiguration.

Other knobs that matter:

- `delete_orig: false` (default) — leaves `.rar` archives in
  place. Flip this on only if you don't need to keep the original
  archives around after extraction.
- Disk budget — plan for the doubled footprint (archive + extracted)
  on the split-RAR portion of the library.

## Why LLMs miss this

The default reach for "Sonarr says completed but won't import"
is *"check Sonarr import settings"*, *"verify the path matches
the root folder"*, or *"check folder permissions"*. All three
are generic arr-stack troubleshooting that ignore the structural
layout difference. Models troubleshoot inside the Sonarr config
because that's the surface tool the user is interacting with —
they don't go up a level and ask *what's actually in the
download folder?*

A model that doesn't know the `unpackerr` sidecar pattern will
sometimes *hallucinate* that "the download client should
auto-extract" (most don't — they manage the files they
downloaded and don't touch the contents) or that "there's a
Sonarr setting to extract archives" (there isn't, in any
current version). Both suggestions waste time and leave the
user looking for a config that doesn't exist.

The right move requires domain knowledge that's underrepresented
in model training: the existence of split-RAR as a packaging
convention, the existence of `unpackerr` as the canonical
sidecar, and the distinction between the download client's
working path and the arr-stack library path. A useful prompt to
deflect the surface miss: *"the download folder contains .rar
files, not .mkv — what handles extraction in an arr-stack?"*
That phrasing routes the model to the structural difference
instead of the import-settings rabbit hole.

## See also

- [mutative-vs-readonly diagnostics](mutative-vs-readonly-diagnostics.md)
  — qBit `force recheck` is a related arr-stack temptation that
  destroys evidence; don't reach for it when state is uncertain.
- [sync-before-write](sync-before-write.md) — different domain,
  but the meta-shape ("the surface tool is misleading; go up one
  level") repeats.
