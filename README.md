# ark

An offline knowledge library for emergencies, packed onto one drive.
The drive is the artifact; the computer is whatever you happen to have.

## Use It

For a prepared drive, open the content directly with Kiwix, Kolibri, the local
models, or the files in `/docs/`. For setup and maintenance, use the root
`update` command:

```bash
./update --check
./update
```

`./update --check` proves the configured downloads still exist and that the
drive has room. `./update` runs the configured fetch stages and resumes
interrupted downloads.

## Contents

The default config is meant to build a kit that is useful without an internet
connection:

| | |
|---|---|
| Wikipedia | Full English Wikipedia with images |
| Medical references | Wikipedia medicine, WikiEM, and practical health guides |
| Repair references | iFixit repair guides with photos |
| Books and dictionary | Project Gutenberg and English Wiktionary |
| Lessons | Khan Academy through Kolibri once a channel ID is set |
| Translation | Argos offline language packs |
| Local AI | Qwen 2B for portability and gpt-oss 20B for stronger machines |
| Personal docs | A place for IDs, insurance, medical notes, contacts, and plans |
| Reserved space | Folders for app binaries and map extracts |

After a completed run, those live under:

```text
/zim/         Kiwix content
/kolibri/     Khan Academy content
/apps/        Optional portable readers and runners
/models/      LLM weights
/translate/   Argos translation models
/maps/        Optional map extracts
/docs/        Personal documents
/scripts/     Update machinery and configuration
manifest.tsv  What was fetched, from where, and when
kit-log.txt   Append-only update log
```

## Key Features

1. Configurable: edit `scripts/kit.conf` to choose ZIMs, models, Kolibri
   channels, translation pairs, and the target drive path.
2. Portable: the drive is formatted as exFAT and the content is readable from
   macOS, Windows, and Linux.
3. Resumable: the shared fetch helper supports partial downloads, so long runs
   can pick up where they stopped.
4. Preflighted: `./update --check` verifies URLs and the space budget before
   the real download starts.
5. Shareable: the repo tracks scripts and `scripts/kit.conf.example`, while
   downloaded content, logs, manifests, and your local config stay out of git.

## First Run

Format the drive as **exFAT** and name it `ark`. On macOS: Disk Utility,
Erase, Format: exFAT, Scheme: GUID Partition Map.

Clone the setup repo somewhere convenient:

```bash
git clone <this repo> ark-scripts
cd ark-scripts
cp scripts/kit.conf.example scripts/kit.conf
$EDITOR scripts/kit.conf
```

Set `KIT_ROOT` to the mounted drive path, then adjust the content lists if you
want a smaller or larger kit.

Run the remote preflight:

```bash
./update --check
```

The current repo includes the root wrapper, preflight, shared helpers, and
example config. The download stages named by `scripts/fetch-all.sh` still need
to be added or restored before `./update --dry-run` or `./update` can fetch the
content.

Once those fetch stage scripts are present, walk the run without writing:

```bash
./update --dry-run
```

Then start the real download:

```bash
./update
```

The first full run will pull a few hundred gigabytes. It is safe to interrupt
with Ctrl-C; re-running `./update` resumes incomplete files.

## Refresh

Refresh the drive about once a year:

```bash
./update
```

With the fetch stage scripts in place, this resolves the newest matching ZIM
builds, downloads what changed, and leaves existing complete files alone. If
you removed entries from `scripts/kit.conf`, prune old files too:

```bash
./update --prune
```

Annual refreshes also help the physical drive: SSDs left unpowered for years
slowly lose charge, and a few hours plugged in is good maintenance.

## Reading

Use Kiwix for everything in `/zim/`. For one person, open the files in Kiwix
Desktop. To serve the library to phones or laptops on a local network:

```bash
kiwix-serve --port 8080 /Volumes/ark/zim/*.zim
```

Then open `http://<your-ip>:8080` from another device. If the router is down,
use a laptop hotspot or local network sharing.

Kolibri serves Khan Academy:

```bash
KOLIBRI_HOME=/Volumes/ark/kolibri kolibri start
```

The local AI models live in `/models/`. On macOS or Linux, make them executable
once:

```bash
chmod +x /Volumes/ark/models/*.llamafile
/Volumes/ark/models/Qwen3.5-2B-Q8_0.llamafile
```

Use `Qwen3.5-2B-Q8_0.llamafile` first on unknown hardware. Try
`gpt-oss-20b-mxfp4.llamafile` on stronger machines. The model is a convenience
layer over the library, not the source of truth; when it disagrees with the
offline references, believe the references.

## Share Or Clone

The repo is meant to be checked in without the downloaded content:

```bash
git status
```

Only scripts, docs, and `scripts/kit.conf.example` should be tracked. Your
local `scripts/kit.conf`, downloaded content folders, `manifest.tsv`, and
`kit-log.txt` are ignored.

To duplicate a finished drive:

```bash
rsync -avh --progress --delete /Volumes/ark/ /Volumes/ark-backup/
```

Keep copies in different places. A backup in the same bag as the primary
protects against drive failure and nothing else.
