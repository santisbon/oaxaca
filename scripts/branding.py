#!/usr/bin/env python3
"""Draw the distro's artwork and write it where the packages take it from (make branding).

Every piece comes from one grid of square cells, so the 16-pixel glyph in the bar, the text art and
the 800-pixel installer image are the same drawing at different sizes (docs/6, choice 104):

- the mark: a xicalcoliuhqui, the stepped fret of the Zapotec stone mosaics at Mitla, Oaxaca; a
  solid staircase rising into a square spiral hook, 8 by 8 cells;
- the wordmark: "oaxaca" in lowercase on the same grid, 8 cells tall with 1-cell strokes; the x is
  built from steps and the a carries a spur, as the mark carries its hook;
- the colors: grana (cochineal red) for the mark, cal (lime-wash white) for the word, on the dark
  background the boot, login and installer screens use.

The artwork is drawn for the name Oaxaca; a distro with another DISTRO_NAME needs its own letters.

Writes, all committed:
  packages/desktop/debian/extra/logo.svg         the lockup (mark and word), /usr/share/<id>/logo.svg
  packages/desktop/debian/extra/splash-logo.png  the lockup for the boot and login screens
  packages/desktop/debian/extra/icon.png         the mark on a dark rounded tile, the desktop's icon
  packages/desktop/debian/extra/logo.txt         the lockup as text art (the screensaver)
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

GRANA = "#E25A6E"   # cochineal red, lifted for contrast on the dark background
CAL = "#ECE6DA"     # lime-wash white
BARRO = "#1a1b26"   # the background of the boot, login and installer screens

MARK = [
    "...#####",
    "...#...#",
    "...#.#.#",
    "...#.###",
    "..##....",
    ".###....",
    "####....",
    "########",
]
LETTERS = {
    "o": ["######", "#....#", "#....#", "#....#", "#....#", "#....#", "#....#", "######"],
    "a": ["#####.", "....#.", "....#.", "#####.", "#...#.", "#...#.", "#...##", "######"],
    "x": ["#....#", "##..##", ".#..#.", "..##..", "..##..", ".#..#.", "##..##", "#....#"],
    "c": ["######", "#.....", "#.....", "#.....", "#.....", "#.....", "#.....", "######"],
}
LETTER_GAP = 2   # cells between letters
MARK_GAP = 4     # cells between the mark and the word


def word(text):
    rows = [""] * len(MARK)
    for i, ch in enumerate(text):
        for r in range(len(MARK)):
            rows[r] += ("." * LETTER_GAP if i else "") + LETTERS[ch][r]
    return rows


WORD = word("oaxaca")


def path_d(rows, cell, dx, dy):
    """One subpath per horizontal run of filled cells."""
    d = []
    for y, row in enumerate(rows):
        x = 0
        while x < len(row):
            if row[x] != "#":
                x += 1
                continue
            x0 = x
            while x < len(row) and row[x] == "#":
                x += 1
            d.append(f"M{dx + x0 * cell},{dy + y * cell}h{(x - x0) * cell}v{cell}h{-(x - x0) * cell}z")
    return "".join(d)


def svg(paths, width, height, background=None, radius=0):
    bg = f'<rect width="{width}" height="{height}" rx="{radius}" fill="{background}"/>' if background else ""
    body = "".join(f'<path fill="{color}" d="{d}"/>' for color, d in paths)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
            f'viewBox="0 0 {width} {height}">{bg}{body}</svg>\n')


def mark_svg(cell, size, color=GRANA, background=None, radius=0):
    offset = (size - len(MARK[0]) * cell) // 2
    return svg([(color, path_d(MARK, cell, offset, offset))], size, size, background, radius)


def lockup_svg(cell, pad, width=None, height=None, background=None):
    mark_w = len(MARK[0])
    natural_w = (mark_w + MARK_GAP + len(WORD[0])) * cell
    natural_h = len(MARK) * cell
    width = width or natural_w + 2 * pad
    height = height or natural_h + 2 * pad
    dx, dy = (width - natural_w) // 2, (height - natural_h) // 2
    return svg([(GRANA, path_d(MARK, cell, dx, dy)),
                (CAL, path_d(WORD, cell, dx + (mark_w + MARK_GAP) * cell, dy))],
               width, height, background)


def text_art(rows, cols_per_cell, lines_per_cell):
    """A terminal cell is about twice as tall as wide, so 2 columns by 1 line draws a square."""
    lines = []
    for row in rows:
        line = "".join(("█" if c == "#" else " ") * cols_per_cell for c in row).rstrip()
        lines += [line] * lines_per_cell
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

    (extra / "logo.svg").write_text(lockup_svg(cell=8, pad=8))
    png(lockup_svg(cell=12, pad=0), extra / "splash-logo.png")
    png(mark_svg(cell=22, size=256, background=BARRO, radius=48), extra / "icon.png")
    (extra / "logo.txt").write_text(text_art([m + "." * MARK_GAP + w for m, w in zip(MARK, WORD)], 2, 1))
    (extra / "icon.txt").write_text(text_art(MARK, 4, 2))

    png(mark_svg(cell=24, size=256), installer / "logo.png")
    png(mark_svg(cell=6, size=64, background=BARRO, radius=12), installer / "icon.png")
    png(lockup_svg(cell=10, pad=0, width=800, height=450, background=BARRO), installer / "welcome.png")

    (build / "mark.svg").write_text(mark_svg(cell=120, size=960, color="#000000"))
    for path in sorted([extra / "logo.svg", extra / "splash-logo.png", extra / "icon.png",
                        extra / "logo.txt", extra / "icon.txt", installer / "logo.png",
                        installer / "icon.png", installer / "welcome.png", build / "mark.svg"]):
        print(f"wrote {path.relative_to(ROOT)}")


if __name__ == "__main__":
    sys.exit(main())
