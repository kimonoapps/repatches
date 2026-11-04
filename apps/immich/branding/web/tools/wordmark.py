"""wordmark.py <font.woff2> <size> <text> -> JSON {"d": svg path, "width": advance, "ascent", "descent"}.
Text drawn as outlines so the logo needs no web font when shown as an <img>."""
import json, sys
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

font = TTFont(sys.argv[1]); size = float(sys.argv[2]); text = sys.argv[3]
upm = font["head"].unitsPerEm; scale = size / upm
cmap = font.getBestCmap(); glyphs = font.getGlyphSet(); hmtx = font["hmtx"]
pen = SVGPathPen(glyphs, ntos=lambda v: f"{v:.2f}".rstrip("0").rstrip("."))
x = 0.0
for ch in text:
    name = cmap[ord(ch)]
    glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x, 0)))
    x += hmtx[name][0] * scale
os2 = font["OS/2"]
print(json.dumps({"d": pen.getCommands(), "width": round(x, 2),
                  "ascent": os2.sCapHeight * scale if getattr(os2, "sCapHeight", 0) else os2.sTypoAscender * scale,
                  "descent": -os2.sTypoDescender * scale}))
