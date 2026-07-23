#!/usr/bin/env bash
# build-web-maps.sh - create laptop browser maps from configured PMTiles extracts.

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib.sh"

preflight
manifest_begin

rc=0
keep_file=$(mktemp)
maps_meta=$(mktemp)
trap 'rm -f "$keep_file" "$maps_meta"' EXIT

set +u
web_map_entries=( "${WEB_MAP_EXTRACTS[@]}" )
set -u

keep() {
  printf '%s\n' "$1" >> "$keep_file"
}

keep_map_meta() {
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$maps_meta"
}

host_pmtiles() {
  local os arch root archive bin

  if command -v pmtiles >/dev/null; then
    command -v pmtiles
    return 0
  fi

  os=$(uname -s)
  arch=$(uname -m)
  case "$os:$arch" in
    Darwin:arm64)
      root="$APP_MACOS_DIR/pmtiles-arm64"
      archive=$(find "$root" -maxdepth 1 -type f -name 'go-pmtiles-*_Darwin_arm64.zip' 2>/dev/null | sort | tail -n1)
      ;;
    Darwin:x86_64)
      root="$APP_MACOS_DIR/pmtiles-x86_64"
      archive=$(find "$root" -maxdepth 1 -type f -name 'go-pmtiles-*_Darwin_x86_64.zip' 2>/dev/null | sort | tail -n1)
      ;;
    Linux:x86_64)
      root="$APP_LINUX_DIR/pmtiles-x86_64"
      archive=$(find "$root" -maxdepth 1 -type f -name 'go-pmtiles_*_Linux_x86_64.tar.gz' 2>/dev/null | sort | tail -n1)
      ;;
    *)
      return 1
      ;;
  esac

  [ -n "${archive:-}" ] || return 1
  mkdir -p "$root/extracted"
  case "$archive" in
    *.zip) unzip -oq "$archive" -d "$root/extracted" ;;
    *.tar.gz) tar -xzf "$archive" -C "$root/extracted" ;;
    *) return 1 ;;
  esac
  bin=$(find "$root/extracted" -type f -name pmtiles | sort | tail -n1)
  [ -n "$bin" ] || return 1
  chmod +x "$bin" 2>/dev/null || true
  printf '%s\n' "$bin"
}

pmtiles_maxzoom() {
  local pmtiles_bin="$1" path="$2"
  "$pmtiles_bin" show "$path" --header-json 2>/dev/null | python3 -c '
import json
import sys

try:
    print(json.load(sys.stdin).get("maxzoom", -1))
except Exception:
    print(-1)
'
}

latest_protomaps_source() {
  curl -fsSL --max-time 60 "https://build-metadata.protomaps.dev/builds.json" | python3 -c '
import json
import sys

builds = json.load(sys.stdin)
builds = sorted(builds, key=lambda item: item.get("key", ""), reverse=True)
if not builds:
    raise SystemExit(1)
print("https://build.protomaps.com/" + builds[0]["key"])
'
}

resolve_source() {
  case "$1" in
    protomaps-latest) latest_protomaps_source ;;
    http://*|https://*) printf '%s\n' "$1" ;;
    *) return 1 ;;
  esac
}

