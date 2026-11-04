// Draws Kimono Photos' phone artwork from Kimono's own bloom code, so the app
// icon is the same flower the Portal shows on the Photos tile. Run it when
// Kimono's bloom, the Photos accent or this file changes, and commit files/:
//
//   node apps/immich/branding/mobile/generate.mjs ~/dev/kimono
//
// Needs a Kimono checkout with dependencies installed (for TypeScript and sharp).
import { createRequire } from "node:module";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const kimono = process.argv[2];
if (!kimono) throw new Error("usage: node generate.mjs <kimono checkout>");
const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, "files", "mobile");
const require = createRequire(join(kimono, "apps/mobile/package.json"));
const sharp = require("sharp");
const ts = createRequire(join(kimono, "packages/ui/package.json"))("typescript");

/* Kimono Photos, as apps/portal/app-definitions/immich/app.json declares it. */
const definition = JSON.parse(readFileSync(join(kimono, "apps/portal/app-definitions/immich/app.json"), "utf8"));
const app = { id: definition.metadata.id, accent: definition.metadata.colors[0], glyph: definition.metadata.glyph };

/* Load packages/ui's bloom without a bundler: transpile the four files it needs. */
const work = mkdtempSync(join(tmpdir(), "kimono-bloom-"));
for (const name of ["bloom-svg.ts", "bloom-identity.ts", "accent.ts", "glyphs.tsx"]) {
  let source = readFileSync(join(kimono, "packages/ui/src", name), "utf8");
  source = source.replace(/^import .* from "react";?$/gm, "");
  const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022, jsx: ts.JsxEmit.React } }).outputText
    .replace(/from "\.\/([a-z-]+)"/g, 'from "./$1.mjs"');
  writeFileSync(join(work, name.replace(/\.tsx?$/, ".mjs")), js);
}
const { bloomSvg } = await import(pathToFileURL(join(work, "bloom-svg.mjs")));
const { accentRamp } = await import(pathToFileURL(join(work, "accent.mjs")));
rmSync(work, { recursive: true });

const bloom = bloomSvg({ id: app.id, accent: app.accent }, { glyph: app.glyph, standalone: true, unique: app.id });
const ground = "#f7f1e8", night = "#1c1618", plum = "#34262a", paper = "#fffaf2";
const inner = bloom.replace(/^<svg[^>]*>/, "").replace(/<\/svg>$/, "");

/* The bloom drawn at `share` of a size×size canvas, on `background` or clear. */
const bloomAt = (size, share, background) => {
  const box = size * share, at = (size - box) / 2;
  return Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}">${background ? `<rect width="100%" height="100%" fill="${background}"/>` : ""}<svg x="${at}" y="${at}" width="${box}" height="${box}" viewBox="0 0 100 100">${inner}</svg></svg>`);
};
const files = [];
const png = (path, input, { flatten } = {}) => {
  files.push(path);
  const full = join(out, path);
  mkdirSync(dirname(full), { recursive: true });
  let image = sharp(input);
  if (flatten) image = image.flatten({ background: flatten });
  return image.png().toFile(full);
};
/* A one-colour silhouette of the bloom, for monochrome and notification icons. */
const silhouette = async (size, share, colour) => {
  const alpha = await sharp(bloomAt(size, share)).ensureAlpha().extractChannel("alpha").toBuffer();
  return sharp({ create: { width: size, height: size, channels: 3, background: colour } }).joinChannel(alpha).png().toBuffer();
};
const solid = (colour) => sharp({ create: { width: 1, height: 1, channels: 3, background: colour } }).png().toBuffer();

/* "KIMONO / PHOTOS", set like Kimono's wordmark (Georgia, spaced capitals, a rule). */
const lockup = (ink, accent) => Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="2400" height="600" viewBox="0 0 240 60"><text x="120" y="30" text-anchor="middle" fill="${ink}" font-family="Georgia, 'Times New Roman', serif" font-size="30" letter-spacing="5">KIMONO</text><rect x="72" y="42" width="22" height="1.2" fill="${accent}"/><text x="102" y="46.5" fill="${accent}" font-family="Arial, Helvetica, sans-serif" font-size="9" font-weight="700" letter-spacing="3">PHOTOS</text></svg>`);

const ramp = accentRamp(app.accent);
const densities = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };
const jobs = [
  // In-app logo, sign-in title, and the images flutter_native_splash would make.
  png("assets/immich-logo.png", bloomAt(1024, 1)),
  png("assets/immich-splash.png", bloomAt(320, 1)),
  png("assets/immich-splash-android12.png", bloomAt(1152, 768 / 1152 * 0.8)),
  png("assets/immich-text-light.png", lockup(plum, ramp.deep)),
  png("assets/immich-text-dark.png", lockup(paper, definition.metadata.colors[2])),
  // Android launcher: legacy square icons, and adaptive layers (safe zone is the middle 66%).
  ...Object.entries(densities).flatMap(([dpi, scale]) => [
    png(`android/app/src/main/res/mipmap-${dpi}/ic_launcher.png`, bloomAt(48 * scale, 0.78, ground)),
    png(`android/app/src/main/res/drawable-${dpi}/splash.png`, bloomAt(80 * scale, 1)),
    png(`android/app/src/main/res/drawable-${dpi}/android12splash.png`, bloomAt(288 * scale, 0.53)),
    png(`android/app/src/main/res/drawable-night-${dpi}/android12splash.png`, bloomAt(288 * scale, 0.53)),
    silhouette(24 * scale, 0.9, "#ffffff").then((b) => png(`android/app/src/main/res/drawable-${dpi}/notification_icon.png`, b)),
  ]),
  png("android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png", bloomAt(432, 0.6)),
  silhouette(432, 0.6, "#000000").then((b) => png("android/app/src/main/res/drawable-nodpi/ic_launcher_monochrome.png", b)),
  ...["drawable", "drawable-v21"].map(async (d) => png(`android/app/src/main/res/${d}/background.png`, await solid(ground))),
  ...["drawable-night", "drawable-night-v21"].map(async (d) => png(`android/app/src/main/res/${d}/background.png`, await solid(night))),
  // iPhone: every AppIcon size upstream ships (named by pixel size), opaque; launch screen.
  ...[16, 20, 29, 32, 40, 48, 50, 55, 57, 58, 60, 64, 66, 72, 76, 80, 87, 88, 92, 100, 102, 114, 120, 128, 144, 152, 167, 172, 180, 196, 216, 256, 512, 1024]
    .map((px) => png(`ios/Runner/Assets.xcassets/AppIcon.appiconset/${px}.png`, bloomAt(px, 0.78, ground), { flatten: ground })),
  ...[["LaunchImage.png", 80], ["LaunchImage@2x.png", 160], ["LaunchImage@3x.png", 240]]
    .map(([name, px]) => png(`ios/Runner/Assets.xcassets/LaunchImage.imageset/${name}`, bloomAt(px, 1))),
  solid(ground).then((b) => png("ios/Runner/Assets.xcassets/LaunchBackground.imageset/background.png", b)),
  solid(night).then((b) => png("ios/Runner/Assets.xcassets/LaunchBackground.imageset/darkbackground.png", b)),
];
await Promise.all(jobs);
writeFileSync(join(here, "colors.json"), JSON.stringify({ accent: app.accent, ramp, ground, night }, null, 2) + "\n");
console.log(`wrote ${files.length} files to ${out}`);
