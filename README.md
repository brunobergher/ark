# ark

An offline knowledge library for emergencies, packed onto one drive.
Designed with families in mind, including survival and reference content,
educational videos and small, easy to run LLMs.
The drive is the artifact; the computer is whatever you happen to have.

## Use It

For a prepared drive, open the content directly with Kiwix, Kolibri, the local
models, the app pantry in `/apps/`, map files in `/maps/`, or the files in
`/docs/`. For setup and maintenance, use the root `update` command:

```bash
./update --help
./update --check
./update
./ark-maps
```

`./update --help` lists the available commands. `./update --check` proves the
configured downloads still exist and that the drive has room. `./update` runs
the configured fetch stages and resumes interrupted downloads. `./ark-maps`
starts the offline laptop map viewer when web maps are present.

Independent fetch stages run in parallel, and large Kiwix ZIM downloads also
run in parallel inside the ZIM stage. Tune `MAX_PARALLEL_STAGES` and
`MAX_PARALLEL_DOWNLOADS` in `scripts/kit.conf` if your connection or upstream
mirrors behave better with more or fewer simultaneous jobs.

Before you need the drive, prepare the devices that might use it:

1. On macOS and Windows, test the readers, installers, and runners carried in
   `/apps/macos/` and `/apps/windows/`.
2. On Android, install the APKs carried in `/apps/android/`, then open each app
   once so permissions and first-run prompts are done.
3. On iPhone and iPad, install the apps listed in `/apps/ios/app-store-links.html`
   while internet is available.
4. At minimum, have Kiwix for `.zim` files, a PDF/EPUB reader, VLC or another
   broad media player, and an offline maps app if `/maps/` is populated. Test
   importing one stored map before going offline.
5. For Kolibri, local AI, and translation on phones, plan to connect through a
   browser to one laptop or appliance running Ark on the local network.

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
| Reserved space | Folders for app binaries and offline map files |

After a completed run, those live under:

