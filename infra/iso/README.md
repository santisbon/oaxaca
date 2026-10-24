<!-- Generated from infra/iso/README.md.in by scripts/render.py. Edit the .in file, not this one. -->
# The installation ISO's downloads

Oaxaca's installation ISO is stored in an Amazon S3 bucket and served at https://get.oaxaca.page by Amazon CloudFront, which is the bucket's only reader. This folder holds the definition of both, and of the certificate and DNS records that go with them; the scripts that create them and upload to the bucket are in `scripts/`. The distro's website reads `https://get.oaxaca.page/latest.json` when it is built and links its download button to the ISO it names (docs/7, choice 59).

## Terms

### S3 bucket

A named container of files ("objects") in Amazon S3, AWS's object storage. Bucket names are global across all AWS accounts.

### CloudFront distribution

Amazon CloudFront is AWS's content delivery network: servers in many cities ("edge locations") that answer HTTPS requests for a site. A distribution is one site's configuration: the host names it answers for, its TLS certificate, and its origin, the place it fetches files from (here the [bucket](#s3-bucket)). An edge server keeps a copy of a file it fetched for as long as the distribution's cache policy says.

### Origin access control

The CloudFront setting that makes the [distribution](#cloudfront-distribution) sign its requests to the bucket, so that the bucket's policy can allow that one distribution to read while refusing everyone else.

### CloudFormation stack

AWS CloudFormation creates AWS resources from a template, a YAML file that declares them, and keeps them together as a stack: deploying the template again changes the resources to match it.

### Apt signing key

The OpenPGP key pair named "Oaxaca Archive Signing Key", fingerprint `2A95E0E7A8E14C48320A00EB7C70659F7A4FDC5A` (`APT_KEY_FPR` in `distro.conf`). Its private key, in the GnuPG home on the workstation that runs releases and protected by the apt signing key passphrase, signs the apt repository and each ISO's `SHA256SUMS`. Its public key is `packages/archive-keyring/archive-keyring.asc` in this repository, installed on every system by `oaxaca-archive-keyring` and uploaded next to the ISOs as `archive-keyring.asc`.

### ISO version

The ISO's build time in UTC to the minute, such as `20261024.0412`. `scripts/iso-create.sh` writes it into the ISO's `.disk/info` and into `build/iso/iso-version`, and the uploaded ISO's file name carries it.

## Anatomy

| Piece | What it is | Command |
|---|---|---|
| `infra/iso/iso-host.yaml` | the [CloudFormation](#cloudformation-stack) template: the [bucket](#s3-bucket) (no public access of any kind, plain HTTP refused, kept when the stack is deleted), the [distribution](#cloudfront-distribution) with its [origin access control](#origin-access-control), the TLS certificate for `get.oaxaca.page` from AWS Certificate Manager, and the A and AAAA records for `get.oaxaca.page` in the Route 53 hosted zone of `oaxaca.page` | |
| `scripts/iso-infra.sh` | looks up that hosted zone's ID, then runs the aws-cli's `cloudformation deploy` with the template as the stack `oaxaca-iso` | `make iso-infra` (create or update), `make iso-infra-check` (validate, show the stack, change nothing) |
| `scripts/iso-publish.sh` | checks that `build/iso/oaxaca-26.10-amd64.iso` carries the [ISO version](#iso-version) in `build/iso/iso-version`, writes `SHA256SUMS`, signs it with the [apt signing key](#apt-signing-key)'s private key, uploads the ISO, the checksums, the archive key's public half and `latest.json`, deletes all but the newest `ISO_KEEP` ISOs, and checks what the host serves | `make iso-publish` (uploads), `make iso-publish ISO_PUBLISH_FLAGS=--dry-run` (checks and lists, uploads nothing); `make release` runs both, asking in between |

The settings are in `distro.conf`, in shell syntax at the repository root: `ISO_S3_BUCKET=oaxaca-iso`, `ISO_HOST=get.oaxaca.page`, `ISO_URL=https://get.oaxaca.page` and `ISO_KEEP=2`. The stack uses the apt repository's region and aws-cli profile, `APT_S3_REGION=us-east-1` (CloudFront only uses certificates from `us-east-1`) and `APT_AWS_PROFILE=personal`, and the hosted zone of `APT_DOMAIN=oaxaca.page`.

## What the bucket holds

```
26.10/<ISO version>/oaxaca-26.10-<ISO version>-amd64.iso
26.10/<ISO version>/SHA256SUMS        the list of SHA-256 hashes of the ISOs in the folder: one line, this ISO's
26.10/<ISO version>/SHA256SUMS.gpg    an OpenPGP detached signature of SHA256SUMS, by the apt signing key's private key
archive-keyring.asc                     the apt signing key's public key
latest.json                             the newest ISO: its file name, URL, size, SHA-256 and date
```

The newest `ISO_KEEP` ISO versions stay; each upload deletes the older ones. `latest.json` from a dry run, trimmed:

```json
{
  "name": "Oaxaca 26.10",
  "version": "20261024.0412",
  "file": "oaxaca-26.10-20261024.0412-amd64.iso",
  "url": "https://get.oaxaca.page/26.10/20261024.0412/oaxaca-26.10-20261024.0412-amd64.iso",
  "size": 3333453824,
  "sha256": "…",
  "key_fingerprint": "2A95E0E7A8E14C48320A00EB7C70659F7A4FDC5A"
}
```

## What CloudFront caches

- **`latest.json` is never cached** (AWS's managed `CachingDisabled` cache policy): each upload rewrites it, and the website's build must read the current one.
- **Everything else is cached** (AWS's managed `CachingOptimized` cache policy): an ISO and its checksum files live under a path named for the [ISO version](#iso-version), which no later upload reuses, so a cached copy is never out of date, and a download that runs while the next ISO is uploaded keeps getting the same file.

## Setting it up, once

1. The aws-cli installed, with the profile named in `APT_AWS_PROFILE` able to manage CloudFormation, S3, CloudFront, Certificate Manager and Route 53.
2. Create the stack:
   ```sh
   make iso-infra
   ```
   A first deploy waits until Certificate Manager has validated the certificate through a DNS record it adds to the hosted zone, and until CloudFront has rolled the distribution out. The last line printed is the downloads URL, which must equal `ISO_URL`.
3. Upload an ISO: answer `y` to the release's ISO question, or run `make iso-publish` after a `make iso`.
4. Publish the website, whose build reads `latest.json`.

## Checking a download

Each ISO's folder holds two files for checking it, and the downloads host's root a third:

- **`SHA256SUMS`**: the list of SHA-256 hashes of the ISOs in the folder, in `sha256sum`'s format. Each folder holds one ISO, so the list has one line, the ISO's SHA-256 hash and file name:
  ```
  3a6d7829164da6e9f24e16dbb002712bee2fd44c84a6adc7534e2375d0f492ac *oaxaca-26.10-20261024.0747-amd64.iso
  ```
  (from `https://get.oaxaca.page/26.10/20261024.0747/SHA256SUMS`, 2026-10-24). `sha256sum -c SHA256SUMS` hashes the downloaded ISO and compares the result with that line: it catches a corrupted or cut-off download, but not a replaced ISO, since whoever could replace the ISO on the host could replace `SHA256SUMS` too. `scripts/iso-publish.sh` uploads `SHA256SUMS` as `application/octet-stream` with the header `Content-Disposition: attachment; filename="SHA256SUMS"`: a browser saves a `text/plain` file whose name has no extension as `SHA256SUMS.txt`, and `gpg --verify SHA256SUMS.gpg SHA256SUMS` then finds no `SHA256SUMS`.
- **`SHA256SUMS.gpg`**: an OpenPGP detached signature of the file `SHA256SUMS` (RSA over a SHA-512 digest), made with the [apt signing key](#apt-signing-key)'s private key by `scripts/iso-publish.sh`. `gpg --verify` proves `SHA256SUMS` is exactly what that private key signed, which only the holder of the private key can produce.
- **`archive-keyring.asc`**: the apt signing key's public key, ASCII-armored, which `gpg --verify` needs to check `SHA256SUMS.gpg`.

The three checks depend on each other: a public key whose fingerprint matches `2A95E0E7A8E14C48320A00EB7C70659F7A4FDC5A` is the distro's, a good signature means `SHA256SUMS` came from the holder of its private key, and `OK` from `sha256sum -c` means the ISO is the one that list names. The public key, the signature and the ISO all come from the same AWS account, so the fingerprint is worth comparing with a copy from elsewhere: `APT_KEY_FPR` in this repository's `distro.conf` on GitHub, or `gpg --show-keys /etc/apt/keyrings/oaxaca-archive-keyring.gpg` on an installed system.

On a Linux machine, with the ISO, `SHA256SUMS`, `SHA256SUMS.gpg` and `archive-keyring.asc` in one folder:

```sh
gpg --import archive-keyring.asc
gpg --verify SHA256SUMS.gpg SHA256SUMS
sha256sum -c SHA256SUMS
```

`gpg --verify` must report a good signature from "Oaxaca Archive Signing Key", whose fingerprint is `2A95E0E7A8E14C48320A00EB7C70659F7A4FDC5A`, and `sha256sum -c` must print `OK` for the ISO.

## WAF

The distribution has its own AWS WAF web ACL, `oaxaca-iso-waf`, defined in the same template (docs/7, choice 61): AWS's managed IP reputation list, AWS's managed known bad inputs, and a per-IP rate limit of `WAF_RATE_LIMIT=2000` requests in 5 minutes. `WAF_ACTION=count` in `distro.conf` decides what the rules do: `count` records matches in CloudWatch metrics and the web ACL's sampled requests, `block` refuses them. To turn blocking on, review the matches in the AWS WAF console, set `WAF_ACTION=block`, and run the stack's `make` target again. The distribution is subscribed to CloudFront's Free flat-rate plan in the CloudFront console (Distributions, the distribution, its pricing plan), which includes the web ACL's cost and charges nothing extra however much traffic arrives.

## Teardown

Deleting the stack removes the distribution, the certificate and the records, and keeps the bucket and its contents (`DeletionPolicy: Retain` in the template). Removing the downloads for good is two steps: delete the stack (`aws cloudformation delete-stack --stack-name oaxaca-iso`), then empty and delete the bucket (`aws s3 rb s3://oaxaca-iso --force`).
