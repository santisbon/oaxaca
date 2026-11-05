<!-- Generated from packages/gliff/README.md.in by scripts/render.py. Edit the .in file, not this one. -->
# gliff

Gliff, the Hyprland remote desktop over SSH that Omarchy v4.5.0 preinstalls, packaged for Oaxaca's repository. It is built from source, with its crates vendored at build time.

| Path | What |
|---|---|
| `upstream` | the tag tarball's URL and SHA-256 (the one Omarchy's recipe records), `CARGO_VENDOR=1`, and `RELEASES=omacom/gliff` for `make upstream-check` |
| `debian/rules` | writes the `.cargo/config.toml` that points cargo at `vendor/`, builds the release binaries, and installs them with the launcher, icon and documents |
