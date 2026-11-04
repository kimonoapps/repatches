#!/usr/bin/env bash
# make-assets.sh [kimono-repo] — regenerate branding/web/files/ from Kimono's own sources. NOT run by
# install.sh: the outputs are committed, so building never needs the Kimono repo. Re-run when
# Kimono Photos' colours, glyph or the bloom renderer change.
# Needs: node, rsvg-convert, python3 with fonttools+brotli (PYTHON=...), esbuild (ESBUILD=...).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KIMONO="${1:-$HOME/dev/kimono}"
OUT="$HERE/../files"
PYTHON="${PYTHON:-python3}"
ESBUILD="${ESBUILD:-esbuild}"
APP_DEF="$KIMONO/apps/portal/app-definitions/immich/app.json"
FONT="$KIMONO/apps/portal/public/fonts/shippori-mincho-600-latin.woff2"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

read -r ACCENT GLYPH < <(node -e 'const m=require(process.argv[1]).metadata;console.log(m.colors[0],m.glyph)' "$APP_DEF")
sed "s#KIMONO/#$KIMONO/#" "$HERE/bloom.mts" > "$TMP/bloom.mts"
"$ESBUILD" "$TMP/bloom.mts" --bundle --platform=node --format=esm --jsx=automatic --log-level=error --outfile="$TMP/bloom.mjs"
ACCENT="$ACCENT" GLYPH="$GLYPH" APP_ID=immich node "$TMP/bloom.mjs" > "$TMP/bloom.json"
"$PYTHON" "$HERE/wordmark.py" "$FONT" 26 kimono > "$TMP/w1.json"
"$PYTHON" "$HERE/wordmark.py" "$FONT" 26 photos > "$TMP/w2.json"

mkdir -p "$OUT/web/static" "$OUT/web/src/lib/assets/kimono"
node --input-type=module - "$TMP" "$OUT" <<'JS'
import { readFileSync, writeFileSync } from "node:fs";
const [tmp, out] = process.argv.slice(2);
const { bloom, ramp } = JSON.parse(readFileSync(`${tmp}/bloom.json`, "utf8"));
const w1 = JSON.parse(readFileSync(`${tmp}/w1.json`, "utf8"));
const w2 = JSON.parse(readFileSync(`${tmp}/w2.json`, "utf8"));
const inner = bloom.replace(/^<svg[^>]*>/, "").replace(/<\/svg>$/, "");
const mark = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">${inner}</svg>`;
// The house lockup: bloom, "kimono" in plum, the app's name in its deep accent (Portal's AppLockup).
const lockup = (word, name) => {
  const h = 48, size = 40, gap = 8, space = 7, base = h / 2 + w1.ascent / 2;
  const x1 = size + gap, x2 = x1 + w1.width + space, width = Math.ceil(x2 + w2.width + 2);
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width} ${h}" width="${width}" height="${h}" role="img" aria-label="Kimono Photos">` +
    `<svg x="0" y="${(h - size) / 2}" width="${size}" height="${size}" viewBox="0 0 100 100">${inner}</svg>` +
    `<path transform="translate(${x1} ${base})" fill="${word}" d="${w1.d}"/>` +
    `<path transform="translate(${x2} ${base})" fill="${name}" d="${w2.d}"/></svg>`;
};
// Square app icons sit on flat paper (no gradients in chrome): `pad` is the share of the tile the bloom fills.
const tile = (pad) => {
  const s = 100 / pad, o = (s - 100) / 2;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${-o} ${-o} ${s} ${s}"><rect x="${-o}" y="${-o}" width="${s}" height="${s}" fill="#faf7f1"/>${inner}</svg>`;
};
const a = `${out}/web/src/lib/assets/kimono`;
writeFileSync(`${a}/logo-icon.svg`, mark);
writeFileSync(`${a}/logo-inline-light.svg`, lockup("#4e2b37", ramp.deep));
writeFileSync(`${a}/logo-inline-dark.svg`, lockup("#faf7f1", ramp.tint));
writeFileSync(`${out}/web/static/kimono-photos-mark.svg`, mark);
writeFileSync(`${tmp}/tile-apple.svg`, tile(0.82));
writeFileSync(`${tmp}/tile-maskable.svg`, tile(0.66));
JS

S="$OUT/web/static"
for n in 16 32 48 96 144; do rsvg-convert -w $n -h $n "$S/kimono-photos-mark.svg" -o "$S/favicon-$n.png"; done
rsvg-convert -w 256 -h 256 "$S/kimono-photos-mark.svg" -o "$S/favicon.png"
rsvg-convert -w 180 -h 180 "$TMP/tile-apple.svg" -o "$S/apple-icon-180.png"
rsvg-convert -w 192 -h 192 "$TMP/tile-maskable.svg" -o "$S/manifest-icon-192.maskable.png"
rsvg-convert -w 512 -h 512 "$TMP/tile-maskable.svg" -o "$S/manifest-icon-512.maskable.png"
# favicon.ico holding the 16/32/48 PNGs (PNG-in-ICO; every current browser reads it).
"$PYTHON" - "$S" <<'PY'
import struct, sys
d = sys.argv[1]; imgs = [open(f"{d}/favicon-{n}.png", "rb").read() for n in (16, 32, 48)]
head = struct.pack("<HHH", 0, 1, len(imgs)); off = 6 + 16 * len(imgs); dirs = b""
for n, data in zip((16, 32, 48), imgs):
    dirs += struct.pack("<BBBBHHII", n, n, 0, 0, 1, 32, len(data), off); off += len(data)
open(f"{d}/favicon.ico", "wb").write(head + dirs + b"".join(imgs))
PY
echo "wrote $(find "$OUT" -type f | wc -l | tr -d ' ') files to $OUT (accent $ACCENT, glyph $GLYPH)"
