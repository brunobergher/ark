#!/usr/bin/env bash
# check-remote.sh — prove every URL in scripts/kit.conf resolves before a
# multi-hundred-gigabyte download. Transfers nothing but headers.
#
#   ./update --check
#
# For each ZIM it resolves the newest build from the mirror index, then probes
# it. For each model it probes the URL directly (including every shard of a
# split GGUF). Prints a total and compares it against free space on the drive.

. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

[ -d "$KIT_ROOT" ] || die "$KIT_ROOT not mounted"
command -v curl >/dev/null || die "curl not found"

green() { printf '\033[32m%s\033[0m' "$1"; }
red()   { printf '\033[31m%s\033[0m' "$1"; }
yellow(){ printf '\033[33m%s\033[0m' "$1"; }

total=0
bad=0
row() { printf '  %-8s %-52s %s\n' "$1" "$2" "$3"; }

set +u
zim_entries=( "${ZIMS[@]}" )
model_entries=( "${MODELS[@]}" )
kolibri_entries=( "${KOLIBRI_CHANNELS[@]}" )
app_entries=( "${APPS[@]}" )
app_resolver_entries=( "${APP_RESOLVERS[@]}" )
ios_link_entries=( "${IOS_APP_LINKS[@]}" )
map_entries=( "${MAPS[@]}" )
map_resolver_entries=( "${MAP_RESOLVERS[@]}" )
web_map_entries=( "${WEB_MAP_EXTRACTS[@]}" )
python_tool_entries=( "${PYTHON_TOOL_PACKAGES[@]}" )

resolve_app() {
  local resolver="$1" pattern="$2" repo api tmp resolved url dir filename

  case "$resolver" in
    direct:*)
      url="${resolver#direct:}"
      [ -n "$pattern" ] || return 1
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

echo
echo "ark — remote preflight  $(date -u +%Y-%m-%dT%H:%MZ)"
echo "══════════════════════════════════════════════════════════════════════════"

# ── ZIMs ─────────────────────────────────────────────────────────────────────
echo
echo "Kiwix ZIMs"
for entry in "${zim_entries[@]}"; do
  subdir="${entry%%:*}"; prefix="${entry#*:}"

  index=$(curl -fsSL --max-time 60 "$MIRROR/$subdir/" 2>/dev/null)
  if [ -z "$index" ]; then
    row "$(red FAIL)" "$prefix" "mirror dir $subdir/ unreachable"
    bad=$((bad+1)); continue
  fi

  file=$(printf '%s' "$index" \
    | grep -o "href=\"${prefix}_[0-9]\{4\}-[0-9]\{2\}\.zim\"" \
    | sed 's/href="//; s/"$//' | sort -V | tail -n1)

  if [ -z "$file" ]; then
    row "$(red FAIL)" "$prefix" "no build matches this prefix"
    bad=$((bad+1)); continue
  fi

  p=$(probe "$MIRROR/$subdir/$file"); st="${p%%$'\t'*}"; sz="${p##*$'\t'}"
  if [ "$st" = "200" ] && [ "$sz" -gt 0 ] 2>/dev/null; then
    row "$(green OK)" "$file" "$(human "$sz")"
    total=$(( total + sz ))
  else
    row "$(red FAIL)" "$file" "HTTP $st"
    bad=$((bad+1))
  fi
done

# ── models ───────────────────────────────────────────────────────────────────
echo
echo "Models"
if [ "${#model_entries[@]}" -eq 0 ]; then
  row "$(yellow SKIP)" "(none configured)" ""
else
  for entry in "${model_entries[@]}"; do
    name="${entry%%|*}"; url="${entry#*|}"
    urls=("$url"); names=("$name")

    # expand sharded GGUF: -00001-of-0000N
    if [[ "$name" =~ -0*1-of-0*([0-9]+)\.gguf$ ]]; then
      n="${BASH_REMATCH[1]}"
      for i in $(seq 2 "$n"); do
        part=$(printf '%05d-of-%05d' "$i" "$n")
        names+=("$(echo "$name" | sed -E "s/[0-9]{5}-of-[0-9]{5}/$part/")")
        urls+=("$(echo "$url"   | sed -E "s/[0-9]{5}-of-[0-9]{5}/$part/")")
      done
    fi

    for i in "${!urls[@]}"; do
      p=$(probe "${urls[$i]}"); st="${p%%$'\t'*}"; sz="${p##*$'\t'}"
      if [ "$st" = "200" ] && [ "$sz" -gt 0 ] 2>/dev/null; then
        row "$(green OK)" "${names[$i]}" "$(human "$sz")"
        total=$(( total + sz ))
      else
        row "$(red FAIL)" "${names[$i]}" "HTTP $st"
        bad=$((bad+1))
      fi
    done
  done
fi

if [ -n "$LLAMAFILE_RELEASE" ]; then
  p=$(probe "$LLAMAFILE_RELEASE"); st="${p%%$'\t'*}"; sz="${p##*$'\t'}"
  if [ "$st" = "200" ]; then
    row "$(green OK)" "$(basename "$LLAMAFILE_RELEASE")" "$(human "$sz")"
    total=$(( total + sz ))
  else
    row "$(red FAIL)" "$(basename "$LLAMAFILE_RELEASE")" "HTTP $st"; bad=$((bad+1))
  fi
