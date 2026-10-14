<!-- Generated from packages/calamares/README.md.in by scripts/render.py. Edit the .in file, not this one. -->
# calamares

Calamares 3.3.14, the installer framework `oaxaca-installer` configures, rebuilt for Oaxaca from Ubuntu's `calamares 3.3.14-0ubuntu30` (universe) with two patches, because the installer crashed on the Legion laptop on 2026-10-12 and again on 2026-10-13 (`docs/7 - image-installer.md`, choices 26 and 42).

The first patch, `debian/patches/replace-read-selection-before-revert.patch`: in "Replace a partition", choosing a partition (or free space) and then confirming the encryption passphrase makes Calamares redo the replacement on a worker thread, which reverts the device first and then read the chosen partition through the preview view's model index. Reverting the device makes the page rebuild that view, so the index dangled and Calamares crashed. The patch reads the partition's path, free-space flag, sectors and extended parent on the GUI thread before the worker starts. Choosing encryption first never hit the path, because nothing had changed the device yet. Upstream has the same family open as issue 2535.

The second patch, `debian/patches/revert-device-on-gui-thread.patch`, fixes the crash the first one left: the worker thread's revert itself. Reverting rescans the device, deletes the old device object and resets the models the "Before" and "After" bars paint from, and doing that on a worker thread raced the GUI thread's painting. On the laptop, choosing the free space and then confirming the passphrase still crashed with the first patch; in QEMU, confirming the passphrase again and again after choosing the space crashed on the third round with a segfault in `PartitionModel::data()`. The patch runs every revert on the partition page (device choice, Erase, Replace, Alongside, Manual) and the Replace layout on the GUI thread, so the page pauses briefly instead of showing its scanning dialog.

The package keeps Ubuntu's source and binary names and the version `3.3.14-0ubuntu30oaxaca2` (the policy's row for third-party software rebuilt from an Ubuntu source package). The live profile takes `calamares`, `calamares-data`, `libcalamares3.3` and `libcalamaresui3.3`, which depend on each other at the exact version; the installer's package removal takes them off the installed system.

| Path | What |
|---|---|
| `upstream` | the URL and SHA-256 of Ubuntu's `.dsc`; `scripts/build.sh` downloads the source package into `build/dsc/calamares/`, unpacks it, and lays this `debian/` over Ubuntu's |
| `debian/changelog.in` | our entries, put on top of Ubuntu's changelog at build time |
| `debian/patches/series` | the two lines appended to Ubuntu's series |
| `debian/patches/replace-read-selection-before-revert.patch` | the first change, with its reasons in DEP-3 headers |
| `debian/patches/revert-device-on-gui-thread.patch` | the second change, with its reasons in DEP-3 headers |
