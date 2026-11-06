# Regulated Landing Zone

A hub-and-spoke Azure landing zone where every guardrail is code: private-only networking, firewall-inspected traffic, and Azure Policy that blocks non-compliant deployments before they exist.

### Build status

What exists in Azure today, what is written but not yet applied, and what is still to come. The finished design is Diagram 1 below. It is shown as two views: the network and state, then the governance that sits over it. Boxes are nested the way Azure nests them: resource group, then VNet, then subnet.

| Colour | Meaning |
| --- | --- |
| Green | Deployed in Azure |
| Yellow | Code written, not yet applied |
| Grey dashed | Still to build |
| Thick two-way line | VNet peering |

#### Network and state

```mermaid
flowchart LR
  ADM["Admin<br/>Azure portal, HTTPS"]:::planned
  FD["Front Door + WAF<br/>public entry point (piece 8)"]:::planned
  TF["Terraform in infra/<br/>runs as the service principal"]:::written

  subgraph SUB["Azure subscription - region: South Africa North"]
    subgraph RGS["Resource group: rg-tfstate-lz-san (bootstrap/)"]
      subgraph SA["Storage account: stlztf31860625"]
        CT[("Blob container: tfstate<br/>holds the Terraform state file")]:::deployed
      end
    end

    subgraph RGH["Resource group: rg-hub-lz-dev-san (infra/)"]
      subgraph HUBV["VNet: vnet-hub - 10.10.0.0/22"]
        FWS["Subnet: AzureFirewallSubnet<br/>10.10.0.0/24, reserved"]:::written
        FW["Azure Firewall + route table<br/>(piece 7, demo-only)"]:::planned
        BAS["Bastion<br/>(optional, demo-only)"]:::planned
      end
    end

    subgraph RGA["Resource group: rg-spoke-app-lz-dev-san (infra/)"]
      subgraph APPV["VNet: vnet-spoke-app - 10.20.0.0/22"]
        APPN["NSG: nsg-app<br/>subnet firewall rules"]:::written
        APPS["Subnet: snet-app<br/>10.20.0.0/24"]:::written
        APP["Flask app<br/>(piece 6)"]:::planned
        VM["VM Scale Set, no public IP<br/>(optional batch tier)"]:::planned
      end
    end

    subgraph RGD["Resource group: rg-spoke-data-lz-dev-san (infra/)"]
      subgraph DATAV["VNet: vnet-spoke-data - 10.30.0.0/22"]
        DATAN["NSG: nsg-data<br/>subnet firewall rules"]:::written
        DATAS["Subnet: snet-data<br/>10.30.0.0/24"]:::written
        PE["Private endpoints + Private DNS<br/>(piece 6)"]:::planned
      end
    end
  end

  HUBV <==>|"VNet peering"| APPV
  HUBV <==>|"VNet peering"| DATAV
  FWS -.-> FW
  APPN --- APPS
  DATAN --- DATAS
  APPS -.-> APP
  APPS -.-> VM
  DATAS -.-> PE
  ADM -.->|"TLS 443"| BAS
  BAS -.->|"SSH / RDP over peering"| VM
  FD -.->|"Private Link"| APP
  APP -.->|"routed via the hub firewall"| PE
  TF -.->|"reads and writes state"| CT
  TF -.->|"creates"| SUB

  classDef deployed fill:#d4edda,stroke:#2e7d32,color:#111
  classDef written fill:#fff3cd,stroke:#b8860b,color:#111
  classDef planned fill:#f2f2f2,stroke:#888,stroke-dasharray:4 3,color:#333
```

#### Governance (piece 5)

