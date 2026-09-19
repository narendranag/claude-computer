#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""render.py — draw the README diagrams as hand-laid SVG, in light and dark variants.

Usage:
  docs/diagrams/render.py            writes <name>.svg and <name>-dark.svg next to this file

The SVGs are build output; this file is the source. Edit the data tables below, rerun, commit both.
Fonts are system stacks (no web fonts), so the SVGs render the same on GitHub and in a blog.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from html import escape
from pathlib import Path

OUT = Path(__file__).resolve().parent
SANS = "Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif"
MONO = "ui-monospace, 'SF Mono', SFMono-Regular, Menlo, Consolas, monospace"


# ---------------------------------------------------------------------------
# Themes
# ---------------------------------------------------------------------------

LIGHT = dict(
    bg="#FBFAF7", card="#FFFFFF", sunk="#F3F1EC", ink="#1C1B19", muted="#6E6A63", faint="#A39E95",
    line="#E3DFD6", strong="#CFC9BD",
    git="#3355D1", r2="#D2740B", crypt="#9A3BB0", local="#9C978E",
    human="#C4461B", hand="#B07A12", claude="#2F5BD3",
    human_bg="#FBEEE8", hand_bg="#FAF3E3", claude_bg="#EDF1FC",
    rebuild_ink="#FFFFFF", accent="#0E7C66", accent_bg="#E4F3EF", tint=0.08,
)
DARK = dict(
    bg="#141417", card="#1D1D22", sunk="#18181C", ink="#ECEAE4", muted="#A29E95", faint="#6F6B64",
    line="#2E2D34", strong="#403F47",
    git="#7C9BFF", r2="#F2A444", crypt="#D48BE6", local="#8F8A82",
    human="#F08A62", hand="#E3B452", claude="#86A6FF",
    human_bg="#2A1D18", hand_bg="#28220F", claude_bg="#1A2032",
    rebuild_ink="#141417", accent="#4FD1B0", accent_bg="#15302A", tint=0.14,
)


# ---------------------------------------------------------------------------
# SVG primitives
# ---------------------------------------------------------------------------

