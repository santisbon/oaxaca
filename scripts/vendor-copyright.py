#!/usr/bin/env python3
"""vendor-copyright.py: the debian/copyright paragraphs for a vendored Rust crate tree.

Anatomy: a package built with CARGO_VENDOR=1 (scripts/build.sh) ships the crates of its
Cargo.lock as the component vendor/, and Debian's copyright file has to cover each of them.
This script reads the license field of every vendor/<crate>/Cargo.toml (Cargo's SPDX
expression, or license-file), writes one "Files:" paragraph per license expression with the
crates that carry it, then one standalone "License:" paragraph for every license name used, its
text taken from scripts/licenses/<name>. A name with no file there stops the script: add the
text and run it again. SPDX names are mapped to the names Debian's copyright format uses
("GPL-3.0-only" is "GPL-3", "LGPL-2.1-or-later" is "LGPL-2.1+", "Apache-2.0 WITH
LLVM-exception" is "Apache-2.0-with-LLVM-exception").

Usage: scripts/vendor-copyright.py <vendor dir> > paragraphs.txt
       (run "cargo vendor --locked vendor" in the unpacked upstream tree first, as build.sh does;
       paste the output after the package's own Files: paragraphs)
"""
import pathlib
import re
import sys
import tomllib

LICENSES = pathlib.Path(__file__).resolve().parent / "licenses"
DEBIAN_NAMES = {
    "GPL-3.0-only": "GPL-3",
    "LGPL-2.1-or-later": "LGPL-2.1+",
}
# A crate whose Cargo.toml names a licence file instead of an SPDX expression, by crate.
LICENSE_FILES = {
    "cargo-husky": "MIT",  # LICENSE.txt is the MIT licence (read 2026-10-16)
}


def debian_expression(spdx: str) -> str:
    spdx = spdx.replace("/", " OR ")
    spdx = re.sub(r"Apache-2\.0\s+WITH\s+LLVM-exception", "Apache-2.0-with-LLVM-exception", spdx)
    spdx = re.sub(r"\s+", " ", spdx).strip()
    for spdx_name, debian_name in DEBIAN_NAMES.items():
        spdx = re.sub(rf"\b{re.escape(spdx_name)}\b", debian_name, spdx)
    return spdx.replace(" OR ", " or ").replace(" AND ", " and ")


def main() -> int:
    vendor = pathlib.Path(sys.argv[1])
    groups: dict[str, list[str]] = {}
    for manifest in sorted(vendor.glob("*/Cargo.toml")):
        crate = manifest.parent.name
        package = tomllib.loads(manifest.read_text()).get("package", {})
        license_field = package.get("license")
        if not isinstance(license_field, str):
            name = re.sub(r"-[0-9][0-9.]*$", "", crate)
            if name not in LICENSE_FILES:
                print(f"{crate}: no SPDX license field; add it to LICENSE_FILES", file=sys.stderr)
                return 1
            license_field = LICENSE_FILES[name]
        groups.setdefault(debian_expression(license_field), []).append(crate)

    names: set[str] = set()
    for expression in sorted(groups, key=lambda e: (-len(groups[e]), e)):
        crates = groups[expression]
        print("Files: " + "\n ".join(f"vendor/{crate}/*" for crate in crates))
        print("Copyright: the authors of the crates named above (Cargo.toml of each crate)")
        print(f"License: {expression}")
        print()
        names.update(n for n in re.split(r"[\s()]+|\bor\b|\band\b", expression) if n and n not in ("or", "and"))

    missing = [n for n in sorted(names) if not (LICENSES / n).is_file()]
    if missing:
        print(f"no text in {LICENSES} for: {' '.join(missing)}", file=sys.stderr)
        return 1
    for name in sorted(names):
        print(f"License: {name}")
        print((LICENSES / name).read_text().rstrip("\n"))
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