fi

# ── app pantry ───────────────────────────────────────────────────────────────
echo
echo "App pantry"
set +u
if [ "${#app_entries[@]}" -eq 0 ] && [ "${#app_resolver_entries[@]}" -eq 0 ]; then
  row "$(yellow SKIP)" "(no app binaries configured)" ""
else
  for entry in "${app_entries[@]}"; do
    IFS='|' read -r platform name filename url sha256 notes <<< "$entry"
    p=$(probe "$url"); st="${p%%$'\t'*}"; sz="${p##*$'\t'}"
    if [ "$st" = "200" ]; then
      if [ "$sz" -gt 0 ] 2>/dev/null; then
        row "$(green OK)" "$platform/$name/$filename" "$(human "$sz")"
        total=$(( total + sz ))
      else
        row "$(green OK)" "$platform/$name/$filename" "unknown size"
      fi
    else
      row "$(red FAIL)" "$platform/$name/$filename" "HTTP $st"
      bad=$((bad+1))
    fi
  done

  for entry in "${app_resolver_entries[@]}"; do
    IFS='|' read -r platform name resolver pattern sha256 notes <<< "$entry"
    resolved=$(resolve_app "$resolver" "$pattern") || {
      row "$(red FAIL)" "$platform/$name" "could not resolve $resolver"
      bad=$((bad+1))
      continue
    }
    IFS=$'\t' read -r tag filename url <<< "$resolved"
    p=$(probe "$url"); st="${p%%$'\t'*}"; sz="${p##*$'\t'}"
    if [ "$st" = "200" ]; then
      if [ "$sz" -gt 0 ] 2>/dev/null; then
        row "$(green OK)" "$platform/$name/$filename" "$tag, $(human "$sz")"
        total=$(( total + sz ))
      else
        row "$(green OK)" "$platform/$name/$filename" "$tag, unknown size"
      fi
    else
      row "$(red FAIL)" "$platform/$name/$filename" "HTTP $st"
      bad=$((bad+1))
    fi
  done
fi

echo
echo "Python tool wheelhouses"
if [ "${#python_tool_entries[@]}" -eq 0 ]; then
  row "$(yellow SKIP)" "(none configured)" ""
else
  if python3 -m pip --version >/dev/null 2>&1; then
    pip_status="pip available"
  else
    pip_status="python3 pip missing — needed for fetch-python-tools"
    bad=$((bad+1))
  fi
  for entry in "${python_tool_entries[@]}"; do
    IFS='|' read -r name spec notes <<< "$entry"
    if [ "$pip_status" = "pip available" ]; then
      row "$(green OK)" "$name" "configured: $spec"
    else
      row "$(red FAIL)" "$name" "$pip_status"
    fi
  done
fi

echo
echo "Maps"
if [ "${#map_entries[@]}" -eq 0 ] && [ "${#map_resolver_entries[@]}" -eq 0 ]; then
  row "$(yellow SKIP)" "(no maps configured)" ""
else
  for entry in "${map_entries[@]}"; do
    IFS='|' read -r platform provider region filename url sha256 notes <<< "$entry"
    p=$(probe "$url"); st="${p%%$'\t'*}"; sz="${p##*$'\t'}"
    if [ "$st" = "200" ]; then
      if [ "$sz" -gt 0 ] 2>/dev/null; then
        row "$(green OK)" "$platform/$provider/$region/$filename" "$(human "$sz")"
        total=$(( total + sz ))
      else
        row "$(green OK)" "$platform/$provider/$region/$filename" "unknown size"
      fi
    else
      row "$(red FAIL)" "$platform/$provider/$region/$filename" "HTTP $st"
      bad=$((bad+1))
    fi
  done

  for entry in "${map_resolver_entries[@]}"; do
    IFS='|' read -r platform provider region resolver pattern sha256 notes <<< "$entry"
    resolved=$(resolve_app "$resolver" "$pattern") || {
      row "$(red FAIL)" "$platform/$provider/$region" "could not resolve $resolver"
      bad=$((bad+1))
      continue
    }
    IFS=$'\t' read -r tag filename url <<< "$resolved"
    p=$(probe "$url"); st="${p%%$'\t'*}"; sz="${p##*$'\t'}"
    if [ "$st" = "200" ]; then
      if [ "$sz" -gt 0 ] 2>/dev/null; then
        row "$(green OK)" "$platform/$provider/$region/$filename" "$tag, $(human "$sz")"
        total=$(( total + sz ))
      else
        row "$(green OK)" "$platform/$provider/$region/$filename" "$tag, unknown size"
      fi
    else
      row "$(red FAIL)" "$platform/$provider/$region/$filename" "HTTP $st"
      bad=$((bad+1))
    fi
  done
fi

echo
echo "Web map extracts"
if [ "${#web_map_entries[@]}" -eq 0 ]; then
  row "$(yellow SKIP)" "(no browser maps configured)" ""
