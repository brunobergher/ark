# ark

An offline knowledge library for emergencies, packed onto one drive.
Designed with families in mind, including survival and reference content,
educational videos and small, easy to run LLMs.
The drive is the artifact; the computer is whatever you happen to have.

## Use It

For a prepared drive, open the content directly with Kiwix, Kolibri, the local
models, the app pantry in `/apps/`, or the files in `/docs/`. For setup and
maintenance, use the root `update` command:

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
/apps/        App pantry: installers, APKs, portable readers and runners
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
   downloaded content, apps, logs, manifests, and your local config stay out of
   git.

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

Once a year, check that the drive, your batteries, cables, etc are working,
and run this to keep the content fresh:

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

Use Kiwix for everything in `/zim/`. On macOS and Windows, the computer is the
primary runtime host: it can open content directly, run portable apps from
`/apps/`, and serve the library to nearby phones and laptops. For one person,
open the files in Kiwix Desktop. To serve the library on a local network:

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

### App Pantry

The repo stores the recipe; the prepared drive stores the binaries. Configure
app payloads in `scripts/kit.conf`, then run `./update` to populate `/apps/`.
The app pantry is ignored by git alongside the downloaded knowledge library.

Pinned app entries use this format:

```bash
APPS=(
  "platform|name|filename|url|sha256|notes"
)
```

Resolver-backed entries can fetch the latest matching asset from a stable
release API:

```bash
APP_RESOLVERS=(
  "macos|kiwix|github-release:kiwix/kiwix-desktop|.*mac.*\\.dmg$||Latest Kiwix Desktop for macOS"
)
```

The generated layout is:

```text
/apps/
  README.txt
  macos/<name>/<file>
  windows/<name>/<file>
  android/<name>/<file.apk>
  ios/README.txt
  ios/app-store-links.html
```

For macOS, carry `.app`, `.dmg`, `.zip`, or command-line tools. For Windows,
carry portable `.exe` builds where available, and installers where needed. For
Android, carry APKs and test installing them from the drive after enabling
local installs. For iOS/iPadOS, keep App Store prep links in `IOS_APP_LINKS`
and install those apps before going offline.

### Prepare Phones And Tablets

Mobile devices can read prepared files and use apps that are already installed,
but they generally cannot run the bundled desktop executables directly from the
drive. Prepare phones and tablets before you need them:

1. Install Kiwix on iOS/iPadOS and Android for `.zim` files.
2. Make sure PDFs, EPUBs, office documents, photos, audio, and video open with
   the built-in apps or installed readers.
3. Install VLC or another broad media player if you keep standalone audio or
   video on the drive.
4. Install an offline maps app such as Organic Maps or OsmAnd if `/maps/` is
   populated, and store maps in a format that app can import.
5. On Android, install Kolibri if you plan to run lessons directly on the
   device. On iOS/iPadOS, plan to use Kolibri through Safari from a hosted Ark
   computer or appliance.
6. On Android, install prepared APKs from `/apps/android/` if the kit carries
   them.
7. Open every app once while internet is available so first-run prompts,
   permissions, and file-access dialogs are already handled.

| Content | iOS/iPadOS | Android | Best Ark Mode |
|---|---|---|---|
| ZIM libraries in `/zim/` | Kiwix app | Kiwix app | Local app, or hosted `kiwix-serve` |
| PDFs, EPUBs, docs, images, audio, video in `/docs/` or `/media/` | Files app and installed readers | Files app and installed readers | Direct file access |
| Kolibri lessons in `/kolibri/` | Safari to hosted Kolibri | Kolibri app or browser to hosted Kolibri | Hosted from desktop or appliance |
| Local AI models in `/models/` | Browser to hosted model service | Browser to hosted model service, or advanced local app workflow | Hosted from desktop or appliance |
| Translation packs in `/translate/` | Browser to hosted translation service | Browser to hosted translation service, or compatible local app workflow | Hosted from desktop or appliance |
| Maps in `/maps/` | Offline maps app if the format is supported | Offline maps app if the format is supported | App-specific local files |

### Hosted Mode For Phones

For phones and tablets, the most reliable setup is to have one laptop or small
appliance start the Ark services, then let mobile devices use them through a
browser. Connect every device to the same local Wi-Fi network. If there is no
router, use a laptop hotspot or a travel router kept with the kit.

Start Kiwix, Kolibri, and any future model or translation services on the host,
then open one of these addresses on the phone or tablet:

```text
http://ark.local
http://<host-ip>:8080
```

`http://ark.local` depends on a future launcher or appliance advertising that
name on the local network. Until then, use the host IP address shown by the
computer that started the service.

Before putting the kit away, test one small `.zim`, one PDF, one video, and the
hosted dashboard from each family phone or tablet. Keep the needed USB-C,
Lightning, and charging cables with the drive.

Future mobile-friendly content should stay predictable: use `/zim/` for Kiwix
libraries, `/docs/` for PDFs, EPUBs, and personal documents, `/media/` for
standalone audio or video outside ZIM/Kolibri, and `/maps/` for app-specific
offline map files.

## Share Or Clone

The repo is meant to be checked in without the downloaded content:

```bash
git status
```

Only scripts, docs, and `scripts/kit.conf.example` should be tracked. Your
local `scripts/kit.conf`, downloaded content folders, `/apps/`, `manifest.tsv`,
and `kit-log.txt` are ignored.

To duplicate a finished drive:

```bash
rsync -avh --progress --delete /Volumes/ark/ /Volumes/ark-backup/
```

Keep copies in different places. A backup in the same bag as the primary
protects against drive failure and nothing else.
