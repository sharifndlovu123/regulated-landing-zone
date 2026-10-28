# Policy rollout

How this project ships Azure Policy changes without breaking running workloads or other teams' deployments. It explains two diagrams from the [README](../README.md): the CI/CD pipeline (Diagram 2) and the policy rollout (Diagram 3), and how they fit together.

## What "policy" means here

Azure Policy is a rule engine that Azure runs itself. A rule looks like "storage accounts must not allow public blob access" or "VMs may not have public IPs". Each rule has an *effect*:

| Effect | What it does |
| --- | --- |
| `audit` | Allows the resource, records that it breaks the rule |
| `deny` | Refuses to create the resource |
| `deployIfNotExists` | Automatically adds something, such as a diagnostic setting |

A **policy definition** is the written rule. In this project it is Terraform code in Git, so editing a rule is a normal pull request.

Two kinds of change live in this repo:

1. **Infrastructure**: networks, firewall, subnets.
2. **The rules themselves**: policy definitions.

Both go through the same pipeline, but rule changes get the extra care described below because a new `deny` rule can block other deployments or flag resources that already exist.

## Diagram 2: the general pipeline

Every commit follows: validate → scan → plan → approve → apply → verify.

| Step | When | What it checks |
| --- | --- | --- |
| **Scan** (Checkov, conftest) | Before deploy | The Terraform plan. Does the code look unsafe? |
| **Verify** | After deploy | The real environment, in two parts |

**Verify, part 1: policy compliance scan.** Ask Azure Policy which resources are non-compliant right now. If the answer is none, or only what you expected, the rules are active and nothing slipped through.

**Verify, part 2: connectivity test.** Prove the network behaves as designed:

- The app reaches the private endpoint through the firewall.
- The data spoke is *not* reachable from the internet.
- Private DNS names resolve to private IPs.

If verify fails, the pipeline rolls back by reverting the commit and applying the previous state.

## Diagram 3: shipping a rule safely

The rule: a new rule never goes straight to `deny`. It runs in `audit` first, you read what it would have broken, and only a clean scan promotes it.

Worked example. New rule: *storage accounts must disable public blob access.*

1. **PR changes the policy definition.** You write the rule.
2. **Unit test with conftest.** Feed sample resources into the Terraform plan (one good, one bad) and check the rule catches the bad one. This is cheap and happens before anything is deployed. It is an early check written in Rego, not Azure's own engine, so it tests your intent, not Azure's exact evaluation.
3. **Deploy in `audit` mode to the nonprod management group.** Azure evaluates the rule but blocks nothing.
4. **Compliance scan.** Azure lists the resources that would have broken. Say 3 existing storage accounts.
5. **Violations found?**
   - **Yes:** fix the code, or add an **exemption** with an owner and an expiry date (for example 30 days for one account you cannot fix yet). Then go back to step 3 and re-scan.
   - **No:** continue.
6. **Switch the effect to `deny` in prod.** This is itself a PR, so it runs through the Diagram 2 pipeline, including the compliance scan in Verify.
7. **Remediation task** (`deployIfNotExists` rules only). Those rules fix *new* resources automatically; existing ones need a one-off task to catch up.
8. **Nightly drift plan.** `terraform plan` runs every night. If someone changed something in the portal, the plan shows a difference and raises an alert.

Exemptions carry an owner and an expiry so a "temporary" hole cannot become permanent.

## How the two diagrams fit together

|  | Diagram 2 | Diagram 3 |
| --- | --- | --- |
| Scope | Any change | A change to a rule |
| Role of policy | The yardstick the deployment is measured against | The thing being changed |
| Question answered | "Did this change land safely?" | "Is this rule safe to enforce?" |

Diagram 3 is the rollout strategy for rules, wrapped around the general machinery of Diagram 2.

## Two layers, on purpose

- **Before deploy:** Checkov and conftest catch bad code in a pull request.
- **At deploy:** Azure Policy catches bad API calls, even from an admin clicking in the portal, which bypasses your pipeline.

You want both.

## What to build and write up

- [ ] Policy definitions in Terraform (`azurerm_policy_definition`) and an initiative grouping them.
- [ ] conftest tests with one good and one bad sample for each rule.
- [ ] Audit-mode assignment to a nonprod management group.
- [ ] A table of exemptions with owner and expiry date, and a check that flags expired ones.
- [ ] Nightly drift workflow that opens an issue when the plan is not empty.
- [ ] A write-up of one real rule going through the loop, with the numbers (violations found, fixed, exempted).
