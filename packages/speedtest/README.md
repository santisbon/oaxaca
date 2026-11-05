<!-- Generated from packages/speedtest/README.md.in by scripts/render.py. Edit the .in file, not this one. -->
# oaxaca-speedtest

omarchy-speedtest, the client Omarchy v4.5.0's speed test panel runs, packaged for Oaxaca's repository. It measures against `speed.omarchy.org`, a service Omarchy runs, chosen by the distro's maintainer (docs/6, choice 126).

| Path | What |
|---|---|
| `upstream` | the tag tarball's URL and SHA-256 (the one Omarchy's recipe records), and `RELEASES=omacom/omarchy-speedtest` for `make upstream-check` |
| `debian/rules` | builds the client with Go and installs it at `/usr/lib/oaxaca/speedtest`, the path the desktop's renamed `omarchy-network-speedtest` runs |
