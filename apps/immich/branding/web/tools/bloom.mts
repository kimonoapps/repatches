// Prints {"bloom": <standalone svg>, "ramp": {...}} for Kimono Photos, using Kimono's own renderer
// (packages/ui), so the mark is the one the Portal draws for this app. Bundled by make-assets.sh.
import { bloomSvg } from "KIMONO/packages/ui/src/bloom-svg.ts";
import { accentRamp } from "KIMONO/packages/ui/src/accent.ts";
const accent = process.env.ACCENT!;
const bloom = bloomSvg({ id: process.env.APP_ID!, accent }, { glyph: process.env.GLYPH as never, standalone: true, unique: "kp" });
process.stdout.write(JSON.stringify({ bloom, ramp: accentRamp(accent) }));
