#!/usr/bin/env python3
"""Render captured ANSI output as an SVG terminal card."""
import re, sys, html

FG = {31: "#ff7b72", 32: "#3fb950", 33: "#e3b341", 34: "#79c0ff",
      35: "#d2a8ff", 36: "#56d4dd", 37: "#e6edf3"}
DEFAULT_FG = "#e6edf3"
TRACK = "#8b949e"   # surco de las barras, neutro para cualquier color
FONT = ("ui-monospace, SFMono-Regular, 'SF Mono', Menlo, Consolas, "
        "'DejaVu Sans Mono', 'Liberation Mono', monospace")
FS, LH, PAD, BAR = 15.0, 25.0, 24.0, 40.0
ADV = FS * 0.6

def parse(text):
    """-> [[(chars, color, bold, dim), ...], ...] one list per line."""
    lines, cur = [], []
    color, bold, dim = DEFAULT_FG, False, False
    buf = ""
    def flush():
        nonlocal buf
        if buf:
            cur.append((buf, color, bold, dim))
            buf = ""
    for tok in re.split(r"(\x1b\[[0-9;]*m|\n)", text):
        if not tok:
            continue
        if tok == "\n":
            flush(); lines.append(cur); cur = []
        elif tok.startswith("\x1b["):
            flush()
            for code in (int(c or 0) for c in tok[2:-1].split(";")):
                if code == 0:
                    color, bold, dim = DEFAULT_FG, False, False
                elif code == 1: bold = True
                elif code == 2: dim = True
                elif code == 22: bold = dim = False
                elif code == 39: color = DEFAULT_FG
                elif code in FG: color = FG[code]
        else:
            buf += tok
    flush()
    if cur or not lines:
        lines.append(cur)
    while lines and not lines[-1]:
        lines.pop()
    while lines and not lines[0]:
        lines.pop(0)
    return lines

BLOCKS = "\u2588\u2591"   # █ ░ : bar glyphs, drawn as shapes
RULE = "\u2500"            # ─   : separator, drawn as a line

def chunks(text):
    """Split a run into homogeneous pieces: bar, rule or plain text."""
    out, kind, buf = [], None, ""
    for ch in text:
        k = "bar" if ch in BLOCKS else "rule" if ch == RULE else "text"
        if k != kind and buf:
            out.append((kind, buf)); buf = ""
        kind, buf = k, buf + ch
    if buf:
        out.append((kind, buf))
    return out

def render(lines, title):
    cols = max((sum(len(t) for t, *_ in ln) for ln in lines), default=0)
    w = round(cols * ADV + 2 * PAD)
    h = round(len(lines) * LH + 2 * PAD + BAR - (LH - FS) / 2)
    out = [
      f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
      f'viewBox="0 0 {w} {h}" font-family="{FONT}" font-size="{FS}">',
      '<defs><linearGradient id="chrome" x1="0" y1="0" x2="0" y2="1">'
      '<stop offset="0" stop-color="#1c2128"/><stop offset="1" stop-color="#15181e"/>'
      '</linearGradient></defs>',
      f'<rect x="0.5" y="0.5" width="{w-1}" height="{h-1}" rx="11" fill="#0f1116" '
      'stroke="#2b313b"/>',
      f'<path d="M0.5 11.5A11 11 0 0 1 11.5 0.5H{w-11.5}A11 11 0 0 1 {w-0.5} 11.5V{BAR}H0.5Z" '
      'fill="url(#chrome)"/>',
      f'<line x1="0.5" y1="{BAR}" x2="{w-0.5}" y2="{BAR}" stroke="#2b313b"/>',
      '<circle cx="22" cy="20" r="6" fill="#ff5f57"/>'
      '<circle cx="42" cy="20" r="6" fill="#febc2e"/>'
      '<circle cx="62" cy="20" r="6" fill="#28c840"/>',
      f'<text x="{w/2}" y="25" fill="#6e7681" font-size="12.5" text-anchor="middle">'
      f'{html.escape(title)}</text>',
    ]
    y = BAR + PAD + FS * 0.82
    for ln in lines:
        col = 0
        for txt, color, bold, dim in ln:
            op = 0.55 if dim else 1.0
            for kind, piece in chunks(txt):
                x = PAD + col * ADV
                width = len(piece) * ADV
                if kind == "bar":
                    # A terminal paints these as solid cells; fonts disagree on
                    # their size, so draw the bar instead of typing it.
                    bh = FS * 0.58
                    by = y - FS * 0.72
                    filled = len(piece) - len(piece.lstrip("\u2588"))
                    out.append(
                        f'<rect x="{x:.1f}" y="{by:.1f}" width="{width:.1f}" '
                        f'height="{bh:.1f}" rx="2.5" fill="{TRACK}" '
                        f'opacity="{0.30 * op:.2f}"/>')
                    if filled:
                        out.append(
                            f'<rect x="{x:.1f}" y="{by:.1f}" width="{filled*ADV:.1f}" '
                            f'height="{bh:.1f}" rx="2.5" fill="{color}" '
                            f'opacity="{op:.2f}"/>')
                elif kind == "rule":
                    out.append(
                        f'<rect x="{x:.1f}" y="{y - FS*0.30:.1f}" width="{width:.1f}" '
                        f'height="1.1" fill="{color}" opacity="{op:.2f}"/>')
                elif piece.strip():
                    attrs = f'fill="{color}"'
                    if bold: attrs += ' font-weight="700"'
                    if dim:  attrs += ' opacity="0.55"'
                    out.append(
                        f'<text x="{x:.1f}" y="{y:.1f}" {attrs} xml:space="preserve" '
                        f'textLength="{width:.1f}" lengthAdjust="spacing">'
                        f'{html.escape(piece)}</text>')
                col += len(piece)
        y += LH
    out.append('</svg>')
    return "".join(out)

if __name__ == "__main__":
    src, dst, title = sys.argv[1], sys.argv[2], sys.argv[3]
    prompt = sys.argv[4] if len(sys.argv) > 4 else ""
    data = open(src, encoding="utf-8").read().replace("\r\n", "\n").rstrip("\n")
    if prompt:
        data = "\x1b[32m$\x1b[0m %s\n%s" % (prompt, data)
    open(dst, "w", encoding="utf-8").write(render(parse(data), title))
    print(f"{dst}: {len(open(dst,encoding='utf-8').read())} bytes")
