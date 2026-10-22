# Entry points for the build. See docs/2 - build-infra.md, docs/3 - rootfs.md and docs/4 - session.md.
.PHONY: render check-render check-versions upstream-check chroot build lint publish repo-seed machine-setup release release-message apt-infra apt-infra-check rootfs rootfs-test drivers-check iso iso-test upgrade-test session-upgrade-test factory-reset-test clean

# Root filesystem profile for rootfs, rootfs-test and drivers-check: base (step 3), session (step 4),
# desktop (step 6) or live (step 7, the desktop plus casper and the installer: what the ISO ships).
# The default is the newest layer, the one the ISO is made from.
PROFILE ?= live
SECURE_BOOT ?= on
# rootfs: SOURCE=published takes our packages from the published apt repository instead of build/.
# rootfs-test: UPGRADE=1 boots that published desktop and updates it to build/ inside its session.
SOURCE ?= build
UPGRADE ?= 0

render:            ## Render every *.in file from distro.conf
	scripts/render.py

check-render: render   ## Fail if committed rendered files don't match distro.conf (CI)
	@git diff --exit-code -- . ':!build' >/dev/null || { echo "rendered files are out of date: run 'make render' and commit the result"; git --no-pager diff --stat -- . ':!build'; exit 1; }

check-versions:    ## Fail if a package directory changed since the last v* tag without a version bump (CI)
	scripts/version-check.sh

upstream-check:    ## Fail if a repackaged program has a newer GitHub release (RELEASES=), or Ubuntu a newer upload of a rebuilt package (DSC=)
	scripts/upstream-check.sh

chroot:            ## Create or refresh the clean build chroot (~/.cache/sbuild)
	scripts/chroot-create.sh

build: render      ## Build packages in the clean chroot: make build [PKG=packages/<dir>]
	scripts/build.sh $(PKG)

publish:           ## Add build/'s newest packages to the apt repo, sign, and upload to S3 with --push: make publish [PUBLISH_FLAGS=--push]
	scripts/repo-publish.sh $(PUBLISH_FLAGS)

repo-seed:         ## Fill a new workstation's empty aptly database and build/ from the published apt repo (once per machine)
	scripts/repo-publish.sh --seed

machine-setup:     ## Install the build, test and publish tools, check the credentials, build the chroot and seed aptly: make machine-setup [SETUP_FLAGS=--tools]
	scripts/machine-setup.sh $(SETUP_FLAGS)

release:           ## Build what is unpublished, test the image, commit, and publish after a prompt (docs/README.md, Releasing)
	scripts/release.sh

release-message:   ## Print the commit message make release would use, without changing anything (docs/README.md, Releasing)
	@scripts/release.sh --message

apt-infra:         ## Create or update the S3 bucket, CloudFront distribution, certificate and DNS records that serve the apt repo (CloudFormation, infra/apt-repo/)
	scripts/apt-infra.sh

apt-infra-check:   ## Validate the apt repo's CloudFormation template and show the stack's state; changes nothing
	scripts/apt-infra.sh --check

rootfs:            ## Build the root filesystem tarball from the Ubuntu archive plus build/*.deb: make rootfs [PROFILE=base|session|desktop|live] [SOURCE=published]
	PROFILE=$(PROFILE) SOURCE=$(SOURCE) scripts/rootfs-create.sh

rootfs-test:       ## Boot the root filesystem tarball in QEMU and check the base system (and, for session, the graphical session) comes up
	PROFILE=$(PROFILE) UPGRADE=$(UPGRADE) scripts/rootfs-boot-test.sh

drivers-check:     ## Ask ubuntu-drivers, inside the tarball, what it would install for this machine's GPU (step 4)
	PROFILE=$(PROFILE) scripts/drivers-check.sh

iso:               ## Build the live installation ISO (and its test variant) from the desktop and live root filesystems: make rootfs PROFILE=desktop and make rootfs first
	scripts/iso-create.sh

iso-test:          ## Boot the test ISO in QEMU under OVMF and check the live session: make iso-test [SECURE_BOOT=on|off]
	SECURE_BOOT=$(SECURE_BOOT) scripts/iso-boot-test.sh

upgrade-test:      ## Upgrade the published packages to build/ in a throwaway chroot and run the migrations (step 8)
	scripts/upgrade-test.sh

session-upgrade-test: ## Boot the published desktop, update it to build/ inside its running session, and check the desktop
	PROFILE=desktop SOURCE=published scripts/rootfs-create.sh
	PROFILE=desktop UPGRADE=1 scripts/rootfs-boot-test.sh

factory-reset-test: ## Install the test ISO on an encrypted btrfs disk in QEMU, factory-reset it, and check the new owner's machine
	scripts/factory-reset-test.sh

clean:
	rm -rf build