else
  for entry in "${web_map_entries[@]}"; do
    IFS='|' read -r provider region source maxzoom bbox notes <<< "$entry"
    case "$source" in
      protomaps-latest)
        p=$(probe "https://build-metadata.protomaps.dev/builds.json"); st="${p%%$'\t'*}"
        if [ "$st" = "200" ]; then
          row "$(green OK)" "$provider/$region" "will extract maxzoom ${maxzoom:-12} from latest Protomaps build"
        else
          row "$(red FAIL)" "$provider/$region" "build metadata HTTP $st"
          bad=$((bad+1))
        fi
        ;;
      http://*|https://*)
        p=$(probe "$source"); st="${p%%$'\t'*}"
        if [ "$st" = "200" ]; then
          row "$(green OK)" "$provider/$region" "will extract maxzoom ${maxzoom:-12}"
        else
          row "$(red FAIL)" "$provider/$region" "source HTTP $st"
          bad=$((bad+1))
        fi
        ;;
      *)
        row "$(red FAIL)" "$provider/$region" "unknown source $source"
        bad=$((bad+1))
        ;;
    esac
  done
fi

echo
echo "iOS prep links"
if [ "${#ios_link_entries[@]}" -eq 0 ]; then
  row "$(yellow SKIP)" "(none configured)" ""
else
  for entry in "${ios_link_entries[@]}"; do
    IFS='|' read -r name url notes <<< "$entry"
    p=$(probe "$url"); st="${p%%$'\t'*}"; sz="${p##*$'\t'}"
    if [ "$st" = "200" ]; then
      row "$(green OK)" "$name" "link reachable"
    elif [ "$st" = "429" ]; then
      row "$(yellow WARN)" "$name" "rate limited by app store; link kept"
    else
      row "$(red FAIL)" "$name" "HTTP $st"
      bad=$((bad+1))
    fi
  done
fi

# ── things that aren't plain URLs ────────────────────────────────────────────
echo
echo "Tool-driven content (size not knowable in advance)"
if printf '%s\n' "${python_tool_entries[@]}" | awk -F'|' '$1 == "kolibri" {found=1} END {exit !found}'; then
  row "$(green OK)" "kolibri CLI" "configured for /apps/python wheelhouse"
elif command -v kolibri >/dev/null; then
  row "$(green OK)" "kolibri CLI" "installed"
else
  row "$(yellow WARN)" "kolibri CLI" "missing — add kolibri to PYTHON_TOOL_PACKAGES"
fi
for entry in "${kolibri_entries[@]}"; do
  label="${entry%%|*}"; cid="${entry#*|}"
  if [ "$cid" = "CHANNEL_ID_HERE" ]; then
    row "$(red FAIL)" "$label" "placeholder channel ID — set it in scripts/kit.conf"
    bad=$((bad+1))
  else
    row "$(green OK)" "$label" "$cid"
  fi
done
set -u

if printf '%s\n' "${python_tool_entries[@]}" | awk -F'|' '$1 == "argostranslate" {found=1} END {exit !found}'; then
  row "$(green OK)" "argostranslate" "configured for /apps/python wheelhouse"
elif python3 -c "import argostranslate.package" 2>/dev/null; then
  row "$(green OK)" "argostranslate" "installed"
else
  row "$(yellow WARN)" "argostranslate" "missing — add argostranslate to PYTHON_TOOL_PACKAGES"
fi

# ── verdict ──────────────────────────────────────────────────────────────────
free_gb=$(df -k "$KIT_ROOT" | awk 'NR==2 {print int($4/1048576)}')
need_gb=$(awk -v b="$total" 'BEGIN{printf "%.0f", b/1073741824}')

echo
echo "══════════════════════════════════════════════════════════════════════════"
echo "  direct downloads   $(human "$total")"
echo "  free on $KIT_ROOT  ${free_gb} GB"
echo
if [ "$need_gb" -gt "$free_gb" ]; then
  echo "  $(red "NOT ENOUGH SPACE") — need ${need_gb} GB, have ${free_gb} GB"
  bad=$((bad+1))
else
  echo "  space is fine — ${need_gb} GB of ${free_gb} GB"
fi
echo
echo "  Kolibri is not counted above. Full Khan Academy English is roughly"
echo "  200 GB on its own, so budget for that separately."
echo

if [ "$bad" -eq 0 ]; then
  set +u
  missing_stages=()
  for stage in fetch-zims fetch-models fetch-apps fetch-python-tools fetch-maps build-kiwix-library build-web-maps fetch-kolibri fetch-argos; do
    [ -x "$HERE/$stage.sh" ] || missing_stages+=( "scripts/$stage.sh" )
  done

  if [ "${#missing_stages[@]}" -eq 0 ]; then
    echo "  $(green "All checks passed.") Run ./update when ready."
  else
    echo "  $(green "All remote checks passed.") Add missing fetch stages before ./update:"
    printf '    %s\n' "${missing_stages[@]}"
  fi
  set -u
else
  echo "  $(red "$bad problem(s).") Fix scripts/kit.conf, or check the mirror for renamed"
  echo "  builds, before starting the real download."
fi
echo

exit $(( bad > 0 ))
