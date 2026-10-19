#!/usr/bin/env python3
"""Write the live layer of the ISO: the live root filesystem minus the installed one, as a tar.

Anatomy: the ISO carries two squashfs layers (docs/7, choice 55). The lower one,
casper/filesystem.squashfs, is the desktop profile's tarball, the system the installer copies
onto the disk. The upper one, casper/filesystem.live.squashfs, holds only what the live profile's
tarball has on top: casper mounts both and stacks them with overlayfs, so the live session sees
exactly the live tarball. This script reads both tarballs and writes the upper layer's tar to
standard output, which scripts/iso-create.sh pipes into mksquashfs -tar.

An entry of the live tarball goes into the layer when the desktop tarball has no entry of that
name, or one that differs in type, mode, owner, link target, device numbers, extended attributes
or, for a regular file, content (compared by SHA-256 when the sizes match). Modification times
are not compared: the two tarballs come from separate mmdebstrap runs, where an unchanged file
can carry another time. A name the desktop tarball has and the live one does not becomes an
overlayfs whiteout, a character device 0/0, which hides the lower entry (only the topmost such
name; its children go with it). Two further rules keep the stacked view equal to the live
tarball:
  - every directory above an entry in the layer is in the layer too, with the live tarball's
    owner and mode, because the uppermost layer holding a directory sets its attributes, and
    mksquashfs would otherwise invent the missing parents with its own defaults;
  - hard links travel as a group: when one name of a hard-linked file is in the layer, all of its
    names are, so that no name keeps pointing at the lower layer's copy of the file.

Usage: scripts/layer-diff.py <desktop.tar> <live.tar> > layer.tar
"""
import hashlib
import sys
import tarfile


def norm(name):
    name = name[2:] if name.startswith("./") else name
    return name.rstrip("/")


def xattrs(member):
    return {k: v for k, v in member.pax_headers.items() if k.startswith("SCHILY.xattr.")}


def digest(tar, member):
    h = hashlib.sha256()
    f = tar.extractfile(member)
    for block in iter(lambda: f.read(1 << 20), b""):
        h.update(block)
    return h.digest()


def same(live_tar, m, lower_tar, l):
    if l is None:
        return False
    if (m.type, m.mode, m.uid, m.gid, m.linkname, m.devmajor, m.devminor) != (
        l.type, l.mode, l.uid, l.gid, l.linkname, l.devmajor, l.devminor
    ):
        return False
    if xattrs(m) != xattrs(l):
        return False
    if m.isreg():
        return m.size == l.size and digest(live_tar, m) == digest(lower_tar, l)
    return True


def parents(name):
    parts = name.split("/")
    return ["/".join(parts[:i]) for i in range(1, len(parts))]


def main():
    lower_path, live_path = sys.argv[1:3]
    lower_tar = tarfile.open(lower_path)
    lower = {norm(m.name): m for m in lower_tar}
    live_tar = tarfile.open(live_path)
    members = [m for m in live_tar if norm(m.name)]
    live = {norm(m.name): m for m in members}

    layer = {n for n, m in live.items() if not same(live_tar, m, lower_tar, lower.get(n))}

    # Hard link groups: tar stores the first name as the file and the others as links to it.
    groups = {}
    for n, m in live.items():
        if m.islnk():
            groups.setdefault(norm(m.linkname), set()).add(n)
    for target, links in groups.items():
        if target in layer or links & layer:
            layer |= links | {target}

    gone = [n for n in lower if n and n not in live]
    gone_set = set(gone)
    whiteouts = sorted(n for n in gone if not any(p in gone_set for p in parents(n)))

    for n in list(layer) + whiteouts:
        layer.update(p for p in parents(n) if p in live)

    out = tarfile.open(fileobj=sys.stdout.buffer, mode="w|", format=tarfile.PAX_FORMAT)
    for m in members:
        if norm(m.name) not in layer:
            continue
        out.addfile(m, live_tar.extractfile(m) if m.isreg() else None)
    for n in whiteouts:
        w = tarfile.TarInfo("./" + n)
        w.type, w.mode, w.devmajor, w.devminor = tarfile.CHRTYPE, 0, 0, 0
        out.addfile(w)
    out.close()
    print(f"layer-diff: {len(layer)} entries, {len(whiteouts)} whiteouts", file=sys.stderr)


if __name__ == "__main__":
    main()
