<!-- Generated from packages/fonts/README.md.in by scripts/render.py. Edit the .in file, not this one. -->
# oaxaca-fonts

The two font families the Oaxaca desktop asks for by name and Ubuntu's archive does not carry: roadmap step 6. The desktop shell, the terminal and the editor configuration ported from Omarchy name "JetBrainsMono Nerd Font" (JetBrains Mono patched with icon glyphs by the Nerd Fonts project; the icons in the shell's bar and menus come from that font), and Omarchy's font list names the iA Writer typefaces (Mono S, Quattro S, Duo S and Duospace, derived from IBM Plex) for documents and notes. Ubuntu's archive has `fonts-jetbrains-mono` (no icon glyphs) and no iA Writer fonts, so this package ships the same 20 TTF files Omarchy's two recipes install (`omacom/omarchy-pkgs`, `pkgbuilds/ttf-jetbrains-mono-nerd-basic/PKGBUILD` and `pkgbuilds/ttf-ia-writer/PKGBUILD`, read on 2026-10-10).

The package name follows the policy's row for packages we own (`oaxaca-fonts`), and the version `3.5.1+ia20261002-0oaxaca1` follows the row for third-party software we package from source: the upstream part names the Nerd Fonts release (3.5.1) and the date of the iA-Fonts commit the iA Writer files come from (2026-10-02), and `-0oaxaca1` marks a package never in Debian.

| Installed path | What |
|---|---|
| `/usr/share/fonts/truetype/oaxaca/JetBrainsMonoNerdFont-{Regular,Bold,Italic,BoldItalic}.ttf` | the four "basic" faces of JetBrains Mono Nerd Font, Nerd Fonts 3.5.1 (JetBrains Mono 2.304 underneath) |
| `/usr/share/fonts/truetype/oaxaca/iAWriterMonoS-{Regular,Bold,Italic,BoldItalic}.ttf` | iA Writer Mono S |
| `/usr/share/fonts/truetype/oaxaca/iAWriterQuattroS-{Regular,Bold,Italic,BoldItalic}.ttf` | iA Writer Quattro S |
| `/usr/share/fonts/truetype/oaxaca/iAWriterDuoS-{Regular,Bold,Italic,BoldItalic}.ttf` | iA Writer Duo S |
| `/usr/share/fonts/truetype/oaxaca/iAWriterDuospace-{Regular,Bold,Italic,BoldItalic}.ttf` | iA Writer Duospace |
| `/usr/share/doc/oaxaca-fonts/copyright` | both SIL Open Font License texts in full, with the copyright holders and Reserved Font Names of each family |

Debian puts a package's TrueType fonts under `/usr/share/fonts/truetype/<package>/`; fontconfig's own file trigger on `/usr/share/fonts` rebuilds the font cache when dpkg unpacks the files, so this package ships no fontconfig snippet and no maintainer script.

Where the files come from, and how the build fetches them:

| File in this directory | What |
|---|---|
| `upstream` | `FILES=sources.list`: tells `scripts/build.sh` to assemble the orig tarball from a list of files instead of downloading one tarball |
| `sources.list` | one `<url> <sha256>` line per file: the Nerd Fonts 3.5.1 release zip `JetBrainsMono.zip` (its SHA-256 is the one Omarchy's recipe records, and matched the download on 2026-10-10) and the 16 iA Writer TTFs from `iaolo/iA-Fonts` (Mono, Quattro and Duo at commit `c6588670`, the commit Omarchy pins; Duospace at commit `b337fe1a`, the last commit carrying that family, which upstream removed later). The iA SHA-256s were computed from downloads whose SHA-512s match Omarchy's recipe |
| `debian/rules` | unzips the four faces out of `JetBrainsMono.zip` at build time (so `unzip` is a build dependency) and installs them with the iA Writer TTFs |

`make build PKG=packages/fonts` downloads the 17 files into `build/oaxaca-fonts-3.5.1+ia20261002-files/`, checks each SHA-256, packs them by basename into `build/oaxaca-fonts_3.5.1+ia20261002.orig.tar.gz`, and builds from that tarball plus `debian/`. Like `packages/quickshell`, this directory holds no font files itself.

Licenses: the JetBrains Mono Nerd Font files are under the SIL Open Font License 1.1 with no Reserved Font Name (the zip's `OFL.txt`; Nerd Fonts labels that license "OFL-1.1-no-RFN"), and the iA Writer files are under the SIL Open Font License 1.1 with the Reserved Font Names "iA Writer" (Information Architects Inc., 2018) and "Plex" (IBM Corp., 2017). The `iaolo/iA-Fonts` README adds guidelines beyond the license, read on 2026-10-10: credit iA Writer when using the fonts outside text editors, and do not bundle them with a text editor or make them a text editor's default typeface. Oaxaca ships them as desktop fonts, as Omarchy does.
