#!/usr/bin/env bash
# Creates the two identities the GitHub Actions pipeline signs in as (no client secrets: OIDC federation),
# gives each only the roles it needs, then sets the GitHub secrets/variables and the "dev" approval environment.
#
#   plan identity   Reader + Storage Blob Data Reader   - used on pull requests and main; cannot change anything
#   apply identity  Contributor + Storage Blob Data Contributor - only reachable from the "dev" environment (needs approval)
#
# Needs: az login as a user who can create app registrations AND role assignments (see docs/service-principal.md,
# turn on elevated access first), and `gh` logged in with admin rights on the repo. Safe to re-run.
set -euo pipefail

REPO="${GITHUB_REPO:-sharifndlovu123/regulated-landing-zone}"
GH_ENV="${GH_ENV:-dev}"
STATE_RG="${STATE_RG:-rg-tfstate-lz-san}"
STATE_ACCOUNT="${STATE_ACCOUNT:?set STATE_ACCOUNT, e.g. STATE_ACCOUNT=stlztf31860625}"
OWNER_TAG="${TF_OWNER:?set TF_OWNER, the value for the owner tag, e.g. TF_OWNER=sharif}"
ISSUER="https://token.actions.githubusercontent.com"

SUB_ID="$(az account show --query id -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"
STATE_SCOPE="$(az storage account show -g "$STATE_RG" -n "$STATE_ACCOUNT" --query id -o tsv)"

ensure_app() { # name -> prints appId; creates the app registration and its service principal if missing
  local name="$1" app
  app="$(az ad app list --display-name "$name" --query "[0].appId" -o tsv)"
  if [ -z "$app" ]; then
    app="$(az ad app create --display-name "$name" --query appId -o tsv)"
    az ad sp create --id "$app" -o none
  fi
  echo "$app"
}

ensure_federated() { # appId credentialName subject
  local app="$1" cred="$2" subject="$3"
  if [ "$(az ad app federated-credential list --id "$app" --query "[?name=='$cred'] | length(@)" -o tsv)" = "0" ]; then
    az ad app federated-credential create --id "$app" --parameters "{\"name\":\"$cred\",\"issuer\":\"$ISSUER\",\"subject\":\"$subject\",\"audiences\":[\"api://AzureADTokenExchange\"]}" -o none
  fi
}

assign() { az role assignment create --assignee "$1" --role "$2" --scope "$3" -o none; }

echo "Plan identity..."
PLAN_ID="$(ensure_app gha-landing-zone-plan)"
ensure_federated "$PLAN_ID" github-pull-request "repo:$REPO:pull_request"
ensure_federated "$PLAN_ID" github-main "repo:$REPO:ref:refs/heads/main"
assign "$PLAN_ID" "Reader" "/subscriptions/$SUB_ID"
assign "$PLAN_ID" "Storage Blob Data Reader" "$STATE_SCOPE"

echo "Apply identity..."
APPLY_ID="$(ensure_app gha-landing-zone-apply)"
ensure_federated "$APPLY_ID" "github-env-$GH_ENV" "repo:$REPO:environment:$GH_ENV"
assign "$APPLY_ID" "Contributor" "/subscriptions/$SUB_ID"
assign "$APPLY_ID" "Storage Blob Data Contributor" "$STATE_SCOPE"

echo "GitHub secrets and variables on $REPO..."
gh secret set AZURE_TENANT_ID --repo "$REPO" --body "$TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID --repo "$REPO" --body "$SUB_ID"
gh secret set AZURE_PLAN_CLIENT_ID --repo "$REPO" --body "$PLAN_ID"
gh secret set AZURE_APPLY_CLIENT_ID --repo "$REPO" --body "$APPLY_ID"
gh variable set TFSTATE_RG --repo "$REPO" --body "$STATE_RG"
gh variable set TFSTATE_ACCOUNT --repo "$REPO" --body "$STATE_ACCOUNT"
gh variable set TF_OWNER --repo "$REPO" --body "$OWNER_TAG"

echo "Approval environment '$GH_ENV' (you are the required reviewer, deployable from main only)..."
MY_ID="$(gh api user --jq .id)"
gh api -X PUT "repos/$REPO/environments/$GH_ENV" --input - >/dev/null <<JSON
{"prevent_self_review": false,
 "reviewers": [{"type": "User", "id": $MY_ID}],
 "deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
JSON
gh api -X POST "repos/$REPO/environments/$GH_ENV/deployment-branch-policies" -f name=main >/dev/null 2>&1 || true

echo
echo "Done. Plan identity: $PLAN_ID"
echo "      Apply identity: $APPLY_ID"
echo "Turn elevated access back off, then open a pull request to test the pipeline."
