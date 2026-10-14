# Entry points for the build. See docs/2 - build-infra.md, docs/3 - rootfs.md and docs/4 - session.md.
.PHONY: render check-render check-versions upstream-check chroot build lint publish apt-infra apt-infra-check rootfs rootfs-test drivers-check iso iso-test upgrade-test clean

# Root filesystem profile for rootfs, rootfs-test and drivers-check: base (step 3), session (step 4),
# desktop (step 6) or live (step 7, the desktop plus casper and the installer: what the ISO ships).
# The default is the newest layer, the one the ISO is made from.
PROFILE ?= live
SECURE_BOOT ?= on

render:            ## Render every *.in file from distro.conf
	scripts/render.py

check-render: render   ## Fail if committed rendered files don't match distro.conf (CI)
	@git diff --exit-code -- . ':!build' >/dev/null || { echo "rendered files are out of date: run 'make render' and commit the result"; git --no-pager diff --stat -- . ':!build'; exit 1; }

check-versions:    ## Fail if a package directory changed since the last v* tag without a version bump (CI)
	scripts/version-check.sh

upstream-check:    ## Fail if a repackaged program (RELEASES= in packages/*/upstream) has a newer GitHub release
	scripts/upstream-check.sh

chroot:            ## Create or refresh the clean build chroot (~/.cache/sbuild)
	scripts/chroot-create.sh

build: render      ## Build packages in the clean chroot: make build [PKG=packages/<dir>]
	scripts/build.sh $(PKG)

publish:           ## Add build/'s newest packages to the apt repo, sign, and upload to S3 with --push: make publish [PUBLISH_FLAGS="--push --replace"]
	scripts/repo-publish.sh $(PUBLISH_FLAGS)

apt-infra:         ## Create or update the S3 bucket that serves the apt repo (CloudFormation, infra/apt-repo/)
	scripts/apt-infra.sh

apt-infra-check:   ## Validate the bucket's CloudFormation template and show the stack's state; changes nothing
	scripts/apt-infra.sh --check

rootfs:            ## Build the root filesystem tarball from the Ubuntu archive plus build/*.deb: make rootfs [PROFILE=base|session|desktop|live]
	PROFILE=$(PROFILE) scripts/rootfs-create.sh

rootfs-test:       ## Boot the root filesystem tarball in QEMU and check the base system (and, for session, the graphical session) comes up
	PROFILE=$(PROFILE) scripts/rootfs-boot-test.sh

drivers-check:     ## Ask ubuntu-drivers, inside the tarball, what it would install for this machine's GPU (step 4)
	PROFILE=$(PROFILE) scripts/drivers-check.sh

iso:               ## Build the live installation ISO (and its test variant) from the live root filesystem: make rootfs first
	scripts/iso-create.sh

iso-test:          ## Boot the test ISO in QEMU under OVMF and check the live session: make iso-test [SECURE_BOOT=on|off]
	SECURE_BOOT=$(SECURE_BOOT) scripts/iso-boot-test.sh

upgrade-test:      ## Upgrade the published packages to build/ in a throwaway chroot and run the migrations (step 8)
	scripts/upgrade-test.sh

clean:
	rm -rf build