class SVG:
    def __init__(self, w: int, h: int, t: dict, title: str, desc: str):
        self.w, self.h, self.t = w, h, t
        self.parts: list[str] = []
        self.title, self.desc = title, desc
        self.markers: set[str] = set()

    def add(self, s: str) -> None:
        self.parts.append(s)

    def marker(self, color: str) -> str:
        mid = "m" + color.lstrip("#")
        self.markers.add(color)
        return f"url(#{mid})"

    def render(self) -> str:
        defs = "".join(
            f'<marker id="m{c.lstrip("#")}" viewBox="0 0 10 10" refX="8.5" refY="5" markerWidth="7" markerHeight="7" '
            f'orient="auto-start-reverse"><path d="M1,1 L9,5 L1,9 z" fill="{c}"/></marker>'
            for c in sorted(self.markers)
        )
        hatch = (
            f'<pattern id="hatch" width="8" height="8" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">'
            f'<line x1="0" y1="0" x2="0" y2="8" stroke="{self.t["line"]}" stroke-width="3"/></pattern>'
        )
        return (
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w} {self.h}" width="{self.w}" height="{self.h}" '
            f'role="img" aria-labelledby="t d" font-family="{SANS}">'
            f'<title id="t">{escape(self.title)}</title><desc id="d">{escape(self.desc)}</desc>'
            f"<defs>{defs}{hatch}</defs>"
            f'<rect width="{self.w}" height="{self.h}" fill="{self.t["bg"]}"/>' + "".join(self.parts) + "</svg>\n"
        )

    # shapes ---------------------------------------------------------------
    def rect(self, x, y, w, h, r=10, fill=None, stroke=None, sw=1, dash=None, opacity=None):
        a = f'x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill or "none"}"'
        if stroke:
            a += f' stroke="{stroke}" stroke-width="{sw}"'
        if dash:
            a += f' stroke-dasharray="{dash}"'
        if opacity is not None:
            a += f' fill-opacity="{opacity}"'
        self.add(f"<rect {a}/>")

    def line(self, x1, y1, x2, y2, stroke, sw=1, dash=None, end=False, start=False, cap="round"):
        a = f'x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="{cap}"'
        if dash:
            a += f' stroke-dasharray="{dash}"'
        if end:
            a += f' marker-end="{self.marker(stroke)}"'
        if start:
            a += f' marker-start="{self.marker(stroke)}"'
        self.add(f"<line {a}/>")

    def path(self, d, stroke, sw=1.5, dash=None, end=False, start=False, fill="none", opacity=None):
        a = f'd="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round"'
        if dash:
            a += f' stroke-dasharray="{dash}"'
        if end:
            a += f' marker-end="{self.marker(stroke)}"'
        if start:
            a += f' marker-start="{self.marker(stroke)}"'
        if opacity is not None:
            a += f' stroke-opacity="{opacity}"'
        self.add(f"<path {a}/>")

    def text(self, x, y, s, size=13, weight=400, fill=None, anchor="start", mono=False, ls=None, italic=False, upper=False):
        s = s.upper() if upper else s
        a = f'x="{x}" y="{y}" font-size="{size}" font-weight="{weight}" fill="{fill or self.t["ink"]}" text-anchor="{anchor}"'
        if mono:
            a += f' font-family="{MONO}"'
        if ls:
            a += f' letter-spacing="{ls}"'
        if italic:
            a += ' font-style="italic"'
        self.add(f"<text {a}>{escape(s)}</text>")

    def pill(self, x, y, label, color, filled=False, size=10.5, pad=8, h=20, mono=False, width=None):
        w = width or int(len(label) * size * (0.62 if mono else 0.58) + pad * 2)
        if filled:
            self.rect(x, y, w, h, r=h / 2, fill=color)
            self.text(x + w / 2, y + h / 2 + size * 0.36, label, size, 600, self.t["rebuild_ink"], "middle", mono)
        else:
            self.rect(x, y, w, h, r=h / 2, fill=color, opacity=self.t["tint"], stroke=color, sw=1)
            self.text(x + w / 2, y + h / 2 + size * 0.36, label, size, 600, color, "middle", mono)
        return w

    def header(self, overline, title, sub, x=48):
        self.text(x, 58, overline, 11.5, 700, self.t["accent"], ls="0.14em", upper=True)
        self.text(x, 92, title, 27, 650, ls="-0.01em")
        for i, line in enumerate(sub if isinstance(sub, list) else [sub]):
            self.text(x, 120 + i * 20, line, 14.5, 400, self.t["muted"])

    # icons (drawn in a 20x20 box at x,y) ------------------------------------
    def icon_laptop(self, x, y, c):
        self.rect(x + 3, y + 3, 14, 10, r=1.5, stroke=c, sw=1.6)
        self.path(f"M{x+1},{y+16} L{x+19},{y+16}", c, 1.8)

    def icon_desktop(self, x, y, c):
        self.rect(x + 1, y + 2, 18, 12, r=1.5, stroke=c, sw=1.6)
        self.path(f"M{x+10},{y+14} L{x+10},{y+18} M{x+6},{y+18} L{x+14},{y+18}", c, 1.6)

    def icon_server(self, x, y, c):
        for i in range(3):
            self.rect(x + 2, y + 1 + i * 6.2, 16, 5, r=1.2, stroke=c, sw=1.4)
            self.add(f'<circle cx="{x+5.5}" cy="{y+3.5+i*6.2}" r="0.9" fill="{c}"/>')

    def icon_key(self, x, y, c):
        self.add(f'<circle cx="{x+6}" cy="{y+10}" r="4.2" fill="none" stroke="{c}" stroke-width="1.8"/>')
        self.path(f"M{x+10},{y+10} L{x+19},{y+10} M{x+16},{y+10} L{x+16},{y+14} M{x+19},{y+10} L{x+19},{y+13}", c, 1.8)

    def icon_plane(self, x, y, c):
        self.path(f"M{x+1},{y+9} L{x+19},{y+2} L{x+14},{y+18} L{x+9},{y+12} Z M{x+9},{y+12} L{x+19},{y+2}", c, 1.5)

    def icon_lock(self, x, y, c, s=1.0):
        self.rect(x + 3 * s, y + 8 * s, 12 * s, 9 * s, r=2 * s, fill=c)
        self.path(f"M{x+5.5*s},{y+8*s} L{x+5.5*s},{y+5.5*s} A{3.5*s},{3.5*s} 0 0 1 {x+12.5*s},{y+5.5*s} L{x+12.5*s},{y+8*s}", c, 1.6 * s)

    def icon_repo(self, x, y, c):
        self.add(f'<circle cx="{x+5}" cy="{y+4}" r="2.2" fill="none" stroke="{c}" stroke-width="1.5"/>')
        self.add(f'<circle cx="{x+5}" cy="{y+16}" r="2.2" fill="none" stroke="{c}" stroke-width="1.5"/>')
        self.add(f'<circle cx="{x+15}" cy="{y+7}" r="2.2" fill="none" stroke="{c}" stroke-width="1.5"/>')
        self.path(f"M{x+5},{y+6.2} L{x+5},{y+13.8} M{x+15},{y+9.2} C{x+15},{y+13} {x+5},{y+11} {x+5},{y+13.5}", c, 1.5)

    def icon_brain(self, x, y, c):
        # a node-graph glyph: "this folder has a brain"
        pts = [(4, 6), (10, 3), (16, 6), (6, 14), (14, 14), (10, 10)]
        for a, b in [(0, 1), (1, 2), (0, 5), (2, 5), (3, 5), (4, 5), (3, 4)]:
            self.line(x + pts[a][0], y + pts[a][1], x + pts[b][0], y + pts[b][1], c, 1.2)
        for px, py in pts:
            self.add(f'<circle cx="{x+px}" cy="{y+py}" r="1.9" fill="{c}"/>')

    def icon_cloud(self, x, y, c):
        self.path(
            f"M{x+5},{y+15} L{x+15},{y+15} A4,4 0 0 0 {x+15.5},{y+7} A5.5,5.5 0 0 0 {x+5},{y+8} A3.6,3.6 0 0 0 {x+5},{y+15} Z",
            c, 1.6,
        )

    def icon_github(self, x, y, c):
        self.add(f'<circle cx="{x+10}" cy="{y+10}" r="8.5" fill="none" stroke="{c}" stroke-width="1.6"/>')
        self.icon_repo(x + 3.5, y + 3.5, c) if False else None
        self.path(f"M{x+7},{y+6} L{x+7},{y+14} M{x+13},{y+8} C{x+13},{y+11} {x+7},{y+10} {x+7},{y+12.5}", c, 1.5)
        self.add(f'<circle cx="{x+13}" cy="{y+7}" r="1.5" fill="{c}"/>')


def card(svg: SVG, x, y, w, h, fill=None, stroke=None, r=14):
    t = svg.t
    svg.rect(x, y + 1.5, w, h, r=r, fill=t["line"], opacity=0.55)  # soft shadow
    svg.rect(x, y, w, h, r=r, fill=fill or t["card"], stroke=stroke or t["line"], sw=1)


# ---------------------------------------------------------------------------
# Diagram 1 — The map
# ---------------------------------------------------------------------------

@dataclass
class Row:
    name: str
    note: str
    brain: bool
    repo: bool
    sync: str  # git | r2 | crypt | local
    depth: int = 0


