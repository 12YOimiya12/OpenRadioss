#!/usr/bin/env python3
"""Render a layered swimlane .drawio into a PNG preview for visual QA.

Parses the mxGraphModel XML and draws containers (swimlanes), child boxes,
cylinders, and orthogonal edges with labels. Coordinates are resolved against
ancestor containers so child geometry is correct in page space. This is a
QA/preview helper for the drawio-skill workflow; the .drawio remains the
editable source of truth.
"""
import sys
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw, ImageFont

NS = {"mx": "http://www.mxgraph.io/"}

CJK_FONT = r"C:\Windows\Fonts\msyh.ttc"
LATIN_FONT = r"C:\Windows\Fonts\segoeui.ttf"


def color_of(style, key, default):
    for part in style.split(";"):
        if part.startswith(key + "="):
            val = part.split("=", 1)[1]
            return None if val.lower() == "none" else val
    return default


def fill_or(color, default="#ffffff", none_as="#ffffff"):
    if color is None or color.lower() == "none":
        return none_as
    return color


def is_white(hexcolor):
    c = hexcolor.lstrip("#")
    if len(c) == 3:
        c = "".join(ch * 2 for ch in c)
    return c.lower() in ("ffffff", "f5f5f5", "000000") or c.lower() in ("", )


def wrap_text(draw, text, font, max_w):
    if not text:
        return []
    lines = []
    for raw in text.split("\n"):
        cur = ""
        for ch in raw:
            if draw.textlength(cur + ch, font=font) <= max_w or not cur:
                cur += ch
            else:
                lines.append(cur)
                cur = ch
        lines.append(cur)
    return lines


def load_font(size, bold=False):
    for path in (CJK_FONT, LATIN_FONT):
        try:
            return ImageFont.truetype(path, size)
        except Exception:
            continue
    return ImageFont.load_default()


def parse(path):
    tree = ET.parse(path)
    root = tree.getroot()
    # find mxGraphModel
    graph = root.find(".//mxGraphModel", NS)
    cells = {}
    for cell in graph.findall("root/mxCell", NS):
        cid = cell.get("id")
        cells[cid] = {
            "value": cell.get("value", ""),
            "style": cell.get("style", ""),
            "vertex": cell.get("vertex") == "1",
            "edge": cell.get("edge") == "1",
            "parent": cell.get("parent", "1"),
            "source": cell.get("source"),
            "target": cell.get("target"),
            "geom": None,
        }
        g = cell.find("mxGeometry", NS)
        if g is not None:
            cells[cid]["geom"] = {
                "x": float(g.get("x", 0)),
                "y": float(g.get("y", 0)),
                "w": float(g.get("width", 0)),
                "h": float(g.get("height", 0)),
                "rel": g.get("relative") == "1",
            }
    return cells


def page_geometry(cells, cid):
    """Resolve page-space geometry by walking up parent containers."""
    c = cells[cid]
    g = c["geom"]
    if not g:
        return None
    if c["parent"] == "1" or c["parent"] == "0" or not c["parent"] in cells:
        # swimlane containers are top-level with absolute geometry
        return (g["x"], g["y"], g["w"], g["h"])
    pg = page_geometry(cells, c["parent"])
    if pg is None:
        return (g["x"], g["y"], g["w"], g["h"])
    # children of swimlane are relative to the container (x,y start at 0)
    return (pg[0] + g["x"], pg[1] + g["y"], g["w"], g["h"])


