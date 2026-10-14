<!-- Generated from packages/archive-keyring/README.md.in by scripts/render.py. Edit the .in file, not this one. -->
# oaxaca-archive-keyring

The first source package of every build. It produces two binary packages:

- `oaxaca-archive-keyring`: the public half of the archive signing key, in `/etc/apt/keyrings/`.
- `oaxaca-apt-source`: the apt sources entry for the Oaxaca repository, bound to that key. The name ends in `-apt-source` because that is the one form Debian policy (and lintian) allows for a package that installs apt sources.

`archive-keyring.gpg` is written here by `scripts/keygen.sh`; the build is skipped without it. See `docs/build-infra.md`.
