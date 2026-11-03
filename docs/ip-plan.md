# IP plan

Non-overlapping ranges, so any network can be peered with any other later (including on-prem over VPN).

| Network | Range | Subnets |
| --- | --- | --- |
| Hub | `10.10.0.0/22` | `10.10.0.0/24` AzureFirewallSubnet (reserved) |
| Spoke: app | `10.20.0.0/22` | `10.20.0.0/24` snet-app |
| Spoke: data | `10.30.0.0/22` | `10.30.0.0/24` snet-data (private endpoints) |

Each /22 holds four /24 subnets; only the first is used so far. New spokes take the next free `10.x0.0.0/22`, for example `10.40.0.0/22`.
