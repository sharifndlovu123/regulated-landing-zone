# Hiccups

Problems hit while building this project, the options considered, and what we went with. Newest at the bottom. Add an entry whenever something unexpected breaks.

| # | Problem | Status |
| --- | --- | --- |
| 1 | Storage data-plane 403 on a keyless account | Fixed |
| 2 | Role assignment 403 (Contributor cannot assign roles) | Worked around |
| 3 | `terraform output -raw` rejects the backend output | Fixed |
| 4 | `400 Request Too Long` on VNets and NSGs | **In progress**, service principal set up |

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

**To do:**
- [x] Script and docs written: `scripts/create-service-principal.sh`, `docs/service-principal.md`, `infra/.env.example`.
- [ ] Turn on elevated access, run the script, turn elevated access off again.
- [ ] `source infra/.env`, then `terraform init -reconfigure` and `terraform plan` in `infra/`.
- [ ] `terraform apply`, then update this entry with the result.
