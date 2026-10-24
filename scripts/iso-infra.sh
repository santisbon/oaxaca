#!/usr/bin/env bash
# iso-infra.sh: create or update the AWS resources that serve the installation ISO.
#
# Anatomy: the aws-cli's "cloudformation deploy" sends infra/iso/iso-host.yaml to AWS
# CloudFormation, which creates or updates the stack <id>-iso in us-east-1: the bucket
# ISO_S3_BUCKET that holds the ISOs, a CloudFront distribution that serves them at ISO_HOST over
# HTTPS and is the bucket's only reader, the TLS certificate for ISO_HOST, and the A and AAAA
# records that point ISO_HOST at the distribution in the Route 53 hosted zone of APT_DOMAIN (all in
# distro.conf). This script looks up that hosted zone's ID by APT_DOMAIN, so no zone ID is kept in
# the source tree. scripts/iso-publish.sh fills the bucket (docs/7, choice 59).
#
# Usage: scripts/iso-infra.sh [--check]
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
stack="$DISTRO_ID-iso"
template="$here/infra/iso/iso-host.yaml"

aws cloudformation validate-template --template-body "file://$template" >/dev/null
echo "== template valid: $template"
if [[ ${1:-} == --check ]]; then
  aws cloudformation describe-stacks --stack-name "$stack" \
    --query "Stacks[0].[StackStatus, Outputs[?OutputKey=='DownloadsUrl'].OutputValue | [0]]" --output text 2>/dev/null \
    || echo "stack $stack does not exist yet"
  exit 0
fi

zone=$(aws route53 list-hosted-zones-by-name --dns-name "$APT_DOMAIN" --max-items 1 \
  --query "HostedZones[?Name=='$APT_DOMAIN.' && Config.PrivateZone==\`false\`].Id | [0]" --output text)
[[ $zone == /hostedzone/* ]] || { echo "no public Route 53 hosted zone for $APT_DOMAIN in this account" >&2; exit 1; }
zone=${zone#/hostedzone/}

echo "== deploying stack $stack (bucket $ISO_S3_BUCKET, host $ISO_HOST, region $APT_S3_REGION, profile $AWS_PROFILE)"
echo "   a first deploy waits for the certificate's DNS validation and the distribution's rollout"
aws cloudformation deploy --stack-name "$stack" --template-file "$template" \
  --parameter-overrides "BucketName=$ISO_S3_BUCKET" "HostName=$ISO_HOST" "HostedZoneId=$zone" \
  --no-fail-on-empty-changeset
url=$(aws cloudformation describe-stacks --stack-name "$stack" \
  --query "Stacks[0].Outputs[?OutputKey=='DownloadsUrl'].OutputValue" --output text)
echo "== downloads URL: $url"
[[ $url == "$ISO_URL" ]] || echo "!! distro.conf's ISO_URL is $ISO_URL, the stack says $url: make them agree" >&2
