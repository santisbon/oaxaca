#!/usr/bin/env bash
# budget-infra.sh: create or update the AWS account's monthly cost budget and its email alerts.
#
# Anatomy: the aws-cli's "cloudformation deploy" sends infra/budget/budget.yaml to AWS
# CloudFormation, which creates or updates the stack <id>-budget in us-east-1: one AWS Budgets
# budget of BUDGET_LIMIT_USD (distro.conf) a month for the whole account, emailing BUDGET_EMAIL when
# the month's actual cost passes 80% and 100% of the limit and when the forecast passes 100%
# (docs/7, choice 60). The address comes from the environment so that it is never written into the
# source tree; the template marks it NoEcho, so CloudFormation does not show it either.
#
# Usage: BUDGET_EMAIL=<address> scripts/budget-infra.sh   (make budget-infra)
#        scripts/budget-infra.sh --check   validate the template and show the stack's state, change nothing
# Env:   AWS_PROFILE  the aws-cli profile (default APT_AWS_PROFILE in distro.conf)
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$here/distro.conf"
command -v aws >/dev/null || { echo "aws (the aws-cli) is not installed" >&2; exit 1; }
export AWS_PROFILE=${AWS_PROFILE:-$APT_AWS_PROFILE}
export AWS_REGION=$APT_S3_REGION
export AWS_PAGER=""
stack="$DISTRO_ID-budget"
template="$here/infra/budget/budget.yaml"

aws cloudformation validate-template --template-body "file://$template" >/dev/null
echo "== template valid: $template"
if [[ ${1:-} == --check ]]; then
  aws cloudformation describe-stacks --stack-name "$stack" \
    --query "Stacks[0].[StackStatus, Outputs[?OutputKey=='BudgetName'].OutputValue | [0]]" --output text 2>/dev/null \
    || echo "stack $stack does not exist yet"
  exit 0
fi

[[ -n ${BUDGET_EMAIL:-} ]] || { echo "set BUDGET_EMAIL to the address the alerts go to: BUDGET_EMAIL=<address> make budget-infra" >&2; exit 1; }
echo "== deploying stack $stack (limit \$$BUDGET_LIMIT_USD a month, profile $AWS_PROFILE)"
aws cloudformation deploy --stack-name "$stack" --template-file "$template" \
  --parameter-overrides "LimitUsd=$BUDGET_LIMIT_USD" "Email=$BUDGET_EMAIL" --no-fail-on-empty-changeset
acct=$(aws sts get-caller-identity --query Account --output text)
name=$(aws cloudformation describe-stacks --stack-name "$stack" --query "Stacks[0].Outputs[?OutputKey=='BudgetName'].OutputValue" --output text)
aws budgets describe-budget --account-id "$acct" --budget-name "$name" \
  --query 'Budget.[BudgetName, BudgetLimit.Amount, BudgetLimit.Unit, TimeUnit]' --output text | sed 's/^/== budget: /'
aws budgets describe-notifications-for-budget --account-id "$acct" --budget-name "$name" \
  --query 'Notifications[].[NotificationType, Threshold]' --output text | sed 's/^/   alert: /'
