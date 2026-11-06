# Tools used

Every tool, action and service this project relies on, with what it does here and where its own documentation lives. Updated each piece, so a tool appears once it is actually used.

## Infrastructure as code

| Tool | Used for | Piece | Docs |
| --- | --- | --- | --- |
| Terraform | Defines and deploys all resources | 1 | https://developer.hashicorp.com/terraform/docs |
| `azurerm` provider (~> 4.0) | Terraform's Azure resources | 1 | https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs |
| `azurerm` backend | Remote state in a storage account, signed in with Entra ID instead of keys | 2 | https://developer.hashicorp.com/terraform/language/backend/azurerm |

## Azure and GitHub command lines

| Tool | Used for | Piece | Docs |
| --- | --- | --- | --- |
| Azure CLI (`az`) | Login, creating identities and role assignments, checking resources | 2 | https://learn.microsoft.com/cli/azure |
| GitHub CLI (`gh`) | Sets repo secrets, variables and the `dev` environment from a script | 4 | https://cli.github.com/manual |

## Identity

| Tool | Used for | Piece | Docs |
| --- | --- | --- | --- |
| Microsoft Entra service principal | Terraform on a laptop (client secret), see [service-principal.md](service-principal.md) | 3 | https://learn.microsoft.com/entra/identity-platform/app-objects-and-service-principals |
| Workload identity federation (OIDC) | GitHub signs in to Azure with no stored secret, see [pipeline.md](pipeline.md) | 4 | https://learn.microsoft.com/entra/workload-id/workload-identity-federation |

## Pipeline: GitHub Actions

Workflow: [`.github/workflows/terraform.yml`](../.github/workflows/terraform.yml). Third-party actions are pinned to a commit SHA.

| Action | Used for | Docs |
| --- | --- | --- |
| `actions/checkout` | Gets the repo code onto the runner | https://github.com/actions/checkout |
| `actions/github-script` | Posts the plan as a pull request comment | https://github.com/actions/github-script |
| `hashicorp/setup-terraform` | Installs Terraform on the runner | https://github.com/hashicorp/setup-terraform |
| `azure/login` | Signs the Azure CLI in using OIDC, for the verify job | https://github.com/Azure/login |
| `terraform-linters/setup-tflint` | Installs tflint on the runner | https://github.com/terraform-linters/setup-tflint |
| `bridgecrewio/checkov-action` | Runs Checkov on the runner | https://github.com/bridgecrewio/checkov-action |

## Checks

| Tool | Used for | Config | Docs |
| --- | --- | --- | --- |
| `terraform fmt` / `validate` | Formatting and syntax | none | https://developer.hashicorp.com/terraform/cli/commands/fmt |
| tflint (+ azurerm ruleset) | Lints Terraform for mistakes `validate` misses, such as invalid VM sizes | [`.tflint.hcl`](../.tflint.hcl) | https://github.com/terraform-linters/tflint |
| Checkov | Security scan of the Terraform (open ports, missing encryption) | none | https://www.checkov.io/1.Welcome/What%20is%20Checkov.html |
| actionlint | Lints the workflow file (run locally, not in the pipeline) | none | https://github.com/rhysd/actionlint |
| Dependabot | Weekly pull requests to update pinned actions | [`.github/dependabot.yml`](../.github/dependabot.yml) | https://docs.github.com/code-security/dependabot |

## Documentation

| Tool | Used for | Docs |
| --- | --- | --- |
| Mermaid | Architecture diagrams in the README and docs | https://mermaid.js.org |
| mermaid-cli (`mmdc`) | Renders diagrams locally to check they parse (not committed) | https://github.com/mermaid-js/mermaid-cli |

## Coming in later pieces

Azure Policy and management groups (5), conftest for policy tests (5), Private DNS and private endpoints (6), Azure Firewall (7), Front Door and Azure Monitor (8).