```mermaid
flowchart LR
  TEAM["Platform team (you)<br/>writes the rules as code in Git"]:::planned
  DEFN["Policy definitions + initiative<br/>Terraform code in policies/"]:::planned
  GH["GitHub Actions + OIDC<br/>CI/CD pipeline (piece 4)"]:::planned
  MG["Management group: mg-landingzone<br/>the scope rules are assigned at"]:::planned
  ARM["Azure Resource Manager<br/>checks every create or update request<br/>against the rules"]:::planned

  TEAM -->|"pull request"| DEFN
  DEFN -->|"applied by"| GH
  GH -->|"assigns at"| MG
  MG -->|"enforced by"| ARM

  R1["Rule: require tags<br/>owner, environment, cost-center"]:::planned
  R2["Rule: allowed region<br/>southafricanorth only"]:::planned
  R3["Rule: deny public blob access"]:::planned
  R4["Rule: deny public IPs"]:::planned
  R5["Rule: private endpoints only,<br/>public network access off"]:::planned

  ARM --> R1 & R2 & R3 & R4 & R5

  T1["Every resource group"]:::planned
  T2["Every deployment in the subscription"]:::planned
  T3["Storage accounts, including the state account"]:::planned
  T4["VNets: app and data spokes"]:::planned
  T5["Private endpoints in the data spoke"]:::planned

  R1 -.->|"acts on"| T1
  R2 -.->|"acts on"| T2
  R3 -.->|"blocks public access on"| T3
  R4 -.->|"blocks public IPs in"| T4
  R5 -.->|"requires"| T5

  classDef planned fill:#f2f2f2,stroke:#888,stroke-dasharray:4 3,color:#333
```

Piece 2 is applied (remote state storage) and the hub resource group exists. The hub-and-spoke network (piece 3) is written and waiting for `terraform apply`. Governance is not started.

