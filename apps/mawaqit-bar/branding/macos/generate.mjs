// Draws Kimono Prayer's Mac icon: Kimono Prayer's bloom (crescent glyph, Prayer's accent, as
// apps/portal/app-definitions/prayer/app.json declares it) on Kimono's paper, then runs upstream's
// own icon pipeline (macos/Assets/make-icon.swift, then iconutil) so the shapes and sizes are
// exactly upstream's. Run it when the bloom, the Prayer accent or this file changes, and commit files/:
//
//   node apps/mawaqit-bar/branding/macos/generate.mjs ~/dev/kimono
//
// Needs macOS (swiftc, iconutil) and a Kimono checkout with dependencies installed
// (TypeScript in packages/ui, sharp in apps/portal).
import { createRequire } from "node:module";
import { execFileSync } from "node:child_process";
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const kimono = process.argv[2];
if (!kimono) throw new Error("usage: node generate.mjs <kimono checkout>");
const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "../../../..");
const upstreamAssets = join(root, "upstream/mawaqit-bar/macos/Assets");
const out = join(here, "files/macos/Assets");
const require = createRequire(join(kimono, "apps/portal/package.json"));
const sharp = require("sharp");
const ts = createRequire(join(kimono, "packages/ui/package.json"))("typescript");

const definition = JSON.parse(readFileSync(join(kimono, "apps/portal/app-definitions/prayer/app.json"), "utf8"));
const app = { id: definition.metadata.id, accent: definition.metadata.colors[0], glyph: definition.metadata.glyph };

/* Load packages/ui's bloom without a bundler, as apps/immich/branding/mobile/generate.mjs does. */
const work = mkdtempSync(join(tmpdir(), "kimono-prayer-icon-"));
for (const name of ["bloom-svg.ts", "bloom-identity.ts", "ink-bloom.ts", "ink.ts", "accent.ts", "glyphs.tsx"]) {
  let source = readFileSync(join(kimono, "packages/ui/src", name), "utf8");
  source = source.replace(/^import .* from "react";?$/gm, "");
  const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022, jsx: ts.JsxEmit.React } }).outputText
    .replace(/from "\.\/([a-z-]+)"/g, 'from "./$1.mjs"');
  writeFileSync(join(work, name.replace(/\.tsx?$/, ".mjs")), js);
}
const { bloomSvg } = await import(pathToFileURL(join(work, "bloom-svg.mjs")));
const bloom = bloomSvg({ id: app.id, accent: app.accent }, { glyph: app.glyph, standalone: true, unique: app.id });
const inner = bloom.replace(/^<svg[^>]*>/, "").replace(/<\/svg>$/, "");

/* make-icon.swift crops 140 px off each side of a 1254 px master and clips the rest to Apple's
   rounded square, so the bloom fills about 60% of what's left, on paper edge to edge. */
const paper = "#f7f1e8", size = 1254, box = 680, at = (size - box) / 2;
const master = Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}"><rect width="100%" height="100%" fill="${paper}"/><svg x="${at}" y="${at}" width="${box}" height="${box}" viewBox="0 0 100 100">${inner}</svg></svg>`);
const assets = join(work, "Assets");
mkdirSync(join(assets, "AppIcon.iconset"), { recursive: true });
cpSync(join(upstreamAssets, "AppIcon.icon"), join(assets, "AppIcon.icon"), { recursive: true });
await sharp(master).flatten({ background: paper }).png().toFile(join(assets, "AppIcon-master.png"));
execFileSync("swiftc", [join(upstreamAssets, "make-icon.swift"), "-o", join(work, "make-icon")], { stdio: "inherit" });
execFileSync(join(work, "make-icon"), [assets], { stdio: "inherit" });
execFileSync("iconutil", ["-c", "icns", join(assets, "AppIcon.iconset"), "-o", join(assets, "Mawaqit.icns")], { stdio: "inherit" });
/* The DMG window: upstream's drawing, naming Kimono Prayer. */
const background = readFileSync(join(upstreamAssets, "make-dmg-background.swift"), "utf8").replace(/Drag Mawaqit to/g, "Drag Kimono Prayer to");
if (!background.includes("Drag Kimono Prayer to")) throw new Error("make-dmg-background.swift no longer says \"Drag Mawaqit to\"");
writeFileSync(join(work, "make-dmg-background.swift"), background);
execFileSync("swiftc", [join(work, "make-dmg-background.swift"), "-o", join(work, "make-dmg-background")], { stdio: "inherit" });
execFileSync(join(work, "make-dmg-background"), [work], { stdio: "inherit" });
execFileSync("tiffutil", ["-cathidpicheck", join(work, "dmg-background.png"), join(work, "dmg-background@2x.png"), "-out", join(assets, "dmg-background.tiff")], { stdio: "inherit" });

rmSync(out, { recursive: true, force: true });
mkdirSync(join(out, "AppIcon.icon/Assets"), { recursive: true });
for (const file of ["AppIcon-master.png", "Mawaqit.icns", "AppIcon.icon/Assets/artwork.png", "dmg-background.tiff"]) cpSync(join(assets, file), join(out, file));
cpSync(join(assets, "AppIcon.iconset"), join(out, "AppIcon.iconset"), { recursive: true });
rmSync(work, { recursive: true });
console.log(`wrote ${out}`);
