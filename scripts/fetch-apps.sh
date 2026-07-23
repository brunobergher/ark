#!/usr/bin/env bash
# fetch-apps.sh - populate /apps/ with platform installers, APKs, and notes.

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib.sh"

preflight
manifest_begin

rc=0
keep_file=$(mktemp)
trap 'rm -f "$keep_file"' EXIT

set +u
app_entries=( "${APPS[@]}" )
resolver_entries=( "${APP_RESOLVERS[@]}" )
ios_link_entries=( "${IOS_APP_LINKS[@]}" )
set -u

valid_component() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

html_escape() {
  sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g'
}

keep() {
  printf '%s\n' "$1" >> "$keep_file"
}

fetch_app() {
  local platform="$1" name="$2" filename="$3" url="$4" sha256="$5" notes="$6"
  local dir dest label

  if ! valid_component "$platform" || ! valid_component "$name" || [ -z "$filename" ]; then
    warn "app:$platform:$name has an invalid platform, name, or filename"
    return 1
  fi

  dir="$APP_DIR/$platform/$name"
  dest="$dir/$filename"
  label="app:$platform:$name"
  keep "$dest"

  log "$label — $notes"
  if [ "$DRY_RUN" = 0 ]; then
    mkdir -p "$dir"
  fi

  fetch_verified "$url" "$dest" "$label" "$sha256"
}

resolve_app() {
  local resolver="$1" pattern="$2" repo api tmp resolved tag filename url dir

  case "$resolver" in
    direct:*)
      url="${resolver#direct:}"
      if [ -z "$pattern" ]; then
        return 1
      fi
      printf 'direct\t%s\t%s\n' "$pattern" "$url"
      ;;
    github-release:*)
      repo="${resolver#github-release:}"
      api="https://api.github.com/repos/$repo/releases/latest"
      tmp=$(mktemp)
      if ! curl -fsSL --max-time 60 "$api" -o "$tmp"; then
        rm -f "$tmp"
        return 1
      fi
      resolved=$(python3 -c '
import json
import re
import sys

pattern = sys.argv[1]
path = sys.argv[2]
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)
tag = data.get("tag_name", "latest")

for asset in data.get("assets", []):
    name = asset.get("name", "")
    url = asset.get("browser_download_url", "")
    if name and url and re.search(pattern, name):
        print(f"{tag}\t{name}\t{url}")
        raise SystemExit(0)

raise SystemExit(2)
' "$pattern" "$tmp")
      rm -f "$tmp"
      [ -n "$resolved" ] || return 1
      printf '%s\n' "$resolved"
      ;;
    mirror-latest:*)
      dir="${resolver#mirror-latest:}"
      tmp=$(mktemp)
      if ! curl -fsSL --max-time 60 "$dir" -o "$tmp"; then
        rm -f "$tmp"
        return 1
      fi
      filename=$(python3 -c '
import html.parser
import re
import sys

pattern = re.compile(sys.argv[1])
path = sys.argv[2]

class Links(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.hrefs = []
    def handle_starttag(self, tag, attrs):
        if tag != "a":
            return
        attrs = dict(attrs)
        href = attrs.get("href", "")
        if href:
            self.hrefs.append(href)

parser = Links()
with open(path, "r", encoding="utf-8", errors="replace") as handle:
    parser.feed(handle.read())

matches = [
    href
    for href in parser.hrefs
    if not href.endswith("/") and not href.endswith(".md5") and pattern.search(href)
]
if not matches:
    raise SystemExit(2)

def key(value):
    return [int(part) if part.isdigit() else part.lower() for part in re.split(r"([0-9]+)", value)]

print(sorted(matches, key=key)[-1])
' "$pattern" "$tmp") || {
        rm -f "$tmp"
        return 1
      }
      rm -f "$tmp"
      [ -n "$filename" ] || return 1
      url="${dir%/}/$filename"
      printf 'latest\t%s\t%s\n' "$filename" "$url"
      ;;
    *)
      return 1
      ;;
  esac
}