**Who controls the guardrails.** The platform team writes the rules as Terraform in Git and changes them only by pull request. The pipeline assigns them to the management group, and Azure Resource Manager (Azure's own control plane) then checks every create or update request against them, whatever tool or person sent it. See [docs/policy-rollout.md](docs/policy-rollout.md) for how a rule is rolled out safely.

**Permissions.** Creating policy definitions, policy assignments and management groups needs rights that the Contributor role does not include (for example Resource Policy Contributor, or Owner). Piece 5 depends on getting those. Terraform itself runs as a service principal; see [docs/service-principal.md](docs/service-principal.md).

| Term | What it is |
| --- | --- |
| **Resource group** | A folder for related Azure resources. Deleting it deletes everything inside. |
| **VNet** (virtual network) | A private network with its own IP range. Nothing outside can reach it unless you connect it. |
| **Subnet** | A slice of a VNet's IP range. Resources are placed in a subnet. |
| **NSG** (network security group) | A set of allow/deny rules attached to a subnet. |
| **VNet peering** | A private link between two VNets. Works in one direction only, so each link needs one on each side, and it is not transitive. |
| **Hub / spoke** | The hub holds shared services (firewall). Spokes hold workloads and talk to each other only through the hub. |
| **Storage account / blob container** | The account is the top-level storage resource. A container inside it holds files, here the Terraform state. |
| **Private endpoint** | A private IP inside your subnet that points at an Azure service such as SQL or Key Vault, so it needs no public address. |
| **Management group** | A level above subscriptions. Rules assigned to it apply to every subscription under it. |
| **Azure Policy** | Rules Azure itself enforces on resources: audit, deny, or auto-fix. |
| **Azure Resource Manager** | The Azure control plane that every create, update or delete request passes through. This is where policy is checked. |

### Business use case

A South African bank, insurer or municipality moving workloads into South Africa North has to show POPIA-minded controls: no public endpoints, encryption everywhere, logging on, region locked. Today auditors get spreadsheets. Here they get a live policy compliance report and a Git history of every change.

### The hard piece

Policy-as-code plus zero-trust networking

### Rough monthly cost, ZAR

R300 to R900 a month if you apply for a few hours and destroy. Left running, Azure Firewall alone is roughly R5,000 a month, so keep it in a module you apply only for sessions and demos.

### Tool stack

- Terraform (azurerm + AzAPI)
- Azure Landing Zone / Verified Modules
- Management groups
- Azure Policy + initiatives
- Defender for Cloud
- Azure Firewall
- Hub-spoke VNet peering
- Private Endpoints + Private DNS
- Private DNS Resolver
- Bastion
- Front Door + WAF
- Log Analytics
- GitHub Actions + OIDC
- Checkov
- conftest (OPA)
- tflint

### Diagrams

#### Diagram 1 · Architecture: hub, spokes and governance

```mermaid
flowchart LR
  U["Users and partners"] -->|"HTTPS"| FD["Front Door + WAF<br/>global edge"]
  subgraph SAN["South Africa North - Johannesburg - 3 AZs"]
    subgraph HUB["Hub VNet"]
      GW["VPN gateway"]
      FW["Azure Firewall<br/>egress + east-west rules"]
      DNSR["Private DNS Resolver"]
      DNSZ["Private DNS zones<br/>privatelink.*"]
      BAS["Bastion<br/>browser-based SSH / RDP"]
    end
    subgraph APPV["Spoke: prod-app VNet"]
      APP["App Service or AKS<br/>VNet integrated"]
      VM["VM Scale Set<br/>batch tier, no public IP"]
    end
    subgraph DATAV["Spoke: prod-data VNet"]
      PE["Private endpoints<br/>SQL, Storage, Key Vault"]
    end
  end
  ONP["Office or on-prem"] ==>|"site-to-site VPN"| GW
  FD -->|"Private Link origin"| APP
  APP -->|"UDR 0.0.0.0/0"| FW
  FW -->|"allowed flows only"| PE
  GW --> FW
  HUB <==>|"VNet peering"| APPV
  HUB <==>|"VNet peering"| DATAV
  ADM["Admin<br/>Azure portal, HTTPS"] -->|"TLS 443"| BAS
  BAS -->|"SSH / RDP over VNet peering"| VM
  ONP -->|"DNS queries for privatelink names"| DNSR
  DNSR --> DNSZ
  DNSZ -.->|"resolves names to private IPs"| PE
  subgraph GOV["Tenant governance"]
    MG["Management groups"] --> POL["Azure Policy<br/>deny, audit, deployIfNotExists"]
    POL --> DEF["Defender for Cloud<br/>compliance score"]
  end
  POL -.->|"blocks public IPs, public blob, wrong region"| SAN
```

> **How to read this:** The hub is joined to each spoke by VNet peering, which is what lets traffic cross between networks; spokes are not peered to each other, so app-to-data traffic must go through the hub firewall. A user hits Front Door, which reaches the app spoke over Private Link, so the app never needs a public IP. When the app calls the database, a user-defined route sends the packet through the hub firewall, and only then does it reach the private endpoint in the data spoke. Admins never get a public IP or an open SSH port: they sign in through the Azure portal, and Bastion opens the session to the VM over VNet peering. Office machines resolve private names (for example a database) through the DNS Resolver, which answers from the Private DNS zones with the private endpoint's address. The dotted line is governance: Azure Policy sits above all of it and rejects a deployment that breaks the rules.

#### Diagram 2 · CI/CD: landing zone changes

```mermaid
flowchart LR
  A["Commit or pull request"] --> B["Validate<br/>terraform fmt, validate, tflint"]
  B --> C["Scan<br/>Checkov and conftest on the plan"]
  C --> D["Plan<br/>terraform plan posted on the PR"]
  D --> E{"Approval gate<br/>prod environment needs 2 reviewers"}
  E -->|"approved"| F["Deploy<br/>terraform apply, federated OIDC identity"]
  F --> G["Verify<br/>policy compliance scan and connectivity test"]
  G -->|"pass"| H["Promote to next environment"]
  G -->|"fail"| R["Rollback<br/>revert commit, apply previous state"]
  R --> K["Last known good state restored"]
  E -->|"rejected"| X["Stop and comment on the PR"]
```

> **How to read this:** Follow the top line from a commit to a deploy: the pipeline stops at the first red step, and nothing reaches the approval gate unless validation, scanning and the plan all passed. The bottom branch is the one hiring managers ask about: when verification fails, the rollback box puts the environment back without a human editing the console. Here the scan step also runs your custom policy tests, so a policy change is tested like application code.

#### Diagram 3 · Hard piece: shipping a policy safely

```mermaid
flowchart LR
  A["PR changes a policy definition"] --> B["Unit test<br/>conftest on the Terraform plan"]
  B --> C["Deploy initiative in audit mode<br/>to the nonprod management group"]
  C --> D["Compliance scan<br/>list non-compliant resources"]
  D --> E{"Violations found?"}
  E -->|"yes"| F["Fix the code, or add an exemption<br/>with owner and expiry date"]
  F --> C
  E -->|"no"| G["Switch effect to deny in prod"]
  G --> H["Remediation task for<br/>deployIfNotExists rules"]
  H --> I["Nightly drift plan<br/>alerts if portal changes appear"]
```

> **How to read this:** A new rule never goes straight to deny. It runs in audit mode first, you read what it would have broken, and only a clean scan promotes it. The loop on the left is the part to write about in your README: exemptions carry an owner and an expiry so they cannot become permanent holes.

### How it covers the five focus areas

- **Compute** (light): Workload spoke runs App Service (VNet integrated) or a small AKS cluster; a VM Scale Set bastion-fronted batch tier shows autoscale. Policy denies public IPs on VMs and restricts SKUs to an approved list.
- **Networking · HOME**: Hub-and-spoke with a user-defined route (0.0.0.0/0) to Azure Firewall, NSGs plus application security groups, private endpoints for SQL, Storage and Key Vault, Private DNS zones linked to the hub, DNS resolver for on-prem name lookups, Front Door with a Private Link origin.
- **Storage** (light): Policy enforces secure transfer, no public blob access and customer-managed keys in Key Vault. Diagnostic logs land in a storage account with an immutability policy.
- **CI/CD** (deep): Plan on PR, conftest policy tests, environment approvals, federated identity (no stored secrets), nightly drift detection with an issue opened automatically.
- **Cost optimisation** (light): Tags required and inherited by policy, a budget per spoke, firewall applied on a schedule, dev spokes auto-shutdown.
### Advanced features that show depth

- Custom policy definitions with DeployIfNotExists that attach diagnostic settings to every new resource
- Policy exemptions that expire, tracked in a table so reviews are not forgotten
- Split-horizon Private DNS: the same name resolves privately inside the VNets and publicly outside
- Privileged Identity Management for owner access and a documented break-glass account
- Map your initiative to ISO 27001 or the CIS benchmark and write down which control supports which POPIA condition

### Production-like touches

- Three subscriptions as environments: platform, nonprod, prod
- Alerts on non-compliance spikes and firewall deny bursts
- Runbook: add a new spoke in under 30 minutes
- Post-incident write-up: an app outage caused by a Private DNS zone that was never linked to the spoke
- Architecture decision records and the diagrams kept as code in the repo

### AWS to Azure bridge

| AWS | Azure | Where it trips up AWS engineers |
| --- | --- | --- |
| Organizations + SCPs | Management groups + Azure Policy | Policy can also fix things (deployIfNotExists). RBAC is a separate system from Policy. |
| Transit Gateway | Hub VNet + peering (or Virtual WAN) | Peering is not transitive. Traffic only crosses spokes if it passes a firewall with routes you write. |
| Security group | NSG | NSGs have numbered priorities and a default rule that allows VNet-to-VNet traffic. It is not default-deny inside the VNet. |
| VPC endpoint / PrivateLink | Private Endpoint | You must also create and link the privatelink Private DNS zone, or the name still resolves to a public IP. This breaks more first deployments than anything else. |
| IAM Identity Center | Entra ID + PIM | Identity lives in the tenant, not the subscription. Roles are assigned at a scope and inherit downwards. |
| Network Firewall | Azure Firewall | Billed every hour it exists. Destroy it between sessions. |
