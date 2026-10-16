<!-- Generated from packages/ttfx/README.md.in by scripts/render.py. Edit the .in file, not this one. -->
# ttfx

ttfx, Omarchy's terminal text effects program, packaged for Oaxaca's repository (docs/6, choice 43). Omarchy v4.0.4 installs ttfx from its own repository and its screensaver (`oaxaca-launch-screensaver`, `oaxaca-screensaver`) runs it on the distro's logo; Ubuntu's archive has none. `oaxaca-desktop` depends on this package.

The package keeps the upstream name, as the policy says for third-party software we rebuild, with the version `0.5.0-0oaxaca1`. It is built from source: ttfx's release tarball, with the crates from its `Cargo.lock` vendored on the build host (`CARGO_VENDOR=1`) so cargo builds offline in the chroot, the path `hyprland-preview-share-picker` uses.

| Path | What |
|---|---|
| `upstream` | the release tarball's URL and SHA-256 (the one Omarchy's recipe records), `CARGO_VENDOR=1`, and `RELEASES=omacom/ttfx` for `make upstream-check` |
| `debian/rules` | writes the `.cargo/config.toml` that points cargo at `vendor/`, builds the release binary, installs it with its bash completion and README; skips the tests, which need a checkout of TerminalTextEffects |
| `debian/copyright` | ttfx's MIT licence and NOTICE credit, and the vendored crates grouped by licence |

A new ttfx release: `make upstream-check` reports it; update the version in the URL and the SHA-256 in `upstream` (Omarchy's `pkgbuilds/ttfx/PKGBUILD` records it), check the crates' licences against `debian/copyright`, add a changelog entry, then `make build PKG=packages/ttfx`.
