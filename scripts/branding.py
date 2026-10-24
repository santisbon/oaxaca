#!/usr/bin/env python3
"""Draw the distro's artwork and write it where the packages take it from (make branding).

Every piece is pixel art with 3-pixel strokes, so the 16-pixel glyph in the bar, the text art and
the 800-pixel installer image are the same pixels at different sizes (docs/6, choices 104 and 105).
As Omarchy does, a piece shows either the mark or the name, never both:

- the mark: a square spiral, the fret of the Zapotec stone mosaics at Mitla, Oaxaca, 24 by 24
  pixels, its outer corners cut by one pixel. It is the bar's menu button (the icon font's U+E900),
  the desktop's icon, fastfetch's logo and the installer's sidebar logo and window icon;
- the name: "oaxaca" in lowercase, 18 pixels tall, its outer corners cut by one pixel; the x is
  two stepped diagonals and the a carries a spur at its foot. It is the boot and login screens'
  logo, the screensaver's text art and the installer's welcome image;
- the colors: agave (the blue-green of espadin, the mezcal agave), on the dark background the
  boot, login and installer screens use.

The artwork is drawn for the name Oaxaca; a distro with another DISTRO_NAME needs its own letters.

Writes, all committed:
  packages/desktop/debian/extra/logo.svg         the name, /usr/share/<id>/logo.svg
  packages/desktop/debian/extra/splash-logo.png  the name, for the boot and login screens
  packages/desktop/debian/extra/icon.png         the mark on a dark rounded tile, the desktop's icon
  packages/desktop/debian/extra/logo.txt         the name as text art (the screensaver)
  packages/desktop/debian/extra/icon.txt         the mark as text art (fastfetch)
  packages/installer/calamares/branding/distro/{logo,icon,welcome}.png
                                                 the installer's sidebar logo, window icon, welcome image
and, not committed, build/branding/mark.svg: the mark alone, one color, one <path>, which the fork's
omarchy-dev-font takes for the icon font's U+E900.

PNGs are rasterized by ImageMagick with their metadata stripped, so a rerun writes the same bytes.
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

AGAVE = "#6CC6B4"   # the mark and the name
NIGHT = "#1a1b26"   # the background of the boot, login and installer screens

STROKE = 3          # pixels
LETTER_GAP = 3      # pixels between letters

# The mark on an 8 by 8 grid of cells; each cell is STROKE by STROKE pixels.
MARK_CELLS = [
    "########",
    "#......#",
    "#.####.#",
    "#.#..#.#",
    "#.#.##.#",
    "#.#....#",
    "#.######",
    "#.......",
]


def rep(row, n):
    return [row] * n


LETTERS = {
    "o": rep("#############", 3) + rep("###.......###", 12) + rep("#############", 3),
    "a": (rep("##########...", 3) + rep(".......###...", 3) + rep("##########...", 3)
          + rep("###....###...", 3) + rep("###....######", 3) + rep("#############", 3)),
    "x": (["###.......###", "###.......###", "####.....####", ".####...####.", "..####.####..",
           "...#######..."] + rep("....#####....", 6)
          + ["...#######...", "..####.####..", ".####...####.", "####.....####", "###.......###",
             "###.......###"]),
    "c": rep("############", 3) + rep("###.........", 12) + rep("############", 3),
}
CHAMFERED_LETTERS = "oac"   # the x's diagonals have no outer corners to cut


def grid(rows):
    return [[c == "#" for c in r] for r in rows]


def chamfer(g, run=4):
    """Cut the pixel at each outer corner whose two sides are at least run pixels long."""
    h, w = len(g), len(g[0])

    def on(x, y):
        return 0 <= y < h and 0 <= x < w and g[y][x]

    out = [r[:] for r in g]
    for y in range(h):
        for x in range(w):
            if not g[y][x]:
                continue
            for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
                if (not on(x + dx, y) and not on(x, y + dy)
                        and all(on(x, y - dy * i) for i in range(1, run))
                        and all(on(x - dx * i, y) for i in range(1, run))):
                    out[y][x] = False
    return out


def mark_pixels():
    return chamfer(grid(["".join(c * STROKE for c in r) for r in MARK_CELLS for _ in range(STROKE)]))


def word_pixels(text):
    letters = [chamfer(grid(LETTERS[c])) if c in CHAMFERED_LETTERS else grid(LETTERS[c]) for c in text]
    rows = []
    for y in range(len(letters[0])):
        row = []
        for i, letter in enumerate(letters):
            row += ([False] * LETTER_GAP if i else []) + letter[y]
        rows.append(row)
    return rows


MARK = mark_pixels()
WORD = word_pixels("oaxaca")


def path_d(pixels, scale, dx, dy):
    """One subpath per horizontal run of pixels."""
    d = []
    for y, row in enumerate(pixels):
        x = 0
        while x < len(row):
            if not row[x]:
                x += 1
                continue
            x0 = x
            while x < len(row) and row[x]:
                x += 1
            d.append(f"M{dx + x0 * scale},{dy + y * scale}h{(x - x0) * scale}v{scale}h{-(x - x0) * scale}z")
    return "".join(d)


def svg(paths, width, height, background=None, radius=0):
    bg = f'<rect width="{width}" height="{height}" rx="{radius}" fill="{background}"/>' if background else ""
    body = "".join(f'<path fill="{color}" d="{d}"/>' for color, d in paths if d)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
            f'viewBox="0 0 {width} {height}">{bg}{body}</svg>\n')


def mark_svg(scale, size, color=AGAVE, background=None, radius=0):
    offset = (size - len(MARK[0]) * scale) // 2
    return svg([(color, path_d(MARK, scale, offset, offset))], size, size, background, radius)


def name_svg(scale, pad, width=None, height=None, background=None):
    natural_w, natural_h = len(WORD[0]) * scale, len(WORD) * scale
    width = width or natural_w + 2 * pad
    height = height or natural_h + 2 * pad
    dx, dy = (width - natural_w) // 2, (height - natural_h) // 2
    return svg([(AGAVE, path_d(WORD, scale, dx, dy))], width, height, background)


def text_art_full(pixels):
    """Two columns per pixel: a terminal cell is about twice as tall as wide, so the pixels are square."""
    return "\n".join("".join("██" if p else "  " for p in row).rstrip() for row in pixels) + "\n"


def text_art_half(pixels):
    """One column and half a line per pixel, with the half-block characters."""
    lines = []
    for y in range(0, len(pixels), 2):
        top, bottom = pixels[y], pixels[y + 1] if y + 1 < len(pixels) else [False] * len(pixels[y])
        lines.append("".join(" ▀▄█"[t + 2 * b] for t, b in zip(top, bottom)).rstrip())
    return "\n".join(lines) + "\n"


def png(svg_text, out):
    # The SVGs are drawn at their pixel size, so 96 dpi rasterizes them 1:1.
    with tempfile.NamedTemporaryFile("w", suffix=".svg") as f:
        f.write(svg_text)
        f.flush()
        subprocess.run(["magick", "-background", "none", "-density", "96", f.name, "-strip",
                        "-define", "png:exclude-chunks=date,time", f"PNG32:{out}"], check=True)


def main():
    extra = ROOT / "packages/desktop/debian/extra"
    installer = ROOT / "packages/installer/calamares/branding/distro"
    build = ROOT / "build/branding"
    build.mkdir(parents=True, exist_ok=True)

    (extra / "logo.svg").write_text(name_svg(scale=4, pad=8))
    png(name_svg(scale=6, pad=0), extra / "splash-logo.png")
    png(mark_svg(scale=8, size=256, background=NIGHT, radius=48), extra / "icon.png")
    (extra / "logo.txt").write_text(text_art_half(WORD))
    (extra / "icon.txt").write_text(text_art_full(MARK))

    png(mark_svg(scale=8, size=256), installer / "logo.png")
    png(mark_svg(scale=2, size=64, background=NIGHT, radius=12), installer / "icon.png")
    png(name_svg(scale=6, pad=0, width=800, height=450, background=NIGHT), installer / "welcome.png")

    (build / "mark.svg").write_text(mark_svg(scale=40, size=960, color="#000000"))
    for path in sorted([extra / "logo.svg", extra / "splash-logo.png", extra / "icon.png",
                        extra / "logo.txt", extra / "icon.txt", installer / "logo.png",
                        installer / "icon.png", installer / "welcome.png", build / "mark.svg"]):
        print(f"wrote {path.relative_to(ROOT)}")


if __name__ == "__main__":
    sys.exit(main())
