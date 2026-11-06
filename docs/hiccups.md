# Hiccups

Problems hit while building this project, the options considered, and what we went with. Newest at the bottom. Add an entry whenever something unexpected breaks.

| # | Problem | Status |
| --- | --- | --- |
| 1 | Storage data-plane 403 on a keyless account | Fixed |
| 2 | Role assignment 403 (Contributor cannot assign roles) | Worked around |
| 3 | `terraform output -raw` rejects the backend output | Fixed |
| 4 | `400 Request Too Long` on VNets and NSGs | Fixed with a service principal |

---

## 1. Storage data-plane 403 on a keyless account

**When:** applying `bootstrap/` (piece 2).

**Symptom:** the storage account was created, then Terraform failed waiting for the blob service:
`403 Key based authentication is not permitted on this storage account (KeyBasedAuthenticationNotPermitted)`.

**Cause:** the account has `shared_access_key_enabled = false` on purpose, but the azurerm provider still used account keys for data-plane calls.

**Options:**
- Turn shared keys back on (simple, but weakens the account).
- Tell the provider to use Azure AD for storage calls.

**Went with:** `storage_use_azuread = true` in the provider block of both `bootstrap/versions.tf` and `infra/versions.tf`.

**Side effect:** the failed step left the account marked *tainted*, so the next plan wanted to destroy and recreate it. Ran `terraform untaint azurerm_storage_account.state` first, and the plan became a harmless in-place update.

---

## 2. Role assignment 403 (Contributor cannot assign roles)

**When:** applying `bootstrap/` (piece 2).

**Symptom:** `AuthorizationFailed ... does not have authorization to perform action 'Microsoft.Authorization/roleAssignments/write'`.

**Cause:** the signed-in account has **Contributor** on the subscription. Contributor can create resources but cannot create role assignments, policy definitions, policy assignments or management groups. With shared keys off, reading and writing the state blob needs the *Storage Blob Data Contributor* role.

**Options:**
1. Get Owner or User Access Administrator and let Terraform assign the role.
2. Turn shared keys back on for the state account.
3. Give a service principal the role.

**Went with:** removed the `azurerm_role_assignment` from `bootstrap/main.tf` and granted the role manually. A comment in that file says so. Access was checked afterwards with `az storage blob list --auth-mode login`.

**Still applies:** piece 4 (pipeline identity) and piece 5 (policy, management groups) need the same missing permissions, so expect this limit again.

---

## 3. `terraform output -raw` rejects the backend output

**When:** reading the bootstrap output.

**Symptom:** `Unsupported value for raw output ... output value "backend_config" is object`.

**Cause:** `-raw` only prints strings, numbers and booleans, and Terraform treats this output as an object.

**Went with:** `terraform output -json backend_config`, then copied the four values into `infra/backend.hcl`. `infra/backend.hcl.example` shows the shape.

---

## 4. `400 Request Too Long` on VNets and NSGs

**When:** applying `infra/` (piece 3, hub-and-spoke network).

**Symptom:** every VNet and NSG failed with
`400 Bad Request - Request Too Long. The size of the request headers is too long.`
Resource groups and the storage account had worked earlier.

**Cause:** the Azure CLI login token is about 16,000 characters. Two claims make up roughly 10 KB of it: `groups` (133 group IDs) and `wids` (133 entries). The networking service enforces a header limit of about 16 KB, and the services behind the earlier successes are more lenient. Not a naming problem: the longest name is 26 characters against a 64 limit.

**Options:**
1. **Service principal for Terraform.** Its tokens carry no group list. Needs Contributor on the subscription, plus Storage Blob Data Contributor on the state account, both of which require permission to create role assignments (see hiccup 2).
2. Sign in as a different account that belongs to few groups.
3. Reduce the account's group memberships (tenant admin task). Check the list with
   `az ad user get-member-of --id $(az ad signed-in-user show --query id -o tsv) --query "[].displayName" -o tsv`.

**Why option 3 is out:** the account is a Global Administrator and holds many Entra directory roles, which is where the 133 `wids` come from, so trimming groups would not shrink the token enough.

