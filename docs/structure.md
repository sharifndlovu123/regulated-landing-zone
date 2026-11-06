# Subscription and resource group structure

How this project divides Azure into subscriptions and resource groups, how that maps to Microsoft's recommended landing zone pattern, and where the portfolio version deliberately takes a shortcut.

## The four boundaries

| Boundary | Used for |
| --- | --- |
| **Subscription** | **Environment** (prod, non-prod), and often one per workload team |
| **Management group** | Grouping subscriptions so policy and RBAC are assigned once and inherited |
| **Resource group** | **Lifecycle and ownership**: resources that are deployed, updated and deleted together |
| **Tags** | Filtering and reporting: cost centre, owner, environment |

The standard guidance (Cloud Adoption Framework, Azure Landing Zone reference architecture) is that **environments are separated by subscription, not by resource group**.

## Why subscriptions separate environments

- **Access:** someone with Contributor on dev cannot touch prod. In one shared subscription, a single wrong role assignment at subscription scope reaches everything.
- **Policy:** prod can enforce `deny` rules while dev stays on `audit`, assigned at different management groups (see [policy-rollout.md](policy-rollout.md)).
- **Blast radius:** quotas, limits and throttling are per subscription, so a runaway dev deployment cannot use up prod's quota.
- **Billing:** cost separates cleanly by subscription.
- **Tags are not a security boundary.** They are good for filtering a cost report and useless for stopping anyone doing anything.

A resource group per environment (`rg-myapp-dev`, `rg-myapp-prod`) is common and fine for one small workload. It stops being enough when prod needs different access or policy from dev, which is the scenario this project models.

## How resource groups are split here

By **function, owner and lifecycle**, using the rule of thumb "would I delete these together?"

| Resource group | Holds | Why separate |
| --- | --- | --- |
| `rg-hub-lz-dev-san` | Hub VNet, firewall subnet, later the firewall | Shared network owned by the platform team, lives for years |
| `rg-spoke-app-lz-dev-san` | App spoke VNet, subnet, NSG, workload | Owned by an app team, changes often |
| `rg-spoke-data-lz-dev-san` | Data spoke VNet, subnet, NSG, private endpoints | Different owner and access rules from the app |
| `rg-tfstate-lz-san` | Terraform state storage | Must outlive everything it describes, deployed by `bootstrap/` |

The environment is in the name (`lz-dev-san`), and `environment` is a variable that accepts only `dev`, `nonprod` or `prod`. The region is also in the name, but a resource group's location is only where its metadata is stored. Resources inside can be in other regions.

## Portfolio vs production

| | This portfolio | Production |
| --- | --- | --- |
| Subscriptions | **One**, for cost and simplicity | Separate for connectivity (hub), prod and non-prod, usually one per workload |
| Management groups | Added in piece 5, if the account allows | Platform, landing zones, sandbox, decommissioned |
| Resource groups | Four, split by function | Per workload per environment, plus shared network and monitoring groups |
| Environment separation | Name and variable only | Subscription boundary |

The code is ready to move: nothing hard-codes a subscription, `environment` and the names already carry the environment, and spokes are a map in `var.spokes`, so a spoke can be added or moved without restructuring.

## Rules of thumb

- **Same lifecycle, same owner, same resource group.** A network that outlives the apps on it goes in its own group.
- **Do not split just to filter.** Use tags and the portal's filters to find things.
- **Resource groups are also scopes** for RBAC, policy, locks and cost views, so split when you need a different setting on a subset.
- **Never use a resource group as the prod/dev wall.** Use a subscription.