def render(path, out, scale=1.4):
    cells = parse(path)
    # compute bounding box over vertex cells
    rects = {}
    for cid, c in cells.items():
        if not c["vertex"]:
            continue
        pg = page_geometry(cells, cid)
        if pg is None:
            continue
        rects[cid] = pg
    x0 = min(r[0] for r in rects.values())
    y0 = min(r[1] for r in rects.values())
    x1 = max(r[0] + r[2] for r in rects.values())
    y1 = max(r[1] + r[3] for r in rects.values())
    pad = 20
    W = int((x1 - x0 + 2 * pad) * scale)
    H = int((y1 - y0 + 2 * pad) * scale)
    img = Image.new("RGB", (W, H), "white")
    draw = ImageDraw.Draw(img)

    def T(x, y):
        return ((x - x0 + pad) * scale, (y - y0 + pad) * scale)

    # Draw edges first (behind boxes)
    for cid, c in cells.items():
        if not c["edge"]:
            continue
        s, t = c["source"], c["target"]
        if s not in rects or t not in rects:
            continue
        sx0, sy0, sw, sh = rects[s]
        tx0, ty0, tw, th = rects[t]
        # connect center-to-center
        p1 = (sx0 + sw / 2, sy0 + sh / 2)
        p2 = (tx0 + tw / 2, ty0 + th / 2)
        color = color_of(c["style"], "strokeColor", "#666666")
        dashed = "dashed=1" in c["style"]
        # clamp start/end to nearest side boundary for cleaner look
        draw.line([T(*p1), T(*p2)], fill=color, width=max(1, int(scale * 1.4)))
        if c.get("value"):
            mx = (p1[0] + p2[0]) / 2
            my = (p1[1] + p2[1]) / 2
            wtxt = c["value"].replace("&#10;", "\n").replace("&amp;", "&")
            f = load_font(int(11 * scale))
            draw.text(T(mx, my - 12), wtxt, fill=color, font=f)

    # Draw containers then children (top-level swimlanes first by y)
    def is_swim(style):
        return style.startswith("swimlane")

    ordered = sorted(rects.items(), key=lambda kv: rects[kv[0]][1])
    # top-level (parent == "1") drawn first
    container_ids = [cid for cid, c in cells.items() if c["vertex"] and is_swim(c["style"])]
    for cid in container_ids:
        x, y, w, h = rects[cid]
        fill = fill_or(color_of(cells[cid]["style"], "fillColor", "#ffffff"))
        stroke = fill_or(color_of(cells[cid]["style"], "strokeColor", "#666666"), default="#666666", none_as="#666666")
        draw.rounded_rectangle([T(x, y), T(x + w, y + h)], radius=int(6 * scale),
                               fill=fill, outline=stroke, width=int(scale * 1.4))
        # title bar
        title = cells[cid]["value"].replace("&#10;", "\n").replace("&amp;", "&")
        f = load_font(int(14 * scale), bold=True)
        draw.rectangle([T(x, y), T(x + w, y + 30)], fill=stroke)
        draw.text((T(x, y)[0] + 8, T(x, y)[1] + 6), title, fill="white", font=f)

    # draw non-swimlane vertex boxes (skip containers already drawn)
    for cid, pg in rects.items():
        if is_swim(cells[cid]["style"]):
            continue
        x, y, w, h = pg
        style = cells[cid]["style"]
        fill = fill_or(color_of(style, "fillColor", "#ffffff"))
        stroke = fill_or(color_of(style, "strokeColor", "#333333"), default="#333333", none_as="#333333")
        geom_rect = [T(x, y), T(x + w, y + h)]
        if "shape=cylinder3" in style:
            # simple cylinder: rect with rounded top
            draw.rounded_rectangle(geom_rect, radius=int(8 * scale), fill=fill,
                                   outline=stroke, width=int(scale * 1.2))
            draw.arc([T(x, y)[0], T(x, y)[1], T(x, y)[0] + w * scale, T(x, y)[1] + 18],
                     180, 360, fill=stroke, width=int(scale * 1.2))
        else:
            rounded = "rounded=1" in style
            if rounded:
                draw.rounded_rectangle(geom_rect, radius=int(6 * scale), fill=fill,
                                       outline=stroke, width=int(scale * 1.2))
            else:
                draw.rectangle(geom_rect, fill=fill, outline=stroke, width=int(scale * 1.2))
        # label
        label = cells[cid]["value"].replace("&#10;", "\n").replace("&amp;", "&")
        fsize = 12
        if "fontSize=11" in style:
            fsize = 11
        f = load_font(int(fsize * scale))
        font_color = color_of(style, "fontColor", "#000000")
        lines = wrap_text(draw, label, f, w * scale - 8)
        line_h = int(fsize * scale * 1.25)
        ty = y + (h - line_h * len(lines)) / 2
        for i, line in enumerate(lines):
            tw = draw.textlength(line, font=f)
            draw.text(T(x + (w - tw / scale) / 2, ty + i * line_h), line, fill=font_color, font=f)

    img.save(out)
    print(f"wrote {out} ({W}x{H})")


if __name__ == "__main__":
    render(sys.argv[1], sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else 1.4)
