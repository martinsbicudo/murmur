#!/usr/bin/env python3
"""Generates every Murmur mark from code so the brand can be tweaked and rebuilt.

The mark: a speech bubble whose voice waveform settles into lines of text.
Usage: python3 brand/generate.py   (writes into brand/svg/)
"""
from pathlib import Path

OUT = Path(__file__).resolve().parent / "svg"

GRAPHITE = "#16181D"
SKY = "#86D3FF"
POOL = "#34D9B8"
GRADIENT = "url(#murmur-gradient)"
CREAM = "#F4EFE6"
SLATE = "#5B6170"


def pill(cx, cy, w, h):
    r = w / 2
    top, bottom = cy - h / 2, cy + h / 2
    return (
        f"M{cx - r:g},{top + r:g}A{r:g},{r:g} 0 0 1 {cx + r:g},{top + r:g}"
        f"V{bottom - r:g}A{r:g},{r:g} 0 0 1 {cx - r:g},{bottom - r:g}Z"
    )


def hline(x0, x1, cy, h):
    r = h / 2
    return (
        f"M{x0:g},{cy - r:g}H{x1:g}A{r:g},{r:g} 0 0 1 {x1:g},{cy + r:g}"
        f"H{x0:g}A{r:g},{r:g} 0 0 1 {x0:g},{cy - r:g}Z"
    )


def bubble(x0, y0, x1, y1, r, tail_from, tail_tip, tail_to):
    return (
        f"M{x0 + r:g},{y0:g}H{x1 - r:g}A{r:g},{r:g} 0 0 1 {x1:g},{y0 + r:g}"
        f"V{y1 - r:g}A{r:g},{r:g} 0 0 1 {x1 - r:g},{y1:g}"
        f"H{tail_from:g}L{tail_tip[0]:g},{tail_tip[1]:g}L{tail_to:g},{y1:g}"
        f"H{x0 + r:g}A{r:g},{r:g} 0 0 1 {x0:g},{y1 - r:g}"
        f"V{y0 + r:g}A{r:g},{r:g} 0 0 1 {x0 + r:g},{y0:g}Z"
    )


def mark():
    shell = bubble(24, 34, 232, 186, 46, 116, (65.28, 226), 76)
    wave = pill(60, 110, 20, 52) + pill(94, 110, 20, 100) + pill(128, 110, 20, 64)
    text = hline(160, 196, 92, 20) + hline(160, 174, 128, 20)
    return shell, wave + text


def menubar_mark():
    shell = bubble(1, 1, 21, 13.5, 4.2, 9.5, (4.66, 17), 5.6)
    wave = pill(5.6, 7.25, 1.9, 4.6) + pill(8.7, 7.25, 1.9, 8) + pill(11.8, 7.25, 1.9, 5.4)
    text = hline(15, 16.9, 5.6, 1.9) + hline(15, 15.6, 8.9, 1.9)
    return shell + wave + text


def gradient_defs():
    return (
        '<defs><linearGradient id="murmur-gradient" x1="0" y1="0" x2="1" y2="1">'
        f'<stop offset="0" stop-color="{SKY}"/><stop offset="1" stop-color="{POOL}"/>'
        "</linearGradient></defs>"
    )


def svg(body, view="0 0 256 256", title="Murmur"):
    defs = gradient_defs() if GRADIENT in body else ""
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view}">'
        f"<title>{title}</title>{defs}{body}</svg>\n"
    )


def path(d, fill, evenodd=False):
    rule = ' fill-rule="evenodd"' if evenodd else ""
    return f'<path d="{d}" fill="{fill}"{rule}/>'


def symbol(fill):
    shell, inner = mark()
    return svg(path(shell + inner, fill, evenodd=True))


def symbol_two_tone(shell_fill, inner_fill):
    shell, inner = mark()
    return svg(path(shell, shell_fill) + path(inner, inner_fill))


def app_icon(small=False):
    shell, inner = mark()
    scale = 2.5 if small else 2.35
    body = (
        f'<rect x="100" y="100" width="824" height="824" rx="185" fill="{GRAPHITE}"/>'
        f'<g transform="translate(512 524) scale({scale}) translate(-128 -130)">'
        + path(shell + inner, GRADIENT, evenodd=True)
        + "</g>"
    )
    return svg(body, view="0 0 1024 1024", title="Murmur app icon")


def menubar(fill):
    return svg(path(menubar_mark(), fill, evenodd=True), view="0 0 22 18", title="Murmur menu bar")


def wordmark_text(fill):
    return (
        '<text x="0" y="0" font-family="Inter, SF Pro Display, -apple-system, Helvetica Neue, sans-serif" '
        f'font-weight="650" font-size="120" letter-spacing="-3" fill="{fill}">murmur</text>'
    )


def lockup(mark_fill, text_fill):
    shell, inner = mark()
    body = (
        path(shell + inner, mark_fill, evenodd=True)
        + f'<g transform="translate(276 162)">{wordmark_text(text_fill)}</g>'
    )
    return svg(body, view="0 0 750 256", title="Murmur lockup")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    files = {
        "murmur-symbol.svg": symbol(GRAPHITE),
        "murmur-symbol-gradient.svg": symbol(GRADIENT),
        "murmur-symbol-black.svg": symbol("#000"),
        "murmur-symbol-white.svg": symbol("#FFF"),
        "murmur-symbol-two-tone.svg": symbol_two_tone(GRADIENT, GRAPHITE),
        "murmur-app-icon.svg": app_icon(),
        "murmur-app-icon-small.svg": app_icon(small=True),
        "menubar-idle.svg": menubar("#000"),
        "menubar-recording.svg": menubar(GRADIENT),
        "murmur-lockup.svg": lockup(GRAPHITE, GRAPHITE),
        "murmur-lockup-gradient.svg": lockup(GRADIENT, GRAPHITE),
        "murmur-lockup-reversed.svg": lockup(GRADIENT, CREAM),
    }
    for name, content in files.items():
        (OUT / name).write_text(content)
    print(f"wrote {len(files)} files to {OUT}")


if __name__ == "__main__":
    main()
