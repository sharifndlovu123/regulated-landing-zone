# Service principal for Terraform

Terraform signs in as a **service principal** (an app identity) instead of your user account. The reason is in [hiccups.md](hiccups.md), entry 4: your user token is about 16 KB because it carries every group and directory role you hold, and Azure's networking service rejects requests that large. A service principal's token has none of that.

## What a service principal is (coming from AWS)

"Service principal", "app registration" and "enterprise application" are **the same identity seen through different pages of the console**. One identity, two linked objects in the tenant, created together when you run the script:

| Console page | What it is | What lives there |
| --- | --- | --- |
| **App registrations** | The *application object*: the identity's definition | Name, client ID (application ID), client secrets, federated credentials |
| **Enterprise applications** | The *service principal object*: the identity's instance in this tenant | The thing that actually signs in and receives permissions |

When someone says "give the service principal Contributor", they mean the enterprise application object. When you rotate a secret you do it on the app registration. Same identity, two views, which is why you find it in both places.

**Where it lives.** The identity belongs to the **tenant** (Microsoft Entra ID), not to a subscription. Its permissions are separate **role assignments** (Azure RBAC) that tie it to a scope: management group, subscription, resource group or single resource. Roles flow down the scope tree, never up, so a role on the storage account does not show on the subscription page. Entra's own "Roles and administrators" page is a different system (directory roles) and does not list Azure RBAC roles.

**AWS comparison.**

| Azure | Closest AWS idea |
| --- | --- |
| Service principal with a client secret | A dedicated IAM user with an access key: client ID is like the access key ID, client secret like the secret access key |
| Service principal with a federated credential (OIDC, used by the pipeline in piece 4) | An IAM role assumed through GitHub OIDC, with no stored secret |
| Managed identity | An IAM role attached to an EC2 instance or Lambda, with no secret to manage |
| Role assignment at a scope | A policy attached to the identity, but scoped to an account, OU or resource |
| Tenant | The organization or identity provider; the identity exists here, not inside one account |

A key difference from AWS: the identity is created once at the tenant level, and then you grant it roles per subscription. In AWS the IAM user or role normally lives inside one account.

## What it gets

| Role | Scope | Why |
| --- | --- | --- |
| Contributor | the subscription | create and change the landing zone resources |
| Storage Blob Data Contributor | the state storage account | read and write the Terraform state blob (shared keys are off) |

It is deliberately **not** Owner. Contributor cannot create role assignments, policy or management groups, so piece 4 and piece 5 will need extra, narrowly scoped roles later.

## One-time setup

Creating the service principal needs rights to create role assignments. Contributor cannot, so the Global Administrator turns on elevated access temporarily:

1. Entra admin center → **Identity → Overview → Properties** → **Access management for Azure resources** → **Yes** → Save.
2. Sign out and back in so the new rights are in your token:
   ```bash
   az logout && az login
   ```
3. Run the script from the project folder (use your own state account name):
   ```bash
   cd azure/regulated-landing-zone
   STATE_ACCOUNT=stlztf31860625 ./scripts/create-service-principal.sh
   ```
4. Turn **Access management for Azure resources** back to **No**, and sign out and in again. Elevation grants User Access Administrator across the whole tenant, so don't leave it on.

The script creates the app registration, issues a client secret (valid 1 year), assigns the two roles, and writes the credentials to `infra/.env` with mode 600. The secret is never printed. Re-running the script reuses the app and issues a fresh secret.

## Using it

```bash
cd azure/regulated-landing-zone/infra
source .env                       # loads ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID
terraform init -reconfigure -backend-config=backend.hcl
terraform plan
```

The azurerm provider and the backend both read the `ARM_*` variables and use them instead of your `az login` session. `terraform.tfvars` is still needed for `subscription_id` and `owner`.

To go back to your own login for a command, open a new shell without sourcing `.env`.

## Safety

- `infra/.env` is git-ignored. Only `infra/.env.example` (placeholders) is committed.
- Never paste the secret into chat, an issue or a commit.
- If it leaks, rotate it by re-running the script, which issues a new secret and invalidates nothing else.
- When the project is finished: `az ad app delete --id <client id>` removes the identity.
- Piece 4 replaces the secret for the pipeline with a federated credential (OIDC), so GitHub Actions needs no stored secret at all.
