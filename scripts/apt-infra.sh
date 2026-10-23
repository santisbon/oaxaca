#!/usr/bin/env bash
# apt-infra.sh: create or update the AWS resources that serve the apt repository.
#
# Anatomy: the aws-cli's "cloudformation deploy" sends infra/apt-repo/apt-repo.yaml to AWS
# CloudFormation, which creates or updates the stack <id>-apt-repo in us-east-1: the bucket
# APT_S3_BUCKET that holds the repository's files, a CloudFront distribution that serves them at
# APT_HOST over HTTPS, the TLS certificate for APT_HOST, and the A and AAAA records that point
# APT_HOST at the distribution in the Route 53 hosted zone of APT_DOMAIN (all in distro.conf).
# This script looks up that hosted zone's ID by APT_DOMAIN, so no zone ID is kept in the source
# tree. APT_S3_PUBLIC_READ decides whether anyone besides CloudFront may read the bucket's own
# REST endpoint.
# Nothing on the distro's images or packages comes from here; the stack only serves the published
# repository (infra/apt-repo/README.md).
#
# Usage: scripts/apt-infra.sh [--check]
#   --check  validate the template with AWS and show the stack's state, change nothing
# Env:   AWS_PROFILE  the aws-cli profile (default APT_AWS_PROFILE in distro.conf)
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$here/distro.conf"
command -v aws >/dev/null || { echo "aws (the aws-cli) is not installed" >&2; exit 1; }
export AWS_PROFILE=${AWS_PROFILE:-$APT_AWS_PROFILE}
export AWS_REGION=$APT_S3_REGION
# The aws-cli would otherwise page its output through less.
export AWS_PAGER=""
stack="$DISTRO_ID-apt-repo"
template="$here/infra/apt-repo/apt-repo.yaml"

aws cloudformation validate-template --template-body "file://$template" >/dev/null
echo "== template valid: $template"
if [[ ${1:-} == --check ]]; then
  aws cloudformation describe-stacks --stack-name "$stack" \
    --query "Stacks[0].[StackStatus, Outputs[?OutputKey=='RepositoryUrl'].OutputValue | [0]]" --output text 2>/dev/null \
    || echo "stack $stack does not exist yet"
  exit 0
fi

zone=$(aws route53 list-hosted-zones-by-name --dns-name "$APT_DOMAIN" --max-items 1 \
  --query "HostedZones[?Name=='$APT_DOMAIN.' && Config.PrivateZone==\`false\`].Id | [0]" --output text)
[[ $zone == /hostedzone/* ]] || { echo "no public Route 53 hosted zone for $APT_DOMAIN in this account" >&2; exit 1; }
zone=${zone#/hostedzone/}

echo "== deploying stack $stack (bucket $APT_S3_BUCKET, host $APT_HOST, public read $APT_S3_PUBLIC_READ, region $APT_S3_REGION, profile $AWS_PROFILE)"
echo "   a first deploy waits for the certificate's DNS validation and the distribution's rollout"
aws cloudformation deploy --stack-name "$stack" --template-file "$template" \
  --parameter-overrides "BucketName=$APT_S3_BUCKET" "HostName=$APT_HOST" "HostedZoneId=$zone" \
  "PublicRead=$APT_S3_PUBLIC_READ" --no-fail-on-empty-changeset
url=$(aws cloudformation describe-stacks --stack-name "$stack" \
  --query "Stacks[0].Outputs[?OutputKey=='RepositoryUrl'].OutputValue" --output text)
echo "== repository URL: $url"
[[ $url == "$APT_URL" ]] || echo "!! distro.conf's APT_URL is $APT_URL, the stack says $url: make them agree" >&2
