#!/usr/bin/env bash
# apt-infra.sh: create or update the S3 bucket that serves the apt repository.
#
# Anatomy: the aws-cli's "cloudformation deploy" sends infra/apt-repo/bucket.yaml to AWS
# CloudFormation, which creates or updates the stack <id>-apt-repo: one bucket (APT_S3_BUCKET in
# distro.conf, in APT_S3_REGION) that anyone can read over HTTPS and nobody can list or write
# without credentials, and its bucket policy. Nothing on the distro's images or packages comes from
# here; the stack only holds the published repository (infra/apt-repo/README.md).
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
stack="$DISTRO_ID-apt-repo"
template="$here/infra/apt-repo/bucket.yaml"

aws cloudformation validate-template --template-body "file://$template" >/dev/null
echo "== template valid: $template"
if [[ ${1:-} == --check ]]; then
  aws cloudformation describe-stacks --stack-name "$stack" \
    --query 'Stacks[0].[StackStatus, Outputs[0].OutputValue]' --output text 2>/dev/null \
    || echo "stack $stack does not exist yet"
  exit 0
fi

echo "== deploying stack $stack (bucket $APT_S3_BUCKET, region $APT_S3_REGION, profile $AWS_PROFILE)"
aws cloudformation deploy --stack-name "$stack" --template-file "$template" \
  --parameter-overrides "BucketName=$APT_S3_BUCKET" --no-fail-on-empty-changeset
url=$(aws cloudformation describe-stacks --stack-name "$stack" \
  --query "Stacks[0].Outputs[?OutputKey=='RepositoryUrl'].OutputValue" --output text)
echo "== repository URL: $url"
[[ $url == "$APT_URL" ]] || echo "!! distro.conf's APT_URL is $APT_URL, the stack says $url: make them agree" >&2
