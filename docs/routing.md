# Routing through the firewall

How traffic from the spokes is forced through the hub firewall using a user-defined route (UDR) for `0.0.0.0/0`. This is the "UDR 0.0.0.0/0" line in Diagram 1 of the [README](../README.md). The route tables are added in piece 7, together with the firewall.

## What `0.0.0.0/0` means

`0.0.0.0/0` matches every address. Azure always prefers the **most specific** matching route (longest prefix match), so `0.0.0.0/0` only catches traffic that no other route matches.

Every subnet starts with **system routes** from Azure. The relevant ones:

- Traffic to the subnet's own VNet, or a peered VNet, goes directly there.
- Everything else (`0.0.0.0/0`) goes to the **internet**.

A **route table** adds your own rules to a subnet. Ours has one:

| Prefix | Next hop type | Next hop address |
| --- | --- | --- |
| `0.0.0.0/0` | Virtual appliance | the firewall's private IP in the hub, for example `10.10.0.4` |

It has the same prefix as the system "to the internet" route, and a user route wins a tie, so the default route now points at the firewall.

## The path of a packet

A workload in the app spoke calls an external API, or a database in the data spoke:

```
workload (snet-app, 10.20.0.0/24)
   │  route lookup: not in my VNet, and no peering route covers it
   │  matches 0.0.0.0/0, next hop = firewall 10.10.0.4
   ▼
VNet peering, app to hub            needs allow_forwarded_traffic = true
   ▼
Azure Firewall (hub)                checks its rules: allow, or drop and log
   ├─► internet                     firewall replaces the source with its own public IP
   └─► data spoke private endpoint  through the hub-to-data peering
```

The workload never reaches the internet or the database directly. Every outbound flow passes the firewall, which gives one place to allow or deny it and one log of everything.

## Why spoke-to-spoke traffic reaches the firewall

The app and data spokes are **not peered to each other**, so the app subnet has no system route for `10.30.0.0/22`. That traffic falls through to `0.0.0.0/0` and lands on the firewall. If the spokes were peered directly, the more specific peering route would win and the firewall would be bypassed. VNet peering is not transitive, which is the main difference from AWS Transit Gateway.

## Details that catch people out

1. **The reply needs a UDR too.** The data spoke also needs a route table sending `0.0.0.0/0` to the firewall. Otherwise its replies go towards the internet and the connection hangs. The firewall tracks connections, so a request and its reply must both pass through it.
2. **Peering must allow forwarded traffic** on the spoke-to-hub side. `network.tf` already sets `allow_forwarded_traffic = true`.
3. **No firewall rule means no traffic.** A UDR with a missing or too-narrow rule drops packets silently. When something hangs, check the firewall log first.
4. **Spokes have no implicit internet access.** The spoke subnets set `default_outbound_access_enabled = false`, so the firewall is the only way out.

## AKS and App Service

- **AKS** has an outbound type called *user-defined routing*. It is set when the cluster is created, and the subnet's route table must already exist. Otherwise AKS builds its own public load balancer for egress, which defeats the point.
- AKS nodes must reach some Microsoft endpoints to work at all (image registry, control plane). The firewall must allow them, usually with the built-in `AzureKubernetesService` FQDN tag. If this is missing, nodes stay `NotReady`.
- **App Service** does not use route tables in the same way. It has a "route all traffic" setting on its VNet integration, which sends outbound traffic into the VNet so the same route table applies.

## Cost

Sending everything through a central firewall gives control and one audit log, but the firewall bills by the hour and per GB processed. That is why it is a demo-only module (see the cost note in the README).

## What to build

- [ ] `azurerm_firewall` with a policy, in the hub's `AzureFirewallSubnet`.
- [ ] `azurerm_route_table` per spoke with the `0.0.0.0/0` route to the firewall's private IP.
- [ ] `azurerm_subnet_route_table_association` for `snet-app` and `snet-data`.
- [ ] Firewall rules: allow app to data on the database port, allow the AKS FQDN tag, deny everything else.
- [ ] A connectivity test in the pipeline (see Diagram 2): app can reach the private endpoint, and the data spoke is unreachable from the internet.
- [ ] A write-up of one blocked flow found in the firewall log.
