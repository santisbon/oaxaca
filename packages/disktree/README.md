<!-- Generated from packages/disktree/README.md.in by scripts/render.py. Edit the .in file, not this one. -->
# disktree

Disktree, the graphical disk usage tool Omarchy v4.5.0 preinstalls, packaged for Oaxaca's repository from the project's own release build, as Omarchy's recipe does.

| Path | What |
|---|---|
| `upstream` | the release tarball's URL and SHA-256, and `RELEASES=tobi/disktree` for `make upstream-check` |
| `debian/rules` | installs the binary, the launcher, the icon and the README |
| `debian/control` | names `libwayland-client0`, `libegl1` and `libvulkan1`, which the binary opens at run time and `dh_shlibdeps` cannot see |
