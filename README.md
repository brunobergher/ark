# ark

An offline knowledge library on a single drive. Wikipedia with images, medical
and repair references, Khan Academy, books, maps, a local language model, and
offline translation — all readable on any Mac, PC, or Linux machine without an
internet connection.

The drive is the artifact. The computer is whatever you happen to have.

## If you are reading this during an emergency

Skip everything below. Open `START-HERE.txt` at the root of the drive.

## Layout

```
/zim/         Kiwix content — Wikipedia, medical, repair, dictionary, books
/kolibri/     Khan Academy, served by Kolibri
/apps/        Portable readers and runners for Mac, Windows, Linux
/models/      LLM weights
/translate/   Argos offline translation models
/maps/        OSM extracts for Iberia
/docs/        Personal documents — insurance, medical, IDs, contacts
/scripts/     Update machinery and configuration
manifest.tsv  What's on the drive, where it came from, when it was fetched
kit-log.txt   Append-only log of every fetch and verify run
```

## Setting up a new drive

Format as **exFAT**, name it `ark`. exFAT reads and writes on macOS, Windows,
and Linux without extra drivers, which is the whole point.

On macOS, Disk Utility → Erase → Format: exFAT, Scheme: GUID Partition Map.

Then:

```bash
git clone <this repo> ark-scripts && cd ark-scripts
cp scripts/kit.conf.example scripts/kit.conf
$EDITOR scripts/kit.conf  # set KIT_ROOT, pick your content
./update --check          # prove every URL resolves and the space adds up
./update --dry-run        # walk the full run, download nothing
./update                  # go make coffee, this takes many hours
```

`./update --check` is the one to run first. It resolves the newest build of
every ZIM, probes each URL with a HEAD (falling back to a one-byte ranged GET
where the host rejects HEAD), and prints a table of what resolved, what didn't,
the total download size, and whether the drive has room. It transfers headers
and nothing else, so it takes seconds. A renamed ZIM or a moved model repo
shows up here rather than sixty gigabytes into a real run.

The first run pulls a few hundred gigabytes. It resumes if interrupted, so
Ctrl-C is safe and re-running picks up where it stopped.

## Changing what's on the drive

The checked-in default lives in `scripts/kit.conf.example`. Your local editable
copy is `scripts/kit.conf`, which git ignores so drive paths, channel IDs, and
personal choices do not accidentally get committed. Add a line to `ZIMS`,
`MODELS`, `KOLIBRI_CHANNELS`, or `ARGOS_PAIRS` and re-run `./update`. Remove a
line and re-run with `./update --prune` to delete the orphaned files.

ZIM entries are prefixes, not filenames — `wikipedia:wikipedia_en_all_maxi`
resolves to whatever the newest monthly build is. You never pin a date, and
re-running is how you update.

## Updating

`./update` is also the refresh path. It resolves the newest build of every ZIM,
downloads what changed, deletes superseded versions, and leaves everything else
alone.

Do this once a year. Put it on a calendar next to the smoke-alarm batteries.
The refresh is also what keeps the drive's NAND healthy — SSDs left unpowered
for years slowly lose charge, and a few hours plugged in fixes that.

## Reading the content

**Kiwix** is the reader for everything in `/zim/`. Kiwix Desktop for a single
person on one machine; `kiwix-serve` when you want the whole family reading on
their own phones over a local network.

```bash
kiwix-serve --port 8080 /Volumes/ark/zim/*.zim
```

Then anyone on the network opens `http://<your-ip>:8080`. If the router is down
too, turn on Internet Sharing on macOS and serve from the laptop's own hotspot.

**Kolibri** serves Khan Academy the same way:

```bash
KOLIBRI_HOME=/Volumes/ark/kolibri kolibri start
```

**The model** runs from `/models/`. Point the runner at the weights, open the
web UI it serves, and optionally register a Kiwix MCP server so the model can
search the library instead of guessing.

## A note on the model

The kit carries two llamafiles by default:

| | |
|---|---|
| `Qwen3.5-2B-Q8_0.llamafile` | Portable first choice, roughly 3 GB on disk. Use this when the computer is old, borrowed, or memory constrained. |
| `gpt-oss-20b-mxfp4.llamafile` | Better answers on stronger machines, roughly 12 GB on disk. Try this when the computer has enough RAM and the smaller model is not helping. |

On macOS or Linux, make the file executable before the first run:

```bash
chmod +x /Volumes/ark/models/*.llamafile
/Volumes/ark/models/Qwen3.5-2B-Q8_0.llamafile
```

The 20B model is optional in practice. If it refuses to load or starts swapping,
drop back to Qwen and use the library directly for anything important.

The model is the least load-bearing part of the drive. Kiwix is the ground
truth; the model is a natural-language interface to it. When they disagree,
believe the ZIM.

## Scripts

| | |
|---|---|
| `update` | The root-level command to check, fetch, and refresh the drive |
| `scripts/kit.conf.example` | The shareable default config |
| `scripts/kit.conf` | Your ignored local config |
| `scripts/check-remote.sh` | Probe every URL and the space budget |
| `scripts/fetch-all.sh` | Run every fetch stage |
| `scripts/lib.sh` | Shared helpers, not run directly |

Use `./update --check` for preflight, `./update --dry-run` for a no-write run,
and `./update --prune` after removing content from `scripts/kit.conf`.

## Cloning to a second drive

```bash
rsync -avh --progress --delete /Volumes/ark/ /Volumes/ark-backup/
```

Keep the copies in different places. A backup in the same bag as the primary
protects against drive failure and nothing else. One in a safe, one in the car,
one at a family member's house — that's what makes it a backup.

Copies are cheap. A drive costs less than a night out and makes an entire
household more resilient. Hand them out.