**Went with:** option 1, a service principal. It also matches piece 4, where the pipeline authenticates with a federated identity (OIDC) and a small token. Retrying with the current login will not work, because the same token is sent every time.

**State of play:** the apply was partial. Some resources, probably the spoke resource groups, exist; the VNets, subnets, NSGs and peerings do not. Re-running `terraform plan` after the fix should show only what is left.

**Result:** applied successfully as the service principal. Checked in Azure afterwards: 3 VNets (`10.10.0.0/22`, `10.20.0.0/22`, `10.30.0.0/22`), 3 subnets, 2 NSGs and 4 peerings, all `Connected`. The state account also has the two role assignments the script made (Contributor on the subscription, Storage Blob Data Contributor on the state account).

**Checklist:**
- [x] Script and docs written: `scripts/create-service-principal.sh`, `docs/service-principal.md`, `infra/.env.example`.
- [x] Elevated access turned on, script run, elevated access turned off.
- [x] `source infra/.env`, then `terraform init -reconfigure` and `terraform plan` in `infra/`.
- [x] `terraform apply` complete.

**Note for later:** the pipeline in piece 4 should use a federated (OIDC) credential on this same identity or a new one, so the client secret can eventually be removed. The secret expires after one year.

## 5. Pull request plans can read the state (accepted risk)

**When:** piece 4, found by an automated security review of the pipeline.

**Issue:** the PR plan job signs in as the plan identity, which has Storage Blob Data Reader on the state account. A PR from a branch in this repo runs the workflow from that branch, so anyone with write access could change it to print the state. Fork PRs get no secrets and cannot do this.

**Options:**
1. Accept the risk and document it.
2. PRs run only validate and scan; plan runs on `main` after merge. No plan comment on the PR.
3. Federate the PR credential to an approval-gated `plan` environment (`environment:plan`). Keeps the comment but needs a click on every PR.

**Went with:** option 1. Only the owner has write access, the state holds network resources and no secrets, and the plan identity is read-only. The apply identity cannot be reached from a PR.

**Revisit when:** a collaborator gets write access, or a later piece puts secrets in state. Then move to option 3.

## 6. OIDC login rejected: "No matching federated identity record" (AADSTS700213)

**When:** first pipeline run, the plan job on a pull request.

**Symptom:** `AADSTS700213: No matching federated identity record found for presented assertion subject 'repo:sharifndlovu123@168600445/regulated-landing-zone@1436004487:pull_request'`.

**Cause:** the credentials were created with the subject `repo:sharifndlovu123/regulated-landing-zone:pull_request`, but GitHub now puts the immutable owner and repo IDs in the token subject. Azure compares the subject exactly, so nothing matched. Check with `gh api repos/<owner>/<repo>/actions/oidc/customization/sub`.

**Options:**
1. Keep the immutable format and update the credentials to match. It survives a repo rename and stops a recreated repo with the same name from inheriting access.
2. Switch the repo back to the old name-only subject through the same API.

**Went with:** option 1. The script now asks GitHub for the exact prefix and updates existing credentials whose subject differs. Needs a re-run with elevated access.

**Result (hiccup 6):** after re-running the script and re-running the failed job (the first attempt ran before Azure had applied the updated credentials), the full pipeline passed on `main`: validate, scan, plan, apply (approved on `dev`, 8 in-place tag changes) and verify. Piece 4 is complete.

## 7. Dependabot pull requests cannot sign in to Azure (expected)

**Symptom:** Dependabot PRs (action version bumps) fail at plan.

**Cause:** GitHub does not give Dependabot runs the normal Actions secrets. They have their own secret store, and the token subject is the same `pull_request`, but the `AZURE_*` secrets are empty.

**Options:** copy the secrets into Dependabot secrets (more places holding IDs), or accept that validate and scan are what Dependabot PRs are checked with and review the plan by hand.

**Went with:** not decided yet. Major version bumps (checkout 4 to 7, github-script 7 to 9, setup-terraform 3 to 4) should be reviewed before merging.