MAP_ROWS = [
    Row("claude-computer/", "the fleet brain · one clone per manager", True, True, "git"),
    Row("projects/*", "active work · one repo each", True, True, "git"),
    Row("_scratch/", "disposable · swept monthly", False, False, "local", 1),
    Row("products/*", "graduated · in production", True, True, "git"),
    Row("personal/*", "finance, personal projects", True, True, "git"),
    Row("vault/", "Obsidian second brain", True, True, "git"),
    Row("archive/", "staging only · R2 keeps the copy", True, False, "r2"),
    Row("library/camera", "RAW files + darktable sidecars", True, False, "r2"),
    Row("library/books, comics", "Calibre owns these", False, False, "r2"),
    Row("resources/<person>", "family key documents", True, False, "crypt"),
]
SYNC_LABEL = {"git": "git", "r2": "R2 →", "crypt": "R2 ⇄ crypt", "local": "local"}


def draw_map(t: dict) -> str:
    W, H = 1280, 940
    s = SVG(W, H, t, "The map",
            "Folders in the home directory, what each has (brain, repo), how each syncs (git to GitHub, rclone to "
            "Cloudflare R2, encrypted two-way for resources), and the fleet: manager machines on a Tailscale tailnet "
            "reaching headless boxes over SSH, Bitwarden feeding every script, Telegram receiving from every machine.")
    s.header("Diagram 1 · The map", "Where everything lives, and how it leaves the machine",
             "One brain per purpose folder. Each folder has exactly one way off the machine — and nothing else syncs.")

    # legend (top right)
    lx, ly = 842, 50
    s.icon_brain(lx, ly - 2, t["ink"]); s.text(lx + 26, ly + 12, "has a brain (CLAUDE.md)", 12, 500, t["muted"])
    s.icon_repo(lx, ly + 26, t["ink"]); s.text(lx + 26, ly + 40, "is a git repo", 12, 500, t["muted"])
    kx = lx + 200
    for i, (k, lab) in enumerate([("git", "git → GitHub"), ("r2", "rclone → R2"), ("crypt", "encrypted, two-way"), ("local", "not synced")]):
        yy = ly + (i // 2) * 28
        s.rect(kx, ly - 1 + i * 19, 18, 12, r=6, fill=t[k])
        s.text(kx + 26, ly + 9.5 + i * 19, lab, 12, 500, t["muted"])

    # --- Column A: the home directory --------------------------------------
    ax, ay, aw = 48, 176, 560
    row_h, top = 52, ay + 70
    ah = 70 + row_h * len(MAP_ROWS) + 22
    card(s, ax, ay, aw, ah)
    s.text(ax + 24, ay + 38, "~/", 20, 700, mono=True)
    s.text(ax + 56, ay + 38, "on every manager machine", 14.5, 500, t["muted"])
    s.line(ax + 24, ay + 54, ax + aw - 24, ay + 54, t["line"])

    chip_right = ax + aw - 22
    anchors: dict[int, tuple[float, float]] = {}
    tree_x = ax + 34
    first_y = top + 16
    last_top_level = max(i for i, r in enumerate(MAP_ROWS) if r.depth == 0)
    s.line(tree_x, first_y - 18, tree_x, top + last_top_level * row_h + 16, t["strong"], 1.2)
    for i, r in enumerate(MAP_ROWS):
        y = top + i * row_h
        cy = y + 16
        indent = r.depth * 26
        if r.depth:
            s.path(f"M{tree_x + 26},{cy - row_h + 26} L{tree_x + 26},{cy} L{tree_x + 26 + 14},{cy}", t["strong"], 1.2)
        else:
            s.line(tree_x, cy, tree_x + 14, cy, t["strong"], 1.2)
        nx = tree_x + 22 + indent
        weight = 650 if r.brain else 500
        s.text(nx, cy + 4, r.name, 14.5, weight, t["ink"] if r.depth == 0 else t["muted"], mono=True)
        s.text(nx, cy + 22, r.note, 12, 400, t["muted"])
        # badges
        bx = ax + 330
        if r.brain:
            s.icon_brain(bx, cy - 9, t["ink"])
        if r.repo:
            s.icon_repo(bx + 28, cy - 9, t["ink"])
        # sync chip
        c = t[r.sync]
        label = SYNC_LABEL[r.sync]
        cw = 96
        s.rect(chip_right - cw, cy - 11, cw, 22, r=11, fill=c, opacity=0.12 if r.sync != "local" else 0.0,
               stroke=c, sw=1.2, dash="3 3" if r.sync == "local" else None)
        if r.sync == "crypt":
            s.icon_lock(chip_right - cw + 8, cy - 9.5, c, 0.85)
            s.text(chip_right - cw / 2 + 8, cy + 4, label, 11.5, 650, c, "middle")
        else:
            s.text(chip_right - cw / 2, cy + 4, label, 11.5, 650, c, "middle")
        anchors[i] = (chip_right, cy)
        if i < len(MAP_ROWS) - 1:
            s.line(nx, y + row_h - 4, chip_right, y + row_h - 4, t["line"], 1)

    # --- Column B: destinations ---------------------------------------------
    bx, bw = 700, 250
    # GitHub
    gy, gh = 206, 272
    card(s, bx, gy, bw, gh)
    s.icon_github(bx + 20, gy + 18, t["git"])
    s.text(bx + 50, gy + 33, "GitHub", 16, 650)
    repos = [
        ("claude-computer", "private · the instance", "inst"),
        ("projects, products,", "personal, vault · private", "proj"),
        ("this template", "public · new instances start here", "tmpl"),
    ]
    gh_anchor = {}
    for i, (name, sub, key) in enumerate(repos):
        ry = gy + 62 + i * 68
        s.rect(bx + 16, ry, bw - 32, 54, r=9, fill=t["sunk"], stroke=t["line"])
        s.text(bx + 30, ry + 23, name, 12.5, 650, mono=True)
        s.text(bx + 30, ry + 41, sub, 11.5, 400, t["muted"])
        gh_anchor[key] = (bx, ry + 27)
    # template -> instance, drawn in the card's right gutter
    gx_ = bx + bw - 8
    s.path(f"M{bx + bw - 16},{gy + 62 + 2 * 68 + 27} L{gx_},{gy + 62 + 2 * 68 + 27} L{gx_},{gy + 62 + 27} L{bx + bw - 14},{gy + 62 + 27}",
           t["git"], 1.3, dash="3 3", end=True)

    # R2
    ry0, rh = 530, 262
    card(s, bx, ry0, bw, rh)
    s.icon_cloud(bx + 20, ry0 + 18, t["r2"])
    s.text(bx + 50, ry0 + 33, "Cloudflare R2", 16, 650)
    buckets = [("archive/", "one-way push · the only copy", "arch", "r2"),
               ("library/", "cold copy of camera, books", "lib", "r2"),
               ("resources/", "rclone crypt · names encrypted", "res", "crypt")]
    r2_anchor = {}
    for i, (name, sub, key, kind) in enumerate(buckets):
        yy = ry0 + 60 + i * 64
        s.rect(bx + 16, yy, bw - 32, 52, r=9, fill=t["sunk"], stroke=t["line"])
        if kind == "crypt":
            s.icon_lock(bx + 26, yy + 8, t["crypt"], 0.9)
            s.text(bx + 48, yy + 22, name, 12.5, 650, mono=True)
        else:
            s.text(bx + 30, yy + 22, name, 12.5, 650, mono=True)
        s.text(bx + 30, yy + 40, sub, 11.5, 400, t["muted"])
        r2_anchor[key] = (bx, yy + 26)

    # connectors A -> B
    def conn(i, target, color, dash=None, both=False):
        x1, y1 = anchors[i]
        x2, y2 = target
        mx = (x1 + x2) / 2
        s.path(f"M{x1 + 2},{y1} C{mx},{y1} {mx},{y2} {x2 - 3},{y2}", color, 1.6, dash=dash, end=True, start=both,
               opacity=0.9)

    conn(0, gh_anchor["inst"], t["git"], both=True)
    px_, py_ = gh_anchor["proj"]
    for k, i in enumerate((1, 3, 4, 5)):
        conn(i, (px_, py_ - 12 + k * 8), t["git"], both=True)
    conn(6, r2_anchor["arch"], t["r2"])
    lx_, ly_ = r2_anchor["lib"]
    conn(7, (lx_, ly_ - 5), t["r2"])
    conn(8, (lx_, ly_ + 5), t["r2"])
    conn(9, r2_anchor["res"], t["crypt"], dash="5 4", both=True)
    s.text(655, 262, "pull · push", 11, 600, t["git"], "middle")
    s.text(655, 590, "rclone", 11, 600, t["r2"], "middle")

    # --- Column C: the fleet ----------------------------------------------------
    cx, cw = 1004, 228
    fy, fh = 206, 440
    s.rect(cx - 14, fy, cw + 28, fh, r=18, fill=t["claude"], opacity=0.035, stroke=t["strong"], sw=1.3, dash="6 5")
    s.text(cx + 2, fy + 28, "tailnet", 12, 700, t["muted"], ls="0.12em", upper=True)
    s.text(cx + 66, fy + 28, "Tailscale, signed in with GitHub", 11.5, 400, t["muted"])

    devices = [("laptop", "pull on start · push on stop", "laptop"), ("desktop", "pull on start · push on stop", "desktop")]
    dev_y = []
    for i, (name, sub, kind) in enumerate(devices):
        yy = fy + 50 + i * 84
        card(s, cx, yy, cw, 68, r=12)
        (s.icon_laptop if kind == "laptop" else s.icon_desktop)(cx + 16, yy + 14, t["ink"])
        s.text(cx + 46, yy + 29, name, 14, 650)
        s.text(cx + 16, yy + 52, sub, 11.5, 400, t["muted"])
        dev_y.append(yy + 34)
    # GitHub instance -> managers
    ix, iy = gh_anchor["inst"]
    for k, dy in enumerate(dev_y):
        oy = iy - 6 + k * 12
        s.path(f"M{bx + bw + 2},{oy} C{bx + bw + 30},{oy} {cx - 44},{dy} {cx - 3},{dy}", t["git"], 1.5, end=True, start=True,
               opacity=0.9)

    hy = fy + 270
    card(s, cx, hy, cw, 146, r=12)
    s.icon_server(cx + 16, hy + 14, t["ink"])
    s.text(cx + 46, hy + 29, "headless boxes", 14, 650)
    s.text(cx + 16, hy + 54, "no brain · managed by any", 11.5, 400, t["muted"])
    s.text(cx + 16, hy + 70, "manager over SSH", 11.5, 400, t["muted"])
    s.rect(cx + 16, hy + 88, cw - 32, 42, r=8, fill=t["sunk"], stroke=t["line"])
    s.text(cx + 28, hy + 106, "/etc/claude-computer/", 11, 600, t["ink"], mono=True)
    s.text(cx + 28, hy + 121, "machine.md  ← backstop", 11, 600, t["muted"], mono=True)
    s.path(f"M{cx + cw / 2},{fy + 50 + 84 + 68 + 2} L{cx + cw / 2},{hy - 3}", t["ink"], 1.5, end=True)
    s.text(cx + cw / 2 + 10, hy - 26, "SSH over Tailscale", 11.5, 600, t["ink"])

    # --- Bottom: Bitwarden and Telegram -------------------------------------------
    by = ay + ah + 36
    card(s, ax, by, bx + bw - ax, 64)
    s.icon_key(ax + 22, by + 22, t["accent"])
    s.text(ax + 56, by + 29, "Bitwarden", 15, 700)
    s.text(ax + 142, by + 29, "every key, and nowhere else", 14, 500, t["ink"])
    s.text(ax + 56, by + 48, "bin/ wrappers read at run time with bw get · no keys in files, repos, rclone.conf, or the map", 12, 400, t["muted"])
    s.path(f"M{ax + 250},{by - 2} L{ax + 250},{ay + ah + 3}", t["accent"], 1.6, end=True)
    s.text(ax + 260, by - 13, "bw get", 11.5, 600, t["accent"])

    ty0 = by
    card(s, cx, ty0, cw, 64, r=12)
    s.icon_plane(cx + 16, ty0 + 18, t["accent"])
    s.text(cx + 46, ty0 + 29, "Telegram bot", 14, 650)
    s.text(cx + 16, ty0 + 50, "tg-send from every machine", 11.5, 400, t["muted"])
    s.path(f"M{cx + cw / 2},{fy + fh + 2} L{cx + cw / 2},{ty0 - 3}", t["accent"], 1.6, end=True)
    s.text(cx + cw / 2 - 10, fy + fh + 30, "[host] done · waiting · drift", 11.5, 600, t["accent"], "end")

    return s.render()


# ---------------------------------------------------------------------------
# Diagram 2 — The build
# ---------------------------------------------------------------------------

PHASES = ["Accounts", "Four commands", "Handover", "Foundation", "Environment", "Folders & brains", "Workflows", "Close the loop"]
# (step, phase, lane, label, rebuild) — lane: h human · c claude drives, human authenticates · a claude alone
# rebuild: 1 repeated on every rebuild · 0.5 role-dependent · 0 first machine only
STEPS = [
    (1, 0, "h", "Claude plan", 0), (2, 0, "h", "GitHub", 0), (3, 0, "h", "Tailscale", 0), (4, 0, "h", "Bitwarden", 0),
    (5, 0, "h", "Cloudflare", 0), (6, 0, "h", "Research keys", 0), (7, 0, "h", "PostHog", 0),
    (8, 0, "h", "Telegram bot", 0), (9, 0, "h", "Google OAuth", 0),
    (10, 1, "h", "xcode-select", 1), (11, 1, "h", "Homebrew", 1), (12, 1, "h", "gh auth login", 1), (13, 1, "h", "Claude Code", 1),
    (14, 2, "h", "Create or clone", 1),
    (15, 3, "a", "Identify host", 1), (16, 3, "c", "SSH key", 1), (17, 3, "c", "Tailscale login", 1),
    (18, 3, "h", "bw login", 1), (19, 3, "a", "Link ~/.claude", 1), (20, 3, "a", "Hooks live", 1),
    (21, 4, "a", "brew bundle", 1), (22, 4, "a", "Dotfiles", 1), (23, 4, "h", "Extensions", 0),
    (24, 4, "a", "Runtimes", 0), (25, 4, "a", "bin/ wrappers", 0), (26, 4, "a", "tg-send hello", 0),
    (27, 4, "h", "Google consent", 0.5), (28, 4, "h", "Time Machine", 0),
    (29, 5, "a", "Folders", 0), (30, 5, "c", "Vault", 1), (31, 5, "c", "Archive", 0),
    (32, 5, "c", "Camera", 0.5), (33, 5, "c", "Resources", 1), (34, 5, "c", "Headless boxes", 0),
    (35, 6, "a", "Tier 1 verified", 0), (36, 6, "a", "Tier 2 daily", 0),
    (37, 7, "a", "Re-capture", 0), (38, 7, "a", "Steady state", 0),
]
LANES = [("h", "human", "You", "only you can"), ("c", "hand", "Claude + you", "Claude drives, you log in"), ("a", "claude", "Claude", "Claude alone")]


def draw_build(t: dict) -> str:
    W, H = 1280, 900
    n_rebuild = sum(1 for st in STEPS if st[4] == 1)
    s = SVG(W, H, t, "The build",
            f"The 38 installation steps in eight phases and three lanes: human only, Claude drives while the human "
            f"authenticates, and Claude alone. The handover at step 14 is the pivot. {n_rebuild} steps are repeated "
            f"when rebuilding a machine.")
    s.header("Diagram 2 · The build", "38 steps. From step 15, Claude drives.",
             ["Before the handover you open accounts and type four commands. After it, you log in, grant and decide — nothing else.",
              f"Filled steps are what a second machine repeats: {n_rebuild} of 38."])

    gx, gy = 176, 206
    bw = (W - 48 - gx) / len(PHASES)
    pill_h, gap, pad = 24, 6, 14

    lane_rows = {}
    for code, *_ in LANES:
        lane_rows[code] = max(sum(1 for st in STEPS if st[1] == p and st[2] == code) for p in range(len(PHASES)))
    lane_rows["h"] = max(lane_rows["h"], 1)
    lane_y = {}
    y = gy + 44
    for code, *_ in LANES:
        h = pad * 2 + lane_rows[code] * (pill_h + gap) - gap
        h = max(h, 96)
        lane_y[code] = (y, h)
        y += h + 10
    grid_bottom = y - 10

    # phase bands
    for p, name in enumerate(PHASES):
        x = gx + p * bw
        if p % 2 == 0:
            s.rect(x, gy, bw, grid_bottom - gy, r=0, fill=t["sunk"])
        s.text(x + 12, gy + 18, f"{p}", 12, 700, t["faint"], mono=True)
        s.text(x + 28, gy + 18, name, 12.5, 650, t["ink"])
        count = sum(1 for st in STEPS if st[1] == p)
        s.text(x + 12, gy + 34, f"{count} step{'s' if count > 1 else ''}", 11, 400, t["muted"])

    # lanes
    for code, key, name, sub in LANES:
        ly, lh = lane_y[code]
        s.rect(gx, ly, W - 48 - gx, lh, r=10, fill=t[key], opacity=0.045, stroke=t[key], sw=0.8)
        s.rect(48, ly, gx - 60, lh, r=10, fill=t[f"{key}_bg"])
        s.rect(48, ly, 4, lh, r=2, fill=t[key])
        s.text(64, ly + 28, name, 15, 700, t[key])
        words = sub.split(" ")
        lines, cur = [], ""
        for wd in words:
            if len(cur) + len(wd) > 13:
                lines.append(cur.strip()); cur = ""
            cur += wd + " "
        lines.append(cur.strip())
        for i, ln in enumerate(lines):
            s.text(64, ly + 48 + i * 16, ln, 11.5, 400, t["muted"])

    # hatch the human lane after the handover
    hy, hh = lane_y["h"]
    pivot_x = gx + 3 * bw
    s.rect(pivot_x + 1, hy + 1, W - 48 - pivot_x - 2, hh - 2, r=9, fill="url(#hatch)", opacity=0.9)

    # steps
    for p in range(len(PHASES)):
        for code, key, *_ in LANES:
            items = [st for st in STEPS if st[1] == p and st[2] == code]
            ly, lh = lane_y[code]
            block = len(items) * (pill_h + gap) - gap
            y0 = ly + (lh - block) / 2 if code != "h" or p >= 3 else ly + pad
            for i, (num, _, _, label, rb) in enumerate(items):
                x = gx + p * bw + 8
                w = bw - 16
                yy = y0 + i * (pill_h + gap)
                c = t[key]
                if rb == 1:
                    s.rect(x, yy, w, pill_h, r=7, fill=c)
                    ink, num_ink = t["rebuild_ink"], t["rebuild_ink"]
                elif rb == 0.5:
                    s.rect(x, yy, w, pill_h, r=7, fill=t["card"], stroke=c, sw=1.4, dash="3 2.5")
                    ink, num_ink = t["ink"], c
                else:
                    s.rect(x, yy, w, pill_h, r=7, fill=t["card"], stroke=c, sw=1, opacity=None)
                    ink, num_ink = t["ink"], c
                s.text(x + 8, yy + 16.5, f"{num:>2}", 10.5, 700, num_ink, mono=True)
                s.text(x + 29, yy + 16.5, label, 11.5, 600, ink)

    # handover pivot
    s.line(pivot_x, gy - 6, pivot_x, grid_bottom + 8, t["ink"], 2.2)
    s.rect(pivot_x - 52, gy - 30, 104, 24, r=12, fill=t["ink"])
    s.text(pivot_x, gy - 13.5, "HANDOVER", 11, 700, t["bg"], "middle", ls="0.12em")
    s.text(pivot_x + 16, hy + hh - 16, "From here on you only log in, grant, and decide.", 12.5, 600, t["human"], italic=True)

    # legend
    ly = grid_bottom + 42
    s.rect(48, ly - 13, 44, 18, r=6, fill=t["claude"])
    s.text(100, ly + 1, "repeated when rebuilding a machine", 12.5, 500, t["muted"])
    s.rect(340, ly - 13, 44, 18, r=6, fill=t["card"], stroke=t["claude"], sw=1.4, dash="3 2.5")
    s.text(392, ly + 1, "depends on the machine's role", 12.5, 500, t["muted"])
    s.rect(600, ly - 13, 44, 18, r=6, fill=t["card"], stroke=t["claude"])
    s.text(652, ly + 1, "first machine only — already in the repo afterwards", 12.5, 500, t["muted"])
    s.text(W - 48, ly + 1, "Rebuild = clone the instance, run /setup", 12.5, 650, t["accent"], "end")

    s.h = int(ly + 34)
    return s.render()


# ---------------------------------------------------------------------------
# Diagram 3 — The session loop
# ---------------------------------------------------------------------------

def draw_loop(t: dict) -> str:
    W, H = 1280, 640
    s = SVG(W, H, t, "The session loop",
            "Every Claude Code session: the SessionStart hook pulls the shared repo and checks secrets; Claude identifies "
            "the machine and reads its file and the fleet index; it works; it records changes in the machine file, "
            "decisions and tasks; the Stop hook commits and pushes docs, so the next machine's session starts current.")
    s.header("Diagram 3 · The brain", "One shared repo. Every machine writes only its own file.",
             "Hooks make the sync automatic; ownership rules make conflicts rare by construction.")

    stages = [
        ("SessionStart hook", "automatic", ["git pull --rebase", "Bitwarden locked?", "tasks-sync"], "a"),
        ("Orient", "CLAUDE.md", ["identify host", "machines/<host>.md", "FLEET.md"], "a"),
        ("Work", "you decide", ["install, configure,", "manage boxes over SSH", "ask before destructive"], "c"),
        ("Record", "same session", ["update machines/<host>.md", "append DECISIONS.md", "TASKS.md · map-check"], "a"),
        ("Stop hook", "automatic", ["commit docs/ as [host]", "git push", "tg-send if long"], "a"),
    ]
    key = {"a": "claude", "c": "hand"}
    x0, y0, cw, ch, gap = 48, 176, 222, 164, 17
    for i, (title, tag, lines, lane) in enumerate(stages):
        x = x0 + i * (cw + gap)
        c = t[key[lane]]
        card(s, x, y0, cw, ch)
        s.rect(x, y0, cw, 5, r=2.5, fill=c)
        s.text(x + 18, y0 + 34, f"{i + 1}", 12, 700, c, mono=True)
        s.text(x + 36, y0 + 34, title, 15, 700)
        s.pill(x + 18, y0 + 48, tag, c, size=10.5, h=19)
        for j, ln in enumerate(lines):
            is_code = any(ch_ in ln for ch_ in ("<", "/", ".md", "git", "tg-", "tasks-", "map-"))
            s.text(x + 18, y0 + 96 + j * 21, ln, 12 if is_code else 12.5, 500 if is_code else 400,
                   t["ink"] if is_code else t["muted"], mono=is_code)
        if i < len(stages) - 1:
            s.line(x + cw + 2, y0 + ch / 2, x + cw + gap - 2, y0 + ch / 2, t["faint"], 1.6, end=True)

    # repo strip
    ry = 420
    card(s, 48, ry, W - 96, 108, fill=t["sunk"])
    s.icon_github(66, ry + 16, t["git"])
    s.text(96, ry + 31, "claude-computer", 15, 700, mono=True)
    s.text(242, ry + 31, "private · cloned on every manager", 12.5, 400, t["muted"])
    files = [
        ("machines/laptop.md", "written only by laptop", t["claude"]),
        ("machines/desktop.md", "written only by desktop", t["hand"]),
        ("machines/nas.md", "whichever manager touched it", t["faint"]),
        ("FLEET.md", "index · rarely changes", t["faint"]),
        ("DECISIONS.md", "append-only · always merges", t["faint"]),
    ]
    fx = 66
    fw = (W - 96 - 36 - 4 * 12) / 5
    for i, (name, sub, c) in enumerate(files):
        xx = fx + i * (fw + 12)
        s.rect(xx, ry + 50, fw, 44, r=8, fill=t["card"], stroke=t["line"])
        s.rect(xx, ry + 50, 4, 44, r=2, fill=c)
        s.text(xx + 16, ry + 68, name, 12, 650, mono=True)
        s.text(xx + 16, ry + 85, sub, 11, 400, t["muted"])

    # push arrow from stop hook, pull arrow into start hook
    sx = x0 + 4 * (cw + gap) + cw / 2
    s.path(f"M{sx},{y0 + ch + 3} L{sx},{ry - 4}", t["git"], 1.8, end=True)
    s.text(sx + 10, y0 + ch + 44, "push", 12, 650, t["git"])
    px = x0 + cw / 2
    s.path(f"M{px},{ry - 4} L{px},{y0 + ch + 3}", t["git"], 1.8, end=True)
    s.text(px + 10, y0 + ch + 44, "pull", 12, 650, t["git"])

    # next machine + backstop
    ny = ry + 108 + 34
    s.icon_desktop(48, ny - 2, t["muted"])
    s.text(78, ny + 13, "Next morning, on the desktop: the SessionStart hook pulls — the laptop's changes are already there.",
           13, 500, t["muted"])
    s.icon_server(W - 470, ny - 2, t["muted"])
    s.text(W - 440, ny + 13, "Changed a headless box? Copy its file to the box too.", 13, 500, t["muted"])
    s.h = ny + 44
    return s.render()


# ---------------------------------------------------------------------------
# Diagram 4 — Four forms, one rule
# ---------------------------------------------------------------------------

def draw_forms(t: dict) -> str:
    W = 1280
    s = SVG(W, 600, t, "Four forms, one rule",
            "Workflows take four forms: scripts in bin/ for anything deterministic; slash commands when judgment or a "
            "conversation is needed; hooks for what must happen every time; scheduled jobs for what must happen without "
            "a session. Commands, hooks and schedules all call scripts rather than reimplementing them.")
    s.header("Diagram 4 · Workflows", "If it can be a script, it's a script.",
             "Everything else is a way of deciding when a script runs — and who, if anyone, has to be in the room.")

    forms = [
        ("Slash command", "needs judgment or a conversation", "claude-global/commands/",
         ["/inbox", "/transcripts", "/today", "/new-app", "/review", "/setup"], "hand"),
        ("Hook", "must happen every time, without asking", "claude-global/settings.json",
         ["SessionStart → pull · transcripts · tasks", "Stop → push docs/ · tg-send", "Notification → tg-send"], "human"),
        ("Scheduled job", "must happen without a session", "bin/schedule → launchd",
         ["on change|transcripts-sync", "hourly|tasks-sync, resources-sync", "06:00|feeds-sync", "06:30|daily note", "09:00|map-check"], "r2"),
    ]
    lx, ly, lw, lh, gap = 48, 176, 600, 124, 16
    for i, (name, when, where, ex, key) in enumerate(forms):
        y = ly + i * (lh + gap)
        c = t[key]
        card(s, lx, y, lw, lh)
        s.rect(lx, y, 5, lh, r=2.5, fill=c)
        s.text(lx + 24, y + 32, name, 17, 700)
        s.text(lx + 24, y + 52, when, 13, 400, t["muted"])
        s.text(lx + 24, y + 104, where, 11.5, 600, c, mono=True)
        # examples (right half)
        ex_x = lx + 300
        if key == "hand":
            for j, e in enumerate(ex):
                col, row = j % 3, j // 3
                s.pill(ex_x + col * 98, y + 26 + row * 30, e, c, size=11, h=22, mono=True, width=92)
        else:
            step = 20 if len(ex) <= 4 else 17
            for j, e in enumerate(ex):
                if "|" in e:  # "when|what" in two aligned columns (SVG collapses runs of spaces)
                    when, what = e.split("|", 1)
                    s.text(ex_x, y + 28 + j * step, when, 11, 700, c, mono=True)
                    s.text(ex_x + 84, y + 28 + j * step, what, 11.5, 500, t["ink"], mono=True)
                else:
                    s.text(ex_x, y + 32 + j * step, e, 11.5, 500, t["ink"], mono=True)
        # arrow to bin/
        s.path(f"M{lx + lw + 4},{y + lh / 2} C{lx + lw + 60},{y + lh / 2} {lx + lw + 60},{ly + 200} {lx + lw + 112},{ly + 200}",
               t["faint"], 1.6, end=True)

    bx, by, bw, bh = lx + lw + 116, ly, W - 48 - (lx + lw + 116), 3 * lh + 2 * gap
    card(s, bx, by, bw, bh, stroke=t["accent"])
    s.rect(bx, by, bw, 5, r=2.5, fill=t["accent"])
    s.text(bx + 26, by + 40, "Script", 20, 700)
    s.text(bx + 26, by + 62, "deterministic · no judgment · answers --help", 13, 400, t["muted"])
    s.text(bx + bw - 26, by + 40, "bin/", 16, 700, t["accent"], "end", mono=True)
    groups = [
        ("plumbing", ["secrets-unlock", "tg-send", "tasks-sync", "map-check", "security-check", "schedule"]),
        ("research", ["tavily", "exa", "firecrawl", "jina", "browse"]),
        ("google", ["gcal", "gmail", "gdrive"]),
        ("storage", ["archive-push", "archive-pull", "camera-ingest", "resources-sync"]),
        ("daily", ["feeds-sync", "transcripts-sync", "new-app", "wt"]),
    ]
    gy = by + 96
    for g, names in groups:
        s.text(bx + 26, gy + 14, g, 11, 700, t["faint"], ls="0.1em", upper=True)
        xx = bx + 116
        for n in names:
            w = int(len(n) * 7.3 + 18)
            if xx + w > bx + bw - 20:
                gy += 28
                xx = bx + 116
            s.rect(xx, gy, w, 22, r=6, fill=t["sunk"], stroke=t["line"])
            s.text(xx + w / 2, gy + 15, n, 11.5, 550, t["ink"], "middle", mono=True)
            xx += w + 7
        gy += 38
    s.text(bx + 26, by + bh - 22, "Keys via bw get · output prefixed [host] · exit codes, not prose", 12, 500,
           t["muted"])
    s.h = by + bh + 44
    return s.render()


# ---------------------------------------------------------------------------
# Hero banner
# ---------------------------------------------------------------------------

def draw_hero(t: dict) -> str:
    W, H = 1280, 420
    s = SVG(W, H, t, "Install the operator first",
            "A terminal with the four commands a human types — Xcode command line tools, Homebrew, GitHub CLI, Claude "
            "Code — beside the list of what Claude Code then sets up: machine map, keys, Tailscale, Bitwarden, "
            "hooks, Brewfiles, brains, workflows.")
    s.text(48, 78, "ai-first machine setup", 12, 700, t["accent"], ls="0.16em", upper=True)
    s.text(46, 136, "Install the", 48, 700, ls="-0.02em")
    s.text(46, 188, "operator first.", 48, 700, ls="-0.02em")
    for i, ln in enumerate(["Type four commands. Claude Code sets up and", "runs everything else on your machines."]):
        s.text(48, 232 + i * 25, ln, 17.5, 400, t["muted"])
    for i, (lab, key) in enumerate([("you authenticate", "human"), ("you set the mode", "hand"), ("you decide", "claude")]):
        x = 48 + i * 158
        s.rect(x, 300, 148, 34, r=17, fill=t[key], opacity=t["tint"] + 0.04, stroke=t[key], sw=1.2)
        s.text(x + 74, 322, lab, 13.5, 650, t[key], "middle")
    s.text(48, 366, "The human's three jobs. The rest is scripts, hooks and conversation.", 13, 500, t["faint"])

    tx, ty, tw, th = 548, 48, 352, 324
    term_bg = "#15151A" if t is LIGHT else "#0C0C0F"
    card(s, tx, ty, tw, th, fill=term_bg, stroke="#2A2A31")
    for i, c in enumerate(["#FF5F57", "#FEBC2E", "#28C840"]):
        s.add(f'<circle cx="{tx + 20 + i * 16}" cy="{ty + 19}" r="5" fill="{c}"/>')
    s.text(tx + tw / 2, ty + 23, "Terminal.app", 11, 600, "#8A8790", "middle")
    lines = [("1", "$", "xcode-select --install"), ("2", "#", "Homebrew: the one-liner on brew.sh"),
             ("3", "$", "brew install gh"), ("", "$", "gh auth login"),
             ("4", "$", "brew install --cask claude-code"), ("", "$", "claude")]
    for i, (n, p, c) in enumerate(lines):
        y = ty + 70 + i * 34
        if n:
            s.text(tx + 20, y, n, 11, 700, "#5F5C66", mono=True)
        col = "#8A8790" if p == "#" else "#EDEBE6"
        s.text(tx + 40, y, f"{p} {c}", 12.5, 500, col, mono=True)
    s.rect(tx + 18, ty + th - 46, tw - 36, 28, r=7, fill="#24242B")
    s.text(tx + 32, ty + th - 27, "› paste docs/FIRST-PROMPT.md", 12.5, 600, "#7EE0C3", mono=True)

    ax = tx + tw
    s.path(f"M{ax + 12},{ty + th / 2} L{ax + 52},{ty + th / 2}", t["accent"], 2.2, end=True)

    cx, cy = ax + 64, ty
    cw = W - 48 - cx
    card(s, cx, cy, cw, th)
    s.text(cx + 22, cy + 34, "Then Claude Code", 14.5, 700)
    items = ["maps the machine", "adds its SSH key", "joins the tailnet", "wires Bitwarden",
             "links hooks + commands", "installs by role", "builds the brains", "files your meetings"]
    for i, it in enumerate(items):
        y = cy + 72 + i * 31
        s.add(f'<circle cx="{cx + 30}" cy="{y - 4}" r="8.5" fill="{t["accent"]}" fill-opacity="0.16"/>')
        s.path(f"M{cx + 26},{y - 4} L{cx + 29},{y - 1} L{cx + 34.5},{y - 8}", t["accent"], 1.8)
        s.text(cx + 48, y, it, 13.5, 500, t["ink"])
    return s.render()

def main() -> int:
    if any(a in ("-h", "--help") for a in sys.argv[1:]):
        print(__doc__)
        return 0
    for name, fn in [("hero", draw_hero), ("map", draw_map), ("build", draw_build), ("loop", draw_loop), ("forms", draw_forms)]:
        for suffix, theme in [("", LIGHT), ("-dark", DARK)]:
            svg = fn(theme)
            # SVG.render uses the final height; re-apply it to the viewBox/height attributes.
            (OUT / f"{name}{suffix}.svg").write_text(svg, encoding="utf-8")
    print("render.py: wrote", ", ".join(sorted(p.name for p in OUT.glob("*.svg"))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