```text
/zim/         Kiwix content
/kolibri/     Khan Academy content
/apps/        App pantry: installers, APKs, portable readers and runners
/models/      LLM weights
/translate/   Argos translation models
/maps/        Optional offline maps for apps, web maps, or conversion
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

The current repo includes the root wrapper, preflight, shared helpers, example
config, and fetch stages for ZIMs, models, app payloads, Python tool
wheelhouses, maps, Kolibri channels, and Argos translation packages. Walk the
run without writing:

```bash
./update --dry-run
```

Then start the real download:

```bash
./update
```

The first full run will pull a few hundred gigabytes. It is safe to interrupt
with Ctrl-C; re-running `./update` resumes incomplete files. Active downloads
use `.partial` files and are moved into their final names only after the file
finishes and passes the available size/hash checks. If you change download
settings while `./update` is already running, stop it with Ctrl-C and start it
again; active parallel workers are stopped, completed files are skipped, and
partial files resume. `./update --prune` runs stages serially so cleanup cannot
race against another stage.

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
open the files in Kiwix Desktop. To serve the library on a local network, use
the generated Kiwix library XML:

```bash
kiwix-serve --port 8080 --library /Volumes/ark/zim/library.xml
```

`./update` rebuilds `/zim/library.xml` from completed `.zim` files using
`kiwix-manage`. For a quick one-off test, `kiwix-serve --port 8080
/Volumes/ark/zim/*.zim` can still serve files directly. Then open
`http://<your-ip>:8080` from another device. If the router is down, use a
laptop hotspot or local network sharing.

Kolibri serves Khan Academy. If Kolibri is carried in `/apps/python/`, use the
drive-local virtualenv created from the wheelhouse; otherwise use an installed
`kolibri` command:

```bash
KOLIBRI_HOME=/Volumes/ark/kolibri /Volumes/ark/apps/python/venvs/kolibri/bin/kolibri start
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
By default, the app resolver recipes carry the Kiwix reader/server stack where
upstream provides portable files: Kiwix Desktop for Windows/Linux, Kiwix Tools
with `kiwix-serve` for macOS/Windows/Linux, and a universal Android Kiwix APK.
macOS Kiwix reader installs still use the App Store workflow.

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
  "macos|kiwix-tools-arm64|mirror-latest:https://download.kiwix.org/release/kiwix-tools|^kiwix-tools_macos-arm64-[0-9].*\\.tar\\.gz$||Kiwix tools including kiwix-serve"
)
```

The generated layout is:

```text
/apps/
  README.txt
  macos/<name>/<file>
  windows/<name>/<file>
  linux/<name>/<file>
  android/<name>/<file.apk>
  python/wheelhouse/<name>/
  python/venvs/
  ios/README.txt
  ios/app-store-links.html
```

For macOS, carry `.app`, `.dmg`, `.zip`, `.tar.gz`, or command-line tools. For
Windows, carry portable `.exe` or `.zip` builds where available, and installers
where needed. For Linux, carry AppImages or command-line tool archives. For
Android, carry APKs and test installing them from the drive after enabling
local installs. For iOS/iPadOS, keep App Store prep links in `IOS_APP_LINKS`
and install those apps before going offline.

Python-based tools such as Kolibri and Argos Translate are carried as offline
wheelhouses:

```bash
PYTHON_TOOL_PACKAGES=(
  "kolibri|kolibri|Offline wheelhouse for the Kolibri CLI and server"
  "argostranslate|argostranslate|Offline wheelhouse for Argos Translate tooling"
)
```

After `./update` populates `/apps/python/wheelhouse/`, install from the drive
without internet into a local virtualenv:

```bash
python3 -m venv /Volumes/ark/apps/python/venvs/kolibri
/Volumes/ark/apps/python/venvs/kolibri/bin/python -m pip install --no-index --find-links /Volumes/ark/apps/python/wheelhouse/kolibri kolibri
```

Use the same pattern for `argostranslate`, changing the virtualenv and
wheelhouse names.

### Maps

The repo stores map recipes; the prepared drive stores the map files. Configure
regions in `scripts/kit.conf`, then run `./update` to populate `/maps/`. Map
downloads stay out of git like the ZIMs, models, and app pantry.

For usable phone/tablet maps today, prefer OsmAnd `.obf.zip` entries under
`/maps/mobile/osmand/`. Install OsmAnd while internet is available, open one
stored `.obf.zip` from the drive with OsmAnd, and confirm the region appears
offline before relying on it. Raw Geofabrik `.osm.pbf` files are source data;
they are valuable, but they are not a normal end-user phone workflow.

For laptop maps, configure `WEB_MAP_EXTRACTS`, run `./update`, then start:

```bash
./ark-maps
```

That opens `http://127.0.0.1:8090` and serves local PMTiles from
`/maps/web/protomaps/` through the bundled `pmtiles` CLI. It does not require
internet after the update has built the map extracts.

Pinned map entries use this format:

```bash
MAPS=(
  "platform|provider|region|filename|url|sha256|notes"
)
```

Resolver-backed entries use the same resolver style as the app pantry:

```bash
MAP_RESOLVERS=(
  "web|protomaps|sample-city|direct:https://example.com/sample-city.pmtiles|sample-city.pmtiles||Direct PMTiles example"
)
```

The generated layout is:

```text
/maps/
  README.txt
  mobile/<provider>/<region>/<file>
  android/<provider>/<region>/<file>
  ios/<provider>/<region>/<file>
  web/protomaps/<region>.pmtiles
  viewer/index.html
  raw/<provider>/<region>/<file>
```

| Format | Use | Notes |
|---|---|---|
| OsmAnd `.obf.zip` | Android or iOS with OsmAnd import where supported | Best mobile-first path; store under `/maps/mobile/osmand/` and test on the exact device |
| Organic Maps files | Organic Maps app-specific workflow | Use direct/manual URLs only when you know the import path works |
| PMTiles `.pmtiles` | Laptop browser map through `./ark-maps` | Built under `/maps/web/protomaps/` |
| Geofabrik `.osm.pbf` or `.shp.zip` | Advanced conversion or analysis | Useful source data, not the easiest phone workflow |

Good upstream source categories are OsmAnd offline map downloads, Organic Maps
map data mirrors, Protomaps PMTiles downloads, and Geofabrik OpenStreetMap
extracts. Choose regions deliberately: maps can become large quickly.

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
