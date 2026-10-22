<!-- Generated from infra/apt-repo/README.md.in by scripts/render.py. Edit the .in file, not this one. -->
# The apt repository's hosting

Oaxaca's apt repository, the packages Ubuntu's archive does not have, is stored in an Amazon S3 bucket and served at https://apt.oaxaca.page by Amazon CloudFront. This folder holds the definition of both, and of the certificate and DNS records that go with them; the scripts that create them and upload to the bucket are in `scripts/`. Nothing here goes into a package or the installation image: installed systems only read the repository over HTTPS, through the URL in `oaxaca-apt-source`'s sources entry.

## Terms

### S3 bucket

A named container of files ("objects") in Amazon S3, AWS's object storage. Bucket names are global across all AWS accounts. An object can be read over HTTPS at `https://<bucket>.s3.<region>.amazonaws.com/<key>`, the bucket's REST endpoint, when the bucket's policy allows the reader.

### CloudFront distribution

Amazon CloudFront is AWS's content delivery network: servers in many cities ("edge locations") that answer HTTPS requests for a site. A distribution is one site's configuration: the host names it answers for, its TLS certificate, and its origin, the place it fetches files from (here the [bucket](#s3-bucket)). An edge server keeps a copy of a file it fetched, for as long as the distribution's cache policy says, and answers later requests for that file from the copy (a cache hit) instead of fetching it again (a cache miss).

### Origin access control

The CloudFront setting that makes the [distribution](#cloudfront-distribution) sign its requests to the bucket with AWS's request signing, so that the bucket's policy can allow that one distribution to read while refusing everyone else.

### CloudFormation stack

AWS CloudFormation creates AWS resources from a template, a YAML file that declares them, and keeps them together as a stack: deploying the template again changes the resources to match it.

### aptly

The program that builds the repository on this workstation: it keeps a database of packages under `~/.local/state/oaxaca/aptly`, and its `publish` writes the repository's two directories, `dists/` (the signed indexes apt reads first) and `pool/` (the `.deb` files and source packages), under `~/.local/state/oaxaca/aptly/public/`.

## Anatomy

| Piece | What it is | Command |
|---|---|---|
| `infra/apt-repo/apt-repo.yaml` | the [CloudFormation](#cloudformation-stack) template: the [bucket](#s3-bucket) (no listing, no public writes, plain HTTP refused, kept when the stack is deleted), the [distribution](#cloudfront-distribution) with its [origin access control](#origin-access-control), the TLS certificate for `apt.oaxaca.page` from AWS Certificate Manager, and the A and AAAA records for `apt.oaxaca.page` in the Route 53 hosted zone of `oaxaca.page` | |
| `scripts/apt-infra.sh` | looks up that hosted zone's ID, then runs the aws-cli's `cloudformation deploy` with the template as the stack `oaxaca-apt-repo` | `make apt-infra` (create or update), `make apt-infra-check` (validate, show the stack, change nothing) |
| `scripts/repo-publish.sh` | adds the newest version of each package in `build/` to [aptly](#aptly), keeps one version of each, publishes and signs, then uploads `public/` to the bucket with the aws-cli's `s3 sync` | `make publish` (shows what an upload would change), `make publish PUBLISH_FLAGS=--push` (uploads) |

The settings are in `distro.conf`, in shell syntax at the repository root:

- `APT_S3_BUCKET=oaxaca-apt` and `APT_S3_REGION=us-east-1`: the bucket. The region must be `us-east-1`, because CloudFront only uses certificates from that region and the whole stack lives in one region.
- `APT_DOMAIN=oaxaca.page`: the domain whose Route 53 hosted zone gets the records. The domain must be registered and its hosted zone must exist in the same AWS account; registering the domain through Route 53 creates the zone.
- `APT_HOST=apt.oaxaca.page` and `APT_URL=https://apt.oaxaca.page`: the repository's host name and URL. `make render` writes `APT_URL` into `packages/archive-keyring/archive.sources`, the sources entry `oaxaca-apt-source` installs.
- `APT_S3_PUBLIC_READ=true`: `true` lets anyone also read the bucket's own REST endpoint, `https://oaxaca-apt.s3.us-east-1.amazonaws.com`; `false` leaves the distribution as the bucket's only reader.
- `APT_AWS_PROFILE=personal`: the aws-cli profile, from `~/.aws/config`; the `AWS_PROFILE` environment variable overrides it.

## What CloudFront caches

The repository's two directories change differently, so the distribution treats them differently:

- **`dists/` is never cached** (AWS's managed `CachingDisabled` cache policy): every request goes to the bucket. `dists/stonking/InRelease` lists every index file in `dists/` with its size and SHA-256, and apt refuses an index whose hash differs. Each publish rewrites all of them, so an edge server holding an `InRelease` from one publish and a `Packages` file from another would make `apt update` fail with "Hash Sum mismatch".
- **`pool/` is cached** (AWS's managed `CachingOptimized` cache policy, one day by default): a file in `pool/` is named after its package's name, version and architecture, such as `pool/main/n/nwg-displays/nwg-displays_0.5.0-0oaxaca1_all.deb`. A new build has a new version and therefore a new file, and `make publish` refuses to upload different content under a name that is already published. A cached copy is therefore never out of date. That refusal has no override: an override would let an edge server keep serving the old file under the same name.

## Setting it up, once

1. The aws-cli installed, with the profile named in `APT_AWS_PROFILE` able to manage CloudFormation, S3, CloudFront, Certificate Manager and Route 53.
2. `APT_DOMAIN` registered, with its Route 53 hosted zone in the same account.
3. Create the stack:
   ```sh
   make apt-infra
   ```
   A first deploy waits until Certificate Manager has validated the certificate through a DNS record it adds to the hosted zone, and until CloudFront has rolled the distribution out. The last line printed is the repository URL, which must equal `APT_URL`.
4. Publish (next section).

## Publishing

```sh
make publish                         # sign locally, list what an upload would change
make publish PUBLISH_FLAGS=--push    # sign and upload
```

gpg asks for the apt signing key passphrase (the archive signing key's). The upload runs in three passes, `pool/` first, then `dists/`, then `pool/` again deleting what no index names, so a client never reads an index that names a missing file. Check from any machine:

```sh
curl -sI https://apt.oaxaca.page/dists/stonking/InRelease | head -1   # HTTP/2 200
```

## Why CloudFront, and the move to it

Until 2026-10-22 apt read the repository straight from the bucket's REST endpoint. That URL named the storage: the repository had already moved once, from GitHub Pages to S3 on 2026-10-13, and the move changed every installed system's sources entry. A host name in a domain of our own stays when the storage changes. S3 alone cannot serve our own name over HTTPS: AWS's documentation, "Website endpoints" (read 2026-10-13), says "Amazon S3 website endpoints do not support HTTPS or access points", and the REST endpoint presents only Amazon's own certificate. CloudFront serves the name with our certificate, and its edge servers answer repeated downloads of `pool/` files without the bucket.

The move happens in two phases, so a system whose sources entry still names the bucket keeps receiving updates until it has the new entry:

- **Phase A** (`APT_S3_PUBLIC_READ=true`): the distribution, certificate and records are added, the bucket stays readable at its REST endpoint, and `oaxaca-apt-source` 0.1.2 carries `https://apt.oaxaca.page`.
- **Phase B** (`APT_S3_PUBLIC_READ=false`, then `make apt-infra`), once every installed system has `oaxaca-apt-source` 0.1.2: the bucket policy keeps only the distribution's read, and S3's Block Public Access refuses any policy that would make the bucket public again. A system still naming the bucket after phase B gets 403 from it, and its sources entry, `/etc/apt/sources.list.d/oaxaca.sources`, needs `URIs: https://apt.oaxaca.page` written by hand.

Why GitHub Pages was left for S3: GitHub refuses files over 100 MB (`oaxaca-themes` is 111 MB, the fonts and desktop source tarballs 135 MB and 118 MB), and GitHub's "GitHub Pages limits" page says "Published GitHub Pages sites may be no larger than 1 GB"; the Pages checkout had already reached 758 MB. S3 has neither limit. Storage, requests and downloads are billed by AWS; see AWS's S3, CloudFront and Route 53 pricing pages for current prices.

## Teardown

Deleting the stack removes the distribution, the certificate and the records, and keeps the bucket and its contents (`DeletionPolicy: Retain` in the template). Removing the repository for good is two steps: delete the stack (`aws cloudformation delete-stack --stack-name oaxaca-apt-repo`), then empty and delete the bucket (`aws s3 rb s3://oaxaca-apt --force`).