write_app_docs() {
  local path name url notes

  [ "$DRY_RUN" = 0 ] || return 0

  mkdir -p "$APP_MACOS_DIR" "$APP_WINDOWS_DIR" "$APP_ANDROID_DIR" "$APP_IOS_DIR" "$APP_LINUX_DIR"

  path="$APP_DIR/README.txt"
  cat > "$path" <<'EOF'
Ark app pantry

This directory is populated by ./update. It carries installers, portable apps,
APKs, and app-prep notes needed to use the offline library.

The git repo tracks the recipe. The prepared drive stores the binaries.
EOF
  keep "$path"

  path="$APP_MACOS_DIR/README.txt"
  cat > "$path" <<'EOF'
macOS apps

Open bundled .app folders, .dmg images, .zip archives, or command-line tools
from this directory. macOS may ask for permission the first time an app runs,
so test these while power and internet are available.
EOF
  keep "$path"

  path="$APP_WINDOWS_DIR/README.txt"
  cat > "$path" <<'EOF'
Windows apps

Run portable .exe files directly when available. If an app is only available as
an installer, run it from this directory and keep the installed app tested on
the machine you expect to use.
EOF
  keep "$path"

  path="$APP_LINUX_DIR/README.txt"
  cat > "$path" <<'EOF'
Linux apps

Run AppImage files directly after marking them executable. Command-line tool
archives such as Kiwix Tools may need to be unpacked first. Test them on the
Linux machine you expect to use before relying on the kit offline.
EOF
  keep "$path"

  path="$APP_ANDROID_DIR/README.txt"
  cat > "$path" <<'EOF'
Android apps

APK files in this directory can be installed from the Android Files app after
allowing local installs from that app. Install and open these apps before an
emergency so permissions and first-run prompts are already handled.
EOF
  keep "$path"

  path="$APP_IOS_DIR/README.txt"
  cat > "$path" <<'EOF'
iOS and iPadOS apps

iPhone and iPad normally cannot install app binaries from this drive. Use the
App Store links here while internet is available, then use those apps for local
files or Safari for services hosted by an Ark computer or appliance.
EOF
  keep "$path"

  path="$APP_IOS_DIR/app-store-links.html"
  {
    printf '%s\n' '<!doctype html>'
    printf '%s\n' '<html lang="en"><head><meta charset="utf-8">'
    printf '%s\n' '<meta name="viewport" content="width=device-width,initial-scale=1">'
    printf '%s\n' '<title>Ark iOS App Prep</title></head><body>'
    printf '%s\n' '<h1>Ark iOS App Prep</h1>'
    printf '%s\n' '<p>Install these apps before going offline.</p>'
    printf '%s\n' '<ul>'
    set +u
    for entry in "${ios_link_entries[@]}"; do
      IFS='|' read -r name url notes <<< "$entry"
      printf '<li><a href="%s">%s</a>' \
        "$(printf '%s' "$url" | html_escape)" \
        "$(printf '%s' "$name" | html_escape)"
      if [ -n "${notes:-}" ]; then
        printf ' - %s' "$(printf '%s' "$notes" | html_escape)"
      fi
      printf '%s\n' '</li>'
    done
    set -u
    printf '%s\n' '</ul></body></html>'
  } > "$path"
  keep "$path"
}

write_app_docs

echo
log "App pantry"

set +u
if [ "${#app_entries[@]}" -eq 0 ] && [ "${#resolver_entries[@]}" -eq 0 ]; then
  log "SKIP  no app binaries configured"
fi

for entry in "${app_entries[@]}"; do
  IFS='|' read -r platform name filename url sha256 notes <<< "$entry"
  fetch_app "$platform" "$name" "$filename" "$url" "${sha256:-}" "${notes:-}" || rc=1
done

for entry in "${resolver_entries[@]}"; do
  IFS='|' read -r platform name resolver pattern sha256 notes <<< "$entry"
  log "app:$platform:$name resolving $resolver"
  resolved=$(resolve_app "$resolver" "$pattern") || {
    warn "app:$platform:$name could not resolve $resolver with pattern $pattern"
    rc=1
    continue
  }
  IFS=$'\t' read -r tag filename url <<< "$resolved"
  log "app:$platform:$name resolved $tag $filename"
  fetch_app "$platform" "$name" "$filename" "$url" "${sha256:-}" "${notes:-latest release}" || rc=1
done

for entry in "${ios_link_entries[@]}"; do
  IFS='|' read -r name url notes <<< "$entry"
  log "iOS prep link $name — $url"
done
set -u

if [ "$PRUNE" = 1 ]; then
  prune_unlisted "$APP_DIR" "$keep_file"
fi

manifest_commit
exit "$rc"
