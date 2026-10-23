# Build infrastructure (roadmap step 2)

*Wording revised 2026-10-05 to follow the documentation guidelines (terms defined before use, subjects named); decisions, facts and dates unchanged.*

Set up 2026-09-30. This document covers what roadmap step 2 of [plan.md](0%20-%20plan.md) asks for: a [signing key](#signing-key), an [apt repository](#git-repository-and-apt-repository), clean [package](README.md#package) builds, and [CI](#ci-workflow-runner-artifact-and-github-release) that builds on every tag. Every decision in this document is a choice with reasons and a rejected alternative, not a vendor best practice, unless a source is cited.

## Terms

Each entry uses only terms defined above it or in the developer README's [Terms](README.md#terms) section. The first use of each term in the rest of this document links to its entry.

### Git repository and apt repository

"Repository" has two meanings in this project, and this document always says which. A git repository is a source tree under version control: `oaxaca`, this tree, on GitHub. An apt repository is an [archive](README.md#archive): the `dists/` and `pool/` tree that apt reads. Ours is published to an [S3 bucket](#s3-bucket), not to a git repository.

### Signing key

A GPG key pair whose secret half signs our apt repository's `InRelease` file and whose public half lets apt verify that signature. The pair lives in the GnuPG home directory of the workstation user, `~/.gnupg`. Its fingerprint is the 40-hex-digit identifier of the key, recorded in `distro.conf` as `APT_KEY_FPR`. Its user ID is the human-readable label on the key (`APT_KEY_NAME` in `distro.conf`, "Oaxaca Archive Signing Key"). A revocation certificate is a file GnuPG writes at creation time that can later declare the key invalid. A subkey is a secondary key attached to the pair that can sign on its behalf. pinentry is the dialog GnuPG uses to ask for the apt signing key passphrase, so that passphrase never appears on a command line.

### Keygrip

A 40-hex-digit hash GnuPG computes from a key's raw public numbers alone, ignoring the user ID, expiry and signatures. gpg-agent names its private key files by keygrip, so a keygrip and a fingerprint identify the same [signing key](#signing-key) but never have the same value.

### Transferable secret key

The OpenPGP wire format for a secret key, defined in RFC 9580 section 10.2. One blob carries the secret key material (encrypted under the apt signing key passphrase), the user ID, the self-signatures, the key flags and the expiry, so any OpenPGP program can import the key from that one blob. `gpg --export-secret-keys` writes a transferable secret key; `--armor` wraps the same bytes in base64 text between `-----BEGIN PGP PRIVATE KEY BLOCK-----` and `-----END PGP PRIVATE KEY BLOCK-----`.

### Archive keyring

The public half of the signing key, exported as a file apt can read. Ours is `packages/archive-keyring/archive-keyring.gpg`, shipped by the `oaxaca-archive-keyring` package to `/etc/apt/keyrings/oaxaca-archive-keyring.gpg`. The apt sources stanza for our apt repository names that file in its `Signed-By` field, which binds the repository to the key.

### Template and rendered file

A template is a file ending in `.in` that contains tokens such as `@DISTRO_ID@`. `make render` (`scripts/render.py`) replaces the tokens with values from `distro.conf` and writes the rendered file next to the template, without the `.in` suffix. Rendered files are committed to the `oaxaca` git repository.

### Unshare mode

sbuild's way of building inside a [chroot](README.md#chroot) without root privileges. In unshare mode sbuild creates an unprivileged user namespace, a kernel feature that lets an ordinary user act as the root user inside a private view of the system, unpacks the chroot tarball there, and runs the build as that fake root. Nothing outside the namespace is touched, and no `sbuild` group membership is needed.

### lintian

Debian's package checker. lintian inspects finished packages against Debian policy: file placement, maintainer scripts, descriptions, licenses, and naming rules such as "only a package named `*-apt-source` may install an apt sources file". `scripts/build.sh` runs lintian on every build and fails on errors.

### aptly repository, snapshot and publish

aptly, the tool that manages our apt repository, works with three objects. An aptly repository is aptly's own database of packages plus its package pool, kept under `~/.local/state/oaxaca/aptly` (configured by `aptly.conf` in that directory, a JSON file `scripts/repo-publish.sh` writes). A snapshot is an immutable copy of an aptly repository's contents at one moment. A publish, in aptly's sense, turns a snapshot into the `dists/` and `pool/` tree apt reads, written under `~/.local/state/oaxaca/aptly/public/` with its `InRelease` file signed by the signing key. Publishing in this sense writes files on the workstation only; pushing those files to GitHub is a separate step, and this document never uses "publish" for the push.

### Origin field

A field in the published `InRelease` file (`dists/stonking/InRelease` in our apt repository) that names who published the repository. Ours reads `Origin: Oaxaca`, set by `scripts/repo-publish.sh` from `APT_ORIGIN` in `distro.conf`. apt pinning rules select a repository by this field (`Pin: release o=Oaxaca`), which is why the field is ours to control.

### S3 bucket

A named container of files in Amazon S3, AWS's object storage. Our apt repository's files are in the bucket `oaxaca-apt` in `us-east-1`. apt reads them at the `APT_URL` in `distro.conf`, `https://apt.oaxaca.page`, through an Amazon CloudFront distribution: AWS's content delivery network, which answers each request from an edge server near the client and fetches from the bucket what the edge server does not hold. The bucket, the distribution, the TLS certificate for `apt.oaxaca.page` and the DNS records that point `apt.oaxaca.page` at the distribution are created by one CloudFormation template, `infra/apt-repo/apt-repo.yaml` (`make apt-infra`); `make publish` fills the bucket; [infra/apt-repo/README.md](../infra/apt-repo/README.md) has the details.

### CI: workflow, runner, artifact and GitHub Release

CI (continuous integration) here means GitHub Actions. A workflow is a YAML file under `.github/workflows/` that GitHub runs on events such as a push; ours is `.github/workflows/build.yml`. A runner is the virtual machine GitHub starts for a workflow run, selected by a label such as `ubuntu-26.04`. An artifact is a set of files a workflow run uploads so they can be downloaded afterwards. A GitHub Release is a page attached to a git tag that can carry downloadable files; our workflow attaches the built packages to the GitHub Release for every `v*` tag. "Release" in this document means a GitHub Release unless the text says "distro release" or "the `Release` file".

### Transitional package

A near-empty package published under an old name whose only purpose is to depend on the package's new name, so that `apt upgrade` on an installed system carries users across a rename.

### PPA and dput

Launchpad terms, used here only in a rejected alternative. A PPA (Personal Package Archive) is an apt repository that Launchpad builds and hosts for a Launchpad account, signed with a key Launchpad owns. dput is the tool that uploads a [source package](README.md#source-package) to Launchpad for building.

## Anatomy

You type `make <target>`. Each make target runs one script, and each script runs one tool:

| You run | Script | Tool underneath | Result |
|---|---|---|---|
| `make render` | `scripts/render.py` | none | every [template](#template-and-rendered-file) rendered from `distro.conf` (see [policy.md](1%20-%20policy.md), section 1) |
| `make chroot` | `scripts/chroot-create.sh` | `mmdebstrap` | `~/.cache/sbuild/stonking-amd64.tar`, a 432 MB buildd chroot from the Ubuntu archive (the `main` and `universe` [components](README.md#component), the `-updates` and `-security` [pockets](README.md#suite-and-pocket), [Recommends](README.md#recommends) off). The script skips the work if the tarball is under 7 days old; `--force` rebuilds the tarball |
| `make build [PKG=packages/<dir>]` | `scripts/build.sh` | `sbuild` in [unshare mode](#unshare-mode), then [lintian](#lintian) | source and binary packages in `build/`. sbuild reads `sbuild.conf` from the root of the `oaxaca` git repository (a Perl-syntax settings file) through the `SBUILD_CONFIG` environment variable, so your `~/.sbuildrc` is untouched |
| `make publish [PUBLISH_FLAGS=--push]` | `scripts/repo-publish.sh` | `aptly`, then `rsync` and `git` | the packages in `build/` added to the [aptly repository](#aptly-repository-snapshot-and-publish) under `~/.local/state/oaxaca/aptly`, a snapshot published and signed with the signing key, the published tree synced into the checkout of the `oaxaca-apt` git repository at `~/Projects/oaxaca-apt`. Only `--push` commits and pushes that checkout |
| `scripts/keygen.sh` (once) | | `gpg` | the signing key in your GnuPG home, the key's public half in `packages/archive-keyring/` as the [archive keyring](#archive-keyring), the key's fingerprint in `distro.conf` |
| a push, PR or `v*` tag | `.github/workflows/build.yml` | the same `make` targets on `ubuntu-26.04` runners: one job prepares the chroot, then one job per package directory builds it, or restores its last build from the cache when nothing it reads has changed | one artifact per package (`packages-<directory>`) with the built files and sbuild's log; on a tag, a last job attaches every package to a GitHub Release |

The clean build in more detail: `scripts/build.sh` runs `dpkg-source -b` from inside `build/` so the source package (`.dsc` and `.tar.xz`) lands there and not in `packages/`, then sbuild takes that `.dsc`, unpacks the chroot tarball inside an unprivileged user namespace (no root privileges, no `sbuild` group), installs the package's declared [build dependencies](README.md#build-dependencies) into that unpacked copy, runs `dpkg-buildpackage` there, and writes the results to `build/`. lintian then checks every `.changes` file on the host and fails the build on errors.

## Choices

1. **A self-hosted aptly repository in an [S3 bucket](#s3-bucket), not a Launchpad [PPA](#ppa-and-dput).** The signing key, the [`Origin` field](#origin-field) (`Origin: Oaxaca`, what apt pins match on) and the apt repository's URL are ours, so a rebrand or a move changes `distro.conf`, not users' trust decisions. A PPA's signing key is Launchpad's, a PPA's `Origin` is `LP-PPA-<user>-<name>`, and a PPA's URL carries the Launchpad user name. Rejected: a PPA, for those reasons and because a PPA needs a Launchpad account, a key registered there and the `dput` upload flow. A PPA is kept as a fallback for builds too heavy for a GitHub runner, such as a Hyprland backport. Rejected as well: GitHub Pages, which served the repository until 2026-10-13. GitHub refuses files over 100 MB (`oaxaca-themes` is 111 MB, the fonts and desktop source tarballs 135 MB and 118 MB), and GitHub's [Pages limits](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits) say "Published GitHub Pages sites may be no larger than 1 GB"; the Pages checkout had reached 758 MB. S3 has neither limit; storage and downloads are billed by AWS.
2. **aptly, not reprepro.** aptly publishes snapshots, so each aptly publish is atomic and the published tree can be switched back to any earlier snapshot. reprepro, the other common apt repository manager, holds one version per package per suite and has no rollback. Rejected: reprepro.
3. **sbuild in unshare mode with an mmdebstrap tarball, not pbuilder or a container.** No root at any point, and the same sbuild with the same chroot tarball runs locally and in CI. pbuilder, the older Debian build tool, needs root privileges. A build inside a container resolves build dependencies against whatever the container image already has, so a passing container build doesn't prove the declared `Build-Depends` are complete. Rejected: pbuilder and containers. `sbuild.conf` at the root of the `oaxaca` git repository turns off sbuild's own chroot auto-creation, which would otherwise rebuild the chroot tarball after a week with Debian defaults that don't know Ubuntu series.
4. **RSA 4096 sign-only key, two-year expiry.** RSA is what every gpgv-based consumer understands, including `mmdebstrap --keyring` when the distro image builder (roadmap step 3) pulls from our apt repository. Rejected: Ed25519, which modern apt accepts but older tooling in the chain may not. Expiry forces a rotation habit; the rotation procedure is in "Key rotation" below.
5. **CI builds, the workstation signs and publishes.** The signing key's secret half never leaves your GnuPG home. A CI run that could sign would make a compromised runner or a leaked secret an apt repository compromise. Rejected: the signing key in GitHub Actions secrets. Revisit with a dedicated signing subkey if distro releases become frequent enough for the manual step to hurt.
6. **Two binary packages from the first source package.** Debian policy, enforced by lintian, forbids packages from installing apt sources unless their name ends in `-apt-source`. So `oaxaca-archive-keyring` ships only the archive keyring and `oaxaca-apt-source` ships only the sources stanza (`packages/archive-keyring/archive.sources`, installed as `/etc/apt/sources.list.d/oaxaca.sources`). Rejected: a lintian override, which would need justifying forever.
7. **Rendered files are committed, and CI checks them.** A clone of the `oaxaca` git repository is complete without running anything, real file names show up in `git grep`, and `make check-render` fails the CI build if someone edits a rendered file or forgets to re-render after changing `distro.conf`. Rejected: generating rendered files only at build time.
8. **sbuild's temporary directory on the runner's disk, two build jobs, and a visible build log (added 2026-10-10).** The step-5 push's run died after 22 minutes in the `quickshell` build with one line of output, "E: Build failure (dpkg-buildpackage died with exit 2)". sbuild only echoes the build log to standard output when its stdin and stdout are terminals (its `VERBOSE` default), so on the runner sbuild's log went only to `build/quickshell_0.3.2-0oaxaca1_amd64-<time>.build`, which the workflow did not upload; `sbuild.conf` now sets `$verbose = 1` and the workflow uploads the `.build` files (copied under `build/logs/` with the colons in their names replaced, because upload-artifact rejects colons) even when the build failed. With the log visible, the next run showed the error: at quickshell's final link, `lto1: fatal error: write: No space left on device`. sbuild's unshare mode unpacks the chroot and runs the whole build under `$TMPDIR`, `/tmp` by default (`sbuild.conf(5)`, `UNSHARE_TMPDIR_TEMPLATE`), and Ubuntu has mounted `/tmp` as a tmpfs of half the RAM since the 24.10 cycle (Launchpad bug 2069834, "systemd defaulting to tmpfs for /tmp causes enospc errors"), so on a 16 GB runner that is 8 GB at most, shared with whatever else the job puts there. The same build on this workstation, where `/tmp` is also a tmpfs, needs 4.8 GB of `/tmp` at its peak (chroot, build dependencies, build tree and the link's LTO temporary files; sampled once a second with `df`). The workflow now runs the build with `TMPDIR=/var/tmp`, which is on the root disk, the choice `sbuild.conf(5)` itself names "if /tmp is too small", and logs `findmnt` and `df` for `/`, `/tmp` and `/var/tmp` in a step before the build so the next failure of this kind has its numbers in the log. A standard runner also has only 4 CPUs and 16 GB (GitHub's runner reference), and the same build pinned to 4 CPUs under a 16 GB cgroup cap peaks at 12.4 GB of anonymous memory with four g++ jobs and 1.9 GB with two (sampled once a second from the cgroup's `memory.stat`, `anon` line, so a spike shorter than a second could be missed); the workflow keeps `DEB_BUILD_OPTIONS=parallel=2`, which sbuild passes into the chroot, at the cost of 7 min 16 s instead of 5 min 30 s for that package. Rejected: a larger runner (paid, and the build is two minutes longer at two jobs, not hours); building without LTO or debug information (Ubuntu's own `quickshell` is built with both through dpkg's default flags, and the `-dbgsym` packages are what makes a shell crash on a user's machine diagnosable); deleting preinstalled software from the runner to make room, the usual workaround, which is a fallback if `/var/tmp` turns out to be short too.
9. **One job per package, and a cache that skips unchanged packages (added 2026-10-10).** The single job that built all 14 packages took 30 min 47 s on every push: `quickshell` 16 min 02 s, `hyprland-preview-share-picker` 5 min 47 s, the other twelve about 4 min 30 s together, lintian over all of them 1 min 52 s, setup and upload about a minute. The workflow now has three jobs. `prepare` checks the rendered files, lists the directories under `packages/` for the matrix and restores or creates the chroot once (a creation takes about 25 minutes, and fourteen jobs would otherwise each do it). `build` runs one job per directory, in parallel, which GitHub runs concurrently at no cost for a public repository; each job first asks `actions/cache` for an entry keyed on the hash of its package directory, `distro.conf`, `scripts/build.sh`, `scripts/render.py` and `sbuild.conf`, plus the chroot's weekly key. A hit restores the `.deb`, `.ddeb`, `.dsc`, tarballs, `.changes`, `.buildinfo` and `build/logs/` from the last build and the job uploads them without installing anything; a miss builds that one package with `make build PKG=packages/<directory>` and the cache saves the files when the job succeeds, never after a failure. `release`, on a `v*` tag, downloads every `packages-*` artifact into one directory and attaches the downloaded files to the GitHub Release, so a tag's release carries cached and fresh packages alike. Expected times, to be confirmed by the next runs: a push that touches no package about a minute per job; a push to one small package a few minutes; a full rebuild, after a chroot rotation or a change to `distro.conf` or the build scripts, as long as `quickshell`, about 17 minutes. Rejected: a compiler cache (ccache) inside the chroot, which would cut `quickshell`'s compile but adds a bind mount and a second cache for a package whose source changes only when its version does; keying the cache on the package version instead of its files' hash, which would miss a packaging change made without a version bump.
10. **The apt repository at its own host name, `apt.oaxaca.page`, through CloudFront, with CloudFront as the bucket's only reader (2026-10-22).** apt reads the repository at a host name in a domain of our own (`APT_DOMAIN=oaxaca.page`, `APT_HOST=apt.oaxaca.page` in `distro.conf`), carried by `oaxaca-apt-source`, rather than at a URL that names the storage, such as the bucket's REST endpoint, `https://oaxaca-apt.s3.us-east-1.amazonaws.com`: a URL naming the storage would have to change in every installed system's sources entry whenever the storage changed, and our own host name stays. CloudFront serves that name over HTTPS with a certificate from AWS Certificate Manager, and its edge servers keep a copy of each `pool/` file, so a repeated download (the release's own `upgrade-test`, `session-upgrade-test` and `repo-seed`) does not reach the bucket. `dists/` is never cached, because apt checks every index against `InRelease` and a publish rewrites them together; `pool/` is cached because a published file name never gets new content, which `make publish` enforces with no override. The bucket is readable only through the distribution (`APT_S3_PUBLIC_READ=false` in `distro.conf`): its policy grants `s3:GetObject` to that one distribution, S3's Block Public Access is on, and a request to the REST endpoint gets 403. Measured on 2026-10-22 from the maintainer's laptop, the bucket's REST endpoint against CloudFront: `InRelease` (5.9 KB) took 0.34 to 0.44 s to its first byte from the bucket and 0.135 to 0.143 s through CloudFront; `oaxaca-themes` (116 MB) downloaded from the bucket at 3.0 to 14.3 MB/s over three runs, and through CloudFront in 2.6 s (44.3 MB/s) on its first download, a cache miss (`x-cache: Miss from cloudfront`), and 1.7 s (68.2 and 69.3 MB/s) on the next two, cache hits. Even a miss beat the bucket, because the edge server's route to the bucket is faster than the laptop's. Rejected: S3's static website hosting (no HTTPS, as [infra/apt-repo/README.md](../infra/apt-repo/README.md) says); a CNAME straight to the bucket (S3's REST endpoint presents only Amazon's certificate, so HTTPS to our own name fails); invalidating CloudFront's cache after each publish instead of not caching `dists/` (a CloudFront permission and a wait added to `make publish`, and a window while the invalidation runs); leaving the bucket readable by anyone as well (a second URL that bypasses the distribution and that nothing needs).

## One-time setup, in order

These steps are yours to run: the signing key needs its apt signing key passphrase through pinentry, and the GitHub steps are outward-facing.

1. **Create the signing key.** In a terminal: `scripts/keygen.sh`. Choose the apt signing key passphrase and keep it in your password manager. The script prints the key's fingerprint, writes the fingerprint into `distro.conf`, and exports the key's public half to `packages/archive-keyring/archive-keyring.gpg` and `.asc`. Then back up the secret half and the revocation certificate as described in [Backing up the signing key](#backing-up-the-signing-key). Commit `distro.conf` and both public key files.
2. **Create the GitHub git repository** for this source tree; its name comes from `distro.conf` (`GITHUB_REPO`).
   ```
   gh repo create santisbon/oaxaca --public --description "Oaxaca Linux"
   git remote add origin git@github.com:santisbon/oaxaca.git
   ```
3. **Create the apt repository's S3 bucket** with the aws-cli profile `APT_AWS_PROFILE` from `distro.conf` (steps in [infra/apt-repo/README.md](../infra/apt-repo/README.md)):
   ```
   make apt-infra
   ```
   The last line printed is the repository URL, which must equal the `APT_URL` in `distro.conf`.
4. **First publish.** `make chroot && make build && make publish`, review what the upload would change, then `make publish PUBLISH_FLAGS=--push`.
5. **Verify the signature from any machine with `gpgv`.** Run this from the source tree, so the keyring path resolves. The same check applies after every later publish:
   ```
   curl -fsSL https://apt.oaxaca.page/dists/stonking/InRelease | gpgv --keyring packages/archive-keyring/archive-keyring.gpg -
   ```
   Expected output, where `<fingerprint>` is the `APT_KEY_FPR` value in `distro.conf`:
   ```
   gpgv: Signature made <date>
   gpgv:                using RSA key <fingerprint>
   gpgv: Good signature from "Oaxaca Archive Signing Key"
   ```
   Any other result (`BAD signature`, `Can't check signature: No public key`, or an HTTP error from `curl`) means the publish or the keyring is wrong; do not go on to step 6.
6. **Verify apt on a test machine.** The test machine is any Ubuntu install you are willing to add our apt repository to, this workstation included. Both packages are architecture `all` with no dependencies, so the test machine's Ubuntu release does not matter. Copy the two packages over and install them, from the source tree:
   ```
   scp build/oaxaca-archive-keyring_0.1.0_all.deb build/oaxaca-apt-source_0.1.0_all.deb <test-machine>:
   ssh <test-machine>
   sudo apt install ./oaxaca-archive-keyring_0.1.0_all.deb ./oaxaca-apt-source_0.1.0_all.deb
   ```
   On the workstation itself, skip `scp` and `ssh` and run the `apt install` line with the `build/` paths. 
   ```sh
   sudo apt install ./build/oaxaca-archive-keyring_0.1.0_all.deb ./build/oaxaca-apt-source_0.1.0_all.deb
   ```

   Confirm the two files the packages install:
   ```
   ls -l /etc/apt/keyrings/oaxaca-archive-keyring.gpg
   cat /etc/apt/sources.list.d/oaxaca.sources
   ```
   The `cat` output must show our apt repository's deb822 stanza: `URIs: https://apt.oaxaca.page`, `Suites: stonking`, `Components: main`, `Signed-By: /etc/apt/keyrings/oaxaca-archive-keyring.gpg`. Then refresh the package lists:
   ```
   sudo apt update
   ```
   Or if you're usgin a VPN and some of your repos (e.g. `packages.microsoft.com`) block your request:
   ```sh
   sudo mullvad-exclude apt update # or equivalent for your VPN software
   ```

   The output must contain a line `Get:` or `Hit:` for `https://apt.oaxaca.page stonking InRelease` and no line starting with `W:` or `E:` that names `apt.oaxaca.page`. A `W: ... NO_PUBKEY` line means apt is not using the keyring; an `E: ... 403` line means nothing is published at that path in the bucket yet (the bucket answers a missing file with 403, since nobody may list it) (`make publish PUBLISH_FLAGS=--push`). A line `Notice: Skipping acquire of configured file 'main/binary-i386/Packages' as repository 'https://apt.oaxaca.page stonking InRelease' doesn't support architecture 'i386'` is expected on a machine that has i386 enabled as a foreign architecture (`dpkg --print-foreign-architectures`), because our apt repository publishes only amd64 and source. Then check that apt attributes our packages to our [Origin](#origin-field):
   ```
   apt policy | grep -A2 apt.oaxaca.page
   ```
   Expected output:
   ```
    500 https://apt.oaxaca.page stonking/main amd64 Packages
        release o=Oaxaca,a=stonking,n=stonking,l=Oaxaca,c=main,b=amd64
        origin apt.oaxaca.page
   ```
   `o=Oaxaca` is the `APT_ORIGIN` from `distro.conf`, and `l=Oaxaca` is `APT_LABEL`. `b=amd64` names the index file apt read, `stonking/main/binary-amd64/Packages`. An apt repository has no `binary-all` index: packages of architecture `all` are listed inside every real architecture's `Packages` file, so `amd64` is expected here even though both of our packages are `all`. Last, fetch a package through the repository to prove the `pool/` path and the checksums in `Packages` are right:
   ```
   cd "$(mktemp -d)" && apt download oaxaca-archive-keyring && ls
   ```
   `ls` must list `oaxaca-archive-keyring_0.1.0_all.deb`. An error `Hash Sum mismatch` or `403` here means `make publish` staged `dists/` without the matching `pool/`, which a rerun of `make publish` fixes.

## Backing up the signing key

`scripts/keygen.sh` leaves the [signing key](#signing-key) in four places under `~/.gnupg`, and only one of them is the right thing to back up.

| Path under `~/.gnupg` | What the file holds | Back it up? |
|---|---|---|
| `private-keys-v1.d/<keygrip>.key` | The secret key material in gpg-agent's own storage format, encrypted under the apt signing key passphrase, named by [keygrip](#keygrip). Only the raw secret numbers: no user ID, no expiry, no self-signature. | No. The storage format is internal to GnuPG and has already changed once: GnuPG 2.1.12 added a second, text-based format and GnuPG 2.3.0 made that format the default for new keys. Restoring from this file means copying it back under the same keygrip name and importing the public key separately, which GnuPG does not document as a procedure. |
| `pubring.kbx` | The public half of every key on the workstation, with user IDs, expiry and signatures. | No. The project's copy of our public key is `packages/archive-keyring/archive-keyring.gpg`, committed to git. |
| `openpgp-revocs.d/<fingerprint>.rev` | The revocation certificate GnuPG wrote at creation time. Publishing that certificate marks the key as invalid everywhere. | Yes, alongside the secret key. The revocation certificate is the only way to retire the key if the apt signing key passphrase is forgotten. |
| `trustdb.gpg` | Trust settings for the workstation's keyring. | No. |

The backup to make is a [transferable secret key](#transferable-secret-key), which `gpg --export-secret-keys` produces from the first two files combined. Being standard OpenPGP, that export restores with one `gpg --import` on any GnuPG version or any other OpenPGP implementation, and the armored form is plain text that a password manager stores as a secure note or an attached document. The secret material inside the export stays encrypted under the apt signing key passphrase, so that passphrase must sit in the same vault or the export is unusable. Run these yourself, in a terminal, with the fingerprint from `APT_KEY_FPR` in `distro.conf`:

```
gpg --export-secret-keys --armor <fingerprint> > ~/oaxaca-archive-key.asc
cat ~/.gnupg/openpgp-revocs.d/<fingerprint>.rev
```

Store three items in the password manager: the contents of `~/oaxaca-archive-key.asc`, the revocation certificate the second command printed, and the apt signing key passphrase. Then remove the temporary export with `shred -u ~/oaxaca-archive-key.asc`. The `.key` file under `private-keys-v1.d` stays where gpg-agent put it; the workstation keeps signing from there.

To restore the signing key on a replacement workstation, paste the saved export into a file and run `gpg --import` on that file, then `gpg --edit-key <fingerprint> trust` and choose ultimate so GnuPG signs with the key without warnings. To retire the key after a compromise, run `gpg --import` on the saved revocation certificate and follow [Key rotation](#key-rotation) step 2.

## Adding a package

1. `mkdir packages/<dir>` with `debian/control.in`, `debian/changelog.in`, `debian/rules.in` (only if the rules file needs the distro's name), `debian/copyright`, `debian/source/format`. Directory names never carry the distro name; use `@DISTRO_ID@` inside files. For a single binary package, use debhelper's unprefixed file names (`debian/install`, `debian/service`, `debian/udev`, `debian/docs`, each as a `.in` template when the file's contents carry the distro's name or identifier) so no file name has to be rendered; `packages/hybrid-backlight` is the example. Versions follow [policy.md](1%20-%20policy.md), "Version scheme".
2. `make build PKG=packages/<dir>`. Fix what lintian reports.
3. Commit, push, and tag a version (`vX.Y.Z`) when ready. CI builds every push and, on a `v*` tag, attaches the built packages to the GitHub Release for that tag.
4. `make publish` from the workstation. When a package build-depends on another package of ours, run `WITH_REPO=1 make build`, which enables our published apt repository inside the chroot.

A package's `debian/` directory may hold its own subdirectories: `debian/source/` (every package), `debian/patches/` (a quilt patch set), `debian/upstream/` (upstream metadata or signing key) and `debian/extra/` (files the rules file installs that are not part of the source). `.gitignore` ignores every directory under `packages/*/debian/` because debhelper creates one per binary package there during an in-tree build, so each of those four names is listed back in with a `!` rule. A new directory name under `debian/` needs its own `!` line, or the directory never reaches git: on 2026-10-10 the desktop package's `debian/extra/` was missing from the first push of step 6, and CI failed on `cp: cannot stat 'debian/extra/logo.txt'` while `make check-render` passed, since the check diffs tracked files and cannot see an ignored directory.

## Rebrand playbook

Everything the distro's name touches is generated from `distro.conf`, so a rebrand starts with editing `distro.conf` and running `make render`. What a rebrand does not make free:

- **Installed users.** Package names change, so ship [transitional packages](#transitional-package) under the old names (`oldid-desktop` depending on `newid-desktop`) for one distro release, then drop the transitional packages.
- **The apt URL.** Our apt repository's URL is a host name in our own domain (`APT_HOST` in `distro.conf`, choice 10), so a rebrand that keeps the domain keeps the URL. A new domain is a new URL: the new `oaxaca-apt-source` package carries it, but users only receive that package through the old URL, so keep the old host name serving (a second alias on the distribution, with its certificate) until the transitional packages have reached everyone.
- **The signing key.** The signing key's user ID carries the old distro name. Add a new user ID rather than a new key (`gpg --edit-key <fpr> adduid`), re-export the public half with `gpg --export`, and republish the keyring package. Users keep trusting the same key.
- **State and config paths** (`~/.config/<id>`, `~/.local/state/<id>`, `/etc/<id>`). Port those paths with a migration, the same mechanism roadmap step 8 uses for Omarchy's `migrations/`.

## Key rotation

Two years after creation the signing key expires and apt refuses our apt repository. Two months before the expiry date:

1. Extend the expiry in place (`gpg --edit-key <fpr> expire`), re-export the public half with `gpg --export`, republish `oaxaca-archive-keyring`. Users who update get the extended key. Extending in place is the normal path.
2. Only if the signing key is compromised: clear `APT_KEY_FPR` in `distro.conf`, run `scripts/keygen.sh`, and publish a keyring package signed by the old key that installs the new key, then switch publishing to the new key. Revoke the old key with the stored revocation certificate.

## Verified on 2026-09-30

These checks were done with a throwaway signing key that lived only in the session's scratch directory and was deleted afterwards. No real signing key existed yet.

- `make render` renders the six templates of `packages/archive-keyring`, and CI's `make check-render` catches a rendered file that drifts from `distro.conf`.
- `make chroot` builds the 432 MB `stonking` chroot tarball in about two minutes.
- `make build` on the keyring package: 16 s in the clean chroot, lintian clean, the source package plus two `all` binaries in `build/`.
- `make publish` twice: the first aptly publish creates the published tree (`Origin: Oaxaca`, `Label: Oaxaca`, `Architectures: amd64`, both `.deb` files and the source package in `pool/`), the second switches the published tree to a new snapshot. `gpgv` with the exported public key reports a good signature on `InRelease`. An `apt-get update` against the staged `oaxaca-apt` checkout runs with no warnings and resolves both packages.
- Second package, `packages/hybrid-backlight` (`oaxaca-hybrid-backlight`, the phantom-backlight hide from the suspend baseline): builds lintian clean through the same pipeline. The systemd unit lands in `/usr/lib/systemd/system/`, the udev rule in `/usr/lib/udev/rules.d/60-oaxaca-hybrid-backlight.rules`, the script in `/usr/libexec/oaxaca/`, and the package's postinst script enables and starts that unit. The script's decision logic was dry-run on this laptop and against fake sysfs layouts for MUX mode.
- Two bugs found and fixed on the way: mmdebstrap treats an output path not ending in `.tar` as a directory, so the temporary tarball name must keep the extension; and aptly publishes nothing for an aptly repository that holds only `all` packages unless the architectures are named explicitly.

## Facts checked on 2026-09-30

| Fact | Value | Source |
|---|---|---|
| Tools on this workstation | sbuild 0.91.2, mmdebstrap 1.5.7, aptly 1.6.2, debhelper 13.31, lintian 2.129 | `dpkg-query` |
| Unprivileged user namespaces here | allowed (`kernel.apparmor_restrict_unprivileged_userns = 0`) | `sysctl` |
| GitHub runner label for 26.04 | `ubuntu-26.04` (x64), `ubuntu-latest` is still 24.04 | `actions/runner-images` README |
| Current action majors | `actions/checkout@v7`, `actions/cache@v6`, `actions/upload-artifact@v7` | GitHub releases |
| Transferable secret key format | RFC 9580 section 10.2 | rfc-editor.org, checked 2026-10-06 |
| gpg-agent private key file format history | read support for the extended format in 2.1.12 (2016-05-04), default from 2.3.0 (2021-04-07); workstation runs GnuPG 2.4.8 | `/usr/share/doc/gnupg/NEWS.gz`, `gpg --version`, checked 2026-10-06 |
