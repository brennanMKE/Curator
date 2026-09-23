#!/usr/bin/env python3
"""Turns potrace's SVG of Curator.png into the app icon layer and the menu bar symbol.

    sips -s format bmp Curator.png --out robot.bmp
    potrace robot.bmp -s -o robot.svg -t 8 -a 1.0 -O 0.4
    Tools/trace_icon.py robot.svg

potrace writes paths in a y-flipped, 10x space; this rewrites them into plain image pixels
so they can be placed without nested transforms (the symbol compiler wants flat paths).
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOKEN = re.compile(r"[MmCcLlZz]|-?\d+(?:\.\d+)?")
ARGS = {"M": 2, "m": 2, "C": 6, "c": 6, "L": 2, "l": 2, "Z": 0, "z": 0}


def parse(d):
    """Yields (command, [numbers]) with implicit repeats expanded."""
    tokens = TOKEN.findall(d)
    i, cmd = 0, None
    while i < len(tokens):
        if tokens[i] in ARGS:
            cmd = tokens[i]
            i += 1
            if ARGS[cmd] == 0:
                yield cmd, []
                continue
        n = ARGS[cmd]
        yield cmd, [float(t) for t in tokens[i:i + n]]
        i += n
        if cmd == "M":
            cmd = "l"  # SVG: extra pairs after M are lineto (potrace writes relative)
        elif cmd == "m":
            cmd = "l"


def to_image_space(d, height):
    """Absolute image-pixel path segments plus bounding box."""
    out, x, y, start = [], 0.0, 0.0, (0.0, 0.0)
    xs, ys = [], []
    for cmd, v in parse(d):
        if cmd in "Mm":
            if cmd == "M":
                x, y = v[0] * 0.1, height - v[1] * 0.1
            else:
                x, y = x + v[0] * 0.1, y - v[1] * 0.1
            start = (x, y)
            out.append(("M", [(x, y)]))
        elif cmd in "Cc":
            pts = []
            for k in range(0, 6, 2):
                if cmd == "C":
                    pts.append((v[k] * 0.1, height - v[k + 1] * 0.1))
                else:
                    pts.append((x + v[k] * 0.1, y - v[k + 1] * 0.1))
            x, y = pts[-1]
            out.append(("C", pts))
        elif cmd in "Ll":
            if cmd == "L":
                x, y = v[0] * 0.1, height - v[1] * 0.1
            else:
                x, y = x + v[0] * 0.1, y - v[1] * 0.1
            out.append(("L", [(x, y)]))
        else:
            x, y = start
            out.append(("Z", []))
        for px, py in (out[-1][1] or []):
            xs.append(px)
            ys.append(py)
    return out, (min(xs), min(ys), max(xs), max(ys))


def emit(segments, scale, dx, dy):
    parts = []
    for cmd, pts in segments:
        coords = " ".join(f"{px * scale + dx:.2f} {py * scale + dy:.2f}" for px, py in pts)
        parts.append(f"{cmd} {coords}".strip())
    return " ".join(parts)


def union(boxes):
    return (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))


def main(source):
    svg = Path(source).read_text()
    height = float(re.search(r'viewBox="0 0 [\d.]+ ([\d.]+)"', svg).group(1))
    paths = [to_image_space(d, height) for d in re.findall(r'<path d="([^"]+)"', svg, re.S)]
    for segs, box in paths:
        print("path bbox", [round(b) for b in box], file=sys.stderr)

    write_icon_layer(paths)
    write_symbol([p for p in paths if p[1][3] < BUST_BOTTOM])


# Hat, head and neck; the bow tie starts below.
BUST_BOTTOM = 550


def write_icon_layer(paths):
    """White robot centred on a 1024-point Icon Composer canvas."""
    box = union([b for _, b in paths])
    target_height = 700
    scale = target_height / (box[3] - box[1])
    dx = 512 - (box[0] + box[2]) / 2 * scale
    dy = 512 - (box[1] + box[3]) / 2 * scale + 8
    body = "\n".join(f'  <path fill="#ffffff" d="{emit(s, scale, dx, dy)}"/>' for s, _ in paths)
    out = ROOT / "Curator/AppIcon.icon/Assets/Curator.svg"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">\n'
        f"{body}\n</svg>\n"
    )
    print("wrote", out, file=sys.stderr)


def write_symbol(paths):
    """A custom SF Symbol (Regular-M only) of the robot's hat and head."""
    box = union([b for _, b in paths])
    # Cap height at Regular-M is ~70.5; let the bust run a little above it and below the baseline.
    top, bottom = -78.0, 8.0
    scale = (bottom - top) / (box[3] - box[1])
    width = (box[2] - box[0]) * scale
    left_margin, baseline = 1349.64, 1126.0
    bearing = 4.0
    dx = bearing - box[0] * scale
    dy = top - box[1] * scale
    body = "\n".join(f'   <path d="{emit(s, scale, dx, dy)}"/>' for s, _ in paths)
    right_margin = left_margin + width + 2 * bearing

    guide = 'style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;"'
    margin = 'style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;"'
    out = ROOT / "Curator/Assets.xcassets/curator.bust.symbolset/curator.bust.svg"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="3300" height="2200">
<!--glyph: "curator.bust", point size: 100.0, template writer version: "Tools/trace_icon.py"-->
<g id="Notes">
  <rect height="2200" id="artboard" style="fill:white;opacity:1" width="3300" x="0" y="0"/>
  <text id="template-version" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;" transform="matrix(1 0 0 1 3036 1933)">Template v.3.0</text>
</g>
<g id="Guides">
  <line id="Baseline-S" {guide} x1="263" x2="3036" y1="696" y2="696"/>
  <line id="Capline-S" {guide} x1="263" x2="3036" y1="625.541" y2="625.541"/>
  <line id="Baseline-M" {guide} x1="263" x2="3036" y1="1126" y2="1126"/>
  <line id="Capline-M" {guide} x1="263" x2="3036" y1="1055.54" y2="1055.54"/>
  <line id="Baseline-L" {guide} x1="263" x2="3036" y1="1556" y2="1556"/>
  <line id="Capline-L" {guide} x1="263" x2="3036" y1="1485.54" y2="1485.54"/>
  <line id="left-margin-Regular-M" {margin} x1="{left_margin:.2f}" x2="{left_margin:.2f}" y1="1030.79" y2="1150.12"/>
  <line id="right-margin-Regular-M" {margin} x1="{right_margin:.2f}" x2="{right_margin:.2f}" y1="1030.79" y2="1150.12"/>
</g>
<g id="Symbols">
  <g id="Regular-M" transform="matrix(1 0 0 1 {left_margin:.2f} {baseline:.2f})">
{body}
  </g>
</g>
</svg>
''')
    (out.parent / "Contents.json").write_text('''{
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "symbols" : [
    {
      "filename" : "curator.bust.svg",
      "idiom" : "universal"
    }
  ]
}
''')
    print("wrote", out, file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1])
