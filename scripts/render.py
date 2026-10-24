#!/usr/bin/env python3
"""Render every *.in file in the repo from distro.conf.

Anatomy: distro.conf holds the identity. This script reads it through bash (so quoting and
${VAR} references work), adds derived values, and replaces @KEY@ tokens in each *.in file,
writing the result next to it without the .in suffix. Write @@NAME@@ to get the literal
text @NAME@ in the output. Rendered files are committed; `make check-render` proves they
still match distro.conf.

Usage: scripts/render.py [--quiet]
"""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SKIP_DIRS = {".git", "build", ".cache"}
# File names whose format has no comment syntax, so they get no "generated" header, and
# suffixes of files whose content is shown as is (text art, SVG artwork).
NO_HEADER = {"changelog", "copyright", "format"}
NO_HEADER_SUFFIXES = {".txt", ".svg"}
# @NAME@ is substituted; @@NAME@@ is an escape that renders as the literal text @NAME@.
TOKEN = re.compile(r"@@([A-Z][A-Z0-9_]*)@@|@([A-Z][A-Z0-9_]*)@")


def load_conf():
    conf_path = ROOT / "distro.conf"
    keys = re.findall(r"^([A-Z][A-Z0-9_]*)=", conf_path.read_text(), flags=re.M)
    script = f"set -a; source '{conf_path}'; " + "; ".join(f'printf "%s\\0" "${k}"' for k in keys)
    values = subprocess.check_output(["bash", "-c", script]).decode().split("\0")
    conf = dict(zip(keys, values))
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]+", conf["DISTRO_ID"]):
        sys.exit(f"DISTRO_ID={conf['DISTRO_ID']!r} must be lowercase letters, digits and hyphens")
    conf["DISTRO_ID_UPPER"] = conf["DISTRO_ID"].upper().replace("-", "_")
    # Each package's version, from the top line of packages/<dir>/debian/changelog.in, as
    # VERSION_<DIR> (the directory's name in capitals, "-" as "_"), so the developer README's
    # table follows every version bump at the next render. Tokens in that line (the desktop's
    # version) are filled from distro.conf first.
    for changelog in sorted((ROOT / "packages").glob("*/debian/changelog.in")):
        m = re.match(r"\S+ \(([^)]*)\)", changelog.read_text())
        if m:
            key = "VERSION_" + changelog.parent.parent.name.upper().replace("-", "_")
            conf[key] = TOKEN.sub(lambda t: f"@{t.group(1)}@" if t.group(1) else conf[t.group(2)], m.group(1))
    return conf


def render(src: pathlib.Path, conf: dict) -> str:
    text = src.read_text()
    missing = sorted({m[1] for m in TOKEN.findall(text) if m[1] and m[1] not in conf})
    if missing:
        sys.exit(f"{src.relative_to(ROOT)}: unknown token(s) {', '.join(missing)}; add them to distro.conf")
    out = TOKEN.sub(lambda m: f"@{m.group(1)}@" if m.group(1) else conf[m.group(2)], text)
    if src.stem not in NO_HEADER and src.with_suffix("").name not in NO_HEADER and src.with_suffix("").suffix not in NO_HEADER_SUFFIXES:
        note = f"Generated from {src.relative_to(ROOT)} by scripts/render.py. Edit the .in file, not this one."
        suffix = src.with_suffix("").suffix
        # Comment syntax of the rendered file: Markdown, Lua, QML, troff (man pages, suffix .1 to
        # .9), or "#" for everything else.
        if suffix == ".md":
            header = f"<!-- {note} -->\n"
        elif suffix == ".lua":
            header = f"-- {note}\n"
        elif suffix == ".qml":
            header = f"// {note}\n"
        elif re.fullmatch(r"\.[1-9]", suffix):
            header = f'.\\" {note}\n'
        else:
            header = f"# {note}\n"
        if out.startswith("#!"):
            first, rest = out.split("\n", 1)
            out = f"{first}\n{header}{rest}"
        else:
            out = header + out
    return out


def main():
    quiet = "--quiet" in sys.argv
    conf = load_conf()
    changed = 0
    for src in sorted(ROOT.rglob("*.in")):
        if SKIP_DIRS & set(src.relative_to(ROOT).parts):
            continue
        dst = src.with_suffix("")
        out = render(src, conf)
        if not dst.exists() or dst.read_text() != out:
            dst.write_text(out)
            changed += 1
            if not quiet:
                print(f"rendered {dst.relative_to(ROOT)}")
        dst.chmod(src.stat().st_mode & 0o7777)
    if not quiet:
        print(f"{changed} file(s) changed; DISTRO_ID={conf['DISTRO_ID']} DISTRO_NAME={conf['DISTRO_NAME']}")


if __name__ == "__main__":
    main()