write_viewer() {
  local viewer="$MAPS_DIR/viewer" assets="$MAPS_DIR/viewer/assets"
  local font_dir="$assets/fonts/Noto Sans Regular" range

  [ "$DRY_RUN" = 0 ] || return 0

  mkdir -p "$assets" "$font_dir"

  fetch_verified \
    "https://unpkg.com/maplibre-gl@${MAPLIBRE_VERSION:-6.0.0}/dist/maplibre-gl.mjs" \
    "$assets/maplibre-gl.mjs" \
    "map-viewer:maplibre-js" \
    "" || rc=1
  keep "$assets/maplibre-gl.mjs"

  fetch_verified \
    "https://unpkg.com/maplibre-gl@${MAPLIBRE_VERSION:-6.0.0}/dist/maplibre-gl-shared.mjs" \
    "$assets/maplibre-gl-shared.mjs" \
    "map-viewer:maplibre-shared-js" \
    "" || rc=1
  keep "$assets/maplibre-gl-shared.mjs"

  fetch_verified \
    "https://unpkg.com/maplibre-gl@${MAPLIBRE_VERSION:-6.0.0}/dist/maplibre-gl-worker.mjs" \
    "$assets/maplibre-gl-worker.mjs" \
    "map-viewer:maplibre-worker-js" \
    "" || rc=1
  keep "$assets/maplibre-gl-worker.mjs"

  fetch_verified \
    "https://unpkg.com/maplibre-gl@${MAPLIBRE_VERSION:-6.0.0}/dist/maplibre-gl.css" \
    "$assets/maplibre-gl.css" \
    "map-viewer:maplibre-css" \
    "" || rc=1
  keep "$assets/maplibre-gl.css"

  for range in 0-255 256-511 512-767 768-1023; do
    fetch_verified \
      "https://protomaps.github.io/basemaps-assets/fonts/Noto%20Sans%20Regular/$range.pbf" \
      "$font_dir/$range.pbf" \
      "map-viewer:glyphs:noto-sans-regular:$range" \
      "" || rc=1
    keep "$font_dir/$range.pbf"
  done

  python3 - "$maps_meta" "$viewer/maps.json" <<'PY'
import json
import sys

items = []
with open(sys.argv[1], "r", encoding="utf-8") as handle:
    for line in handle:
        provider, region, bbox, maxzoom, notes = line.rstrip("\n").split("\t")
        west, south, east, north = [float(part) for part in bbox.split(",")]
        items.append({
            "provider": provider,
            "region": region,
            "label": region.replace("-", " ").title(),
            "tilejson": f"/{region}.json",
            "bbox": [west, south, east, north],
            "center": [(west + east) / 2, (south + north) / 2],
            "zoom": 5,
            "maxzoom": int(maxzoom),
            "notes": notes,
        })

with open(sys.argv[2], "w", encoding="utf-8") as out:
    json.dump(items, out, indent=2)
    out.write("\n")
PY
  keep "$viewer/maps.json"

  cat > "$viewer/index.html" <<'EOF'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Ark Maps</title>
  <link rel="stylesheet" href="assets/maplibre-gl.css">
  <style>
    html, body, #map { height: 100%; margin: 0; }
    body { font-family: ui-sans-serif, system-ui, sans-serif; background: #f6f1e8; }
    #panel {
      position: absolute; z-index: 10; top: 16px; left: 16px; max-width: 320px;
      padding: 14px; border-radius: 16px; background: rgba(255, 252, 246, 0.94);
      box-shadow: 0 12px 40px rgba(38, 31, 20, 0.22);
    }
    h1 { margin: 0 0 10px; font-size: 18px; }
    select, button { width: 100%; margin-top: 8px; padding: 9px; font: inherit; }
    .hint { margin-top: 10px; color: #5e5347; font-size: 13px; line-height: 1.35; }
  </style>
</head>
<body>
  <div id="panel">
    <h1>Ark Maps</h1>
    <select id="region"></select>
    <button id="fit">Fit Region</button>
    <div class="hint">Served entirely from this Ark drive. If tiles do not load, start maps with <code>./ark-maps</code>.</div>
  </div>
  <div id="map"></div>
  <script type="module">
    import * as maplibregl from "./assets/maplibre-gl.mjs";

    const params = new URLSearchParams(location.search);
    const tileBase = params.get("tiles") || `http://${location.hostname || "127.0.0.1"}:8082`;
    const regionSelect = document.getElementById("region");
    const fitButton = document.getElementById("fit");
    let maps = [];
    let current = null;

    const styleFor = (entry) => ({
      version: 8,
      glyphs: "assets/fonts/{fontstack}/{range}.pbf",
      sources: {
        protomaps: {
          type: "vector",
          url: tileBase + entry.tilejson,
          attribution: "© OpenStreetMap contributors, Protomaps"
        }
      },
      layers: [
        { id: "background", type: "background", paint: { "background-color": "#f6f1e8" } },
        { id: "earth", type: "fill", source: "protomaps", "source-layer": "earth", paint: { "fill-color": "#f1eadb" } },
        { id: "landcover", type: "fill", source: "protomaps", "source-layer": "landcover", paint: { "fill-color": "#dce8c8", "fill-opacity": 0.45 } },
        { id: "landuse", type: "fill", source: "protomaps", "source-layer": "landuse", paint: { "fill-color": "#e7ddbf", "fill-opacity": 0.42 } },
        { id: "water", type: "fill", source: "protomaps", "source-layer": "water", paint: { "fill-color": "#9fc9df" } },
        { id: "water-lines", type: "line", source: "protomaps", "source-layer": "water", paint: { "line-color": "#79aec9", "line-width": ["interpolate", ["linear"], ["zoom"], 5, 0.5, 12, 2] } },
        { id: "roads-minor", type: "line", source: "protomaps", "source-layer": "roads", filter: ["in", ["get", "kind"], ["literal", ["minor_road", "path"]]], paint: { "line-color": "#ffffff", "line-width": ["interpolate", ["linear"], ["zoom"], 6, 0.2, 12, 2.2] } },
        { id: "roads-major", type: "line", source: "protomaps", "source-layer": "roads", filter: ["in", ["get", "kind"], ["literal", ["highway", "major_road"]]], paint: { "line-color": "#d0834f", "line-width": ["interpolate", ["linear"], ["zoom"], 5, 0.7, 12, 4] } },
        { id: "boundaries", type: "line", source: "protomaps", "source-layer": "boundaries", paint: { "line-color": "#8d8175", "line-dasharray": [3, 2], "line-width": 1 } },
        { id: "buildings", type: "fill", source: "protomaps", "source-layer": "buildings", minzoom: 12, paint: { "fill-color": "#c9bda9", "fill-opacity": 0.7 } },
        {
          id: "region-labels",
          type: "symbol",
          source: "protomaps",
          "source-layer": "places",
          filter: ["in", ["get", "kind"], ["literal", ["country", "region"]]],
          layout: {
            "text-field": ["coalesce", ["get", "name:en"], ["get", "name:latin"], ["get", "name"]],
            "text-font": ["Noto Sans Regular"],
            "text-size": ["interpolate", ["linear"], ["zoom"], 3, 13, 7, 18],
            "text-transform": "uppercase",
            "text-letter-spacing": 0.08,
            "text-allow-overlap": false
          },
          paint: {
            "text-color": "#786b5e",
            "text-halo-color": "#f6f1e8",
            "text-halo-width": 1.4
          }
        },
        {
          id: "city-labels",
          type: "symbol",
          source: "protomaps",
          "source-layer": "places",
          filter: ["==", ["get", "kind"], "locality"],
          layout: {
            "text-field": ["coalesce", ["get", "name:en"], ["get", "name:latin"], ["get", "name"]],
            "text-font": ["Noto Sans Regular"],
            "text-size": ["interpolate", ["linear"], ["zoom"], 4, 12, 8, 16, 12, 22],
            "text-anchor": "center",
            "text-offset": [0, 0.25],
            "text-allow-overlap": false
          },
          paint: {
            "text-color": "#2f2a24",
            "text-halo-color": "#fffaf0",
            "text-halo-width": 1.6
          }
        },
        {
          id: "major-road-labels",
          type: "symbol",
          source: "protomaps",
          "source-layer": "roads",
          minzoom: 8,
          filter: ["has", "name"],
          layout: {
            "symbol-placement": "line",
            "symbol-spacing": 360,
            "text-field": ["coalesce", ["get", "name"], ["get", "ref"], ["get", "shield_text"]],
            "text-font": ["Noto Sans Regular"],
            "text-size": ["interpolate", ["linear"], ["zoom"], 9, 10, 13, 13, 16, 16],
            "text-rotation-alignment": "map",
            "text-pitch-alignment": "viewport",
            "text-allow-overlap": false
          },
          paint: {
            "text-color": "#604126",
            "text-halo-color": "#fffaf0",
            "text-halo-width": 1.3
          }
        },
        {
          id: "street-labels",
          type: "symbol",
          source: "protomaps",
          "source-layer": "roads",
          minzoom: 13,
          filter: ["has", "name"],
          layout: {
            "symbol-placement": "line",
            "symbol-spacing": 260,
            "text-field": ["get", "name"],
            "text-font": ["Noto Sans Regular"],
            "text-size": ["interpolate", ["linear"], ["zoom"], 12, 10, 15, 13, 17, 16],
            "text-rotation-alignment": "map",
            "text-pitch-alignment": "viewport",
            "text-allow-overlap": false
          },
          paint: {
            "text-color": "#5f5a50",
            "text-halo-color": "#fffaf0",
            "text-halo-width": 1.2
          }
        }
      ]
    });

    const map = new maplibregl.Map({
      container: "map",
      style: { version: 8, sources: {}, layers: [{ id: "background", type: "background", paint: { "background-color": "#f6f1e8" } }] },
      center: [-8, 40],
      zoom: 5
    });
    map.addControl(new maplibregl.NavigationControl(), "bottom-right");

    function fit(entry) {
      map.fitBounds([[entry.bbox[0], entry.bbox[1]], [entry.bbox[2], entry.bbox[3]]], { padding: 40, duration: 0 });
    }

    function load(entry) {
      current = entry;
      map.setStyle(styleFor(entry));
      fit(entry);
    }

    fetch("maps.json")
      .then((response) => response.json())
      .then((entries) => {
        maps = entries;
        regionSelect.innerHTML = maps.map((entry, index) => `<option value="${index}">${entry.label}</option>`).join("");
        regionSelect.addEventListener("change", () => load(maps[Number(regionSelect.value)]));
        fitButton.addEventListener("click", () => current && fit(current));
        if (maps.length) load(maps[0]);
      });
  </script>
</body>
</html>
EOF
  keep "$viewer/index.html"
}

echo
log "Web maps"

if [ "${#web_map_entries[@]}" -eq 0 ]; then
  log "SKIP  no web map extracts configured"
  manifest_commit
  exit 0
fi

if [ "$DRY_RUN" = 1 ]; then
  for entry in "${web_map_entries[@]}"; do
    IFS='|' read -r provider region source maxzoom bbox notes <<< "$entry"
    resolved=$(resolve_source "$source") || {
      warn "web-map:$provider:$region could not resolve $source"
      rc=1
      continue
    }
    log "DRY   would extract $provider/$region maxzoom ${maxzoom:-12} from $resolved"
  done
  manifest_commit
  exit "$rc"
fi

pmtiles_bin=$(host_pmtiles) || {
  warn "pmtiles CLI not available; run fetch-apps first or install pmtiles"
  manifest_commit
  exit 1
}

for entry in "${web_map_entries[@]}"; do
  IFS='|' read -r provider region source maxzoom bbox notes <<< "$entry"
  label="web-map:$provider:$region"
  dir="$MAPS_DIR/web/$provider"
  dest="$dir/$region.pmtiles"
  partial="$dest.partial"
  keep "$dest"

  resolved=$(resolve_source "$source") || {
    warn "$label could not resolve $source"
    rc=1
    continue
  }

  if [ -f "$dest" ] && "$pmtiles_bin" show "$dest" >/dev/null 2>&1; then
    existing_maxzoom=$(pmtiles_maxzoom "$pmtiles_bin" "$dest")
    if [ "$existing_maxzoom" -lt "${maxzoom:-12}" ] 2>/dev/null; then
      log "REBUILD $label — existing maxzoom $existing_maxzoom, want ${maxzoom:-12}"
    else
      size=$(wc -c < "$dest" | tr -d ' ')
      log "SKIP  $label — already built ($(human "$size"))"
      record "$label" "pmtiles-extract:$resolved#$bbox" "$size"
      keep_map_meta "$provider" "$region" "$bbox" "${maxzoom:-12}" "${notes:-}"
      continue
    fi
  fi

  mkdir -p "$dir"
  rm -f "$partial"
  log "EXTRACT $label — bbox $bbox, maxzoom ${maxzoom:-12}"
  if "$pmtiles_bin" extract "$resolved" "$partial" --bbox="$bbox" --maxzoom="${maxzoom:-12}" --download-threads="${PMTILES_DOWNLOAD_THREADS:-8}"; then
    mv "$partial" "$dest"
    size=$(wc -c < "$dest" | tr -d ' ')
    record "$label" "pmtiles-extract:$resolved#$bbox" "$size"
    keep_map_meta "$provider" "$region" "$bbox" "${maxzoom:-12}" "${notes:-}"
    log "OK    $label — $(human "$size")"
  else
    rm -f "$partial"
    warn "$label extract failed"
    rc=1
  fi
done

write_viewer

if [ "$PRUNE" = 1 ]; then
  prune_unlisted "$MAPS_DIR/web" "$keep_file"
fi

manifest_commit
exit "$rc"
