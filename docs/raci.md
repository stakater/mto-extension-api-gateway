# Ownership and RACI

Who owns what — **without** the extension (the copy-the-chart world the Template
replaces) and **with** it — and the split between the **platform team** and the
**application team**. The running example and terms are in `concepts.md`.

## Without the extension today (the copy-the-chart model)

The platform runs the shared pieces; each application team runs its own
gateways by **copying a Helm chart into its own repository** and keeping the
full values file, security switches included.

| Layer | Who owns it | How |
|---|---|---|
| Mesh (operator, control plane, mTLS, settings) | platform | GitOps, one set of values per cluster |
| Shared rate-limit service (+ Redis) and tiers | platform | GitOps, a platform namespace |
| Identity provider (realm, consumer clients, roles) | platform | a separate chart against the identity provider |
| Tenant namespaces and mesh/waypoint labels | platform | the `Tenant` object, through the Multi-Tenant Operator |
| **The gateway package** (gateway, routes, token checks, rate-limit hook, strip, telemetry, waypoint) | **each application team** | **a copy of the base chart in the team repo**, plus a full values file and a GitOps app per gateway |

What that costs — the failure modes this extension removes:

| # | Problem today |
|---|---|
| 1 | **N drifting copies of one chart.** A fix in the base chart is copied into every team repo by hand; versions diverge. |
| 2 | **Security is a switch in a team-editable values file.** `auth.enabled`, `allowGatewayAccessOnly`, `rateLimit.enabled` are plain toggles; one wrong value ships an **unauthenticated** or open-backend API, and nothing checks it. |
| 3 | **The consumer scope is free text.** Nothing stops `*` or a typo. |
| 4 | **Mesh/waypoint labels live outside the chart.** A gateway deploys "green" while a required label is missing, so it is silently out of the mesh. |
| 5 | **No single workflow for a new API.** Three owners (tenant labels, the identity-provider client, the gateway values) with no one object that means "I want a gateway". |
| 6 | **Upgrading every gateway is N manual jobs**, each team on its own schedule. |

## With the extension (the Template model)

The gateway chart becomes a platform-owned `Template`; a team instantiates it
with a short `TemplateInstance` (API-shaped parameters only). Security, the
rate-limit hook, `gw-only` and telemetry are inside the Template (ADR-0002); the
consumer scope is derived (ADR-0003); mesh/waypoint labels come from the
`Tenant` (ADR-0005).

**R** = does the work · **A** = owns the result · **C** = consulted ·
**I** = informed. The last column is what changes from the copy-the-chart model.

| Task | Platform team | Application team | Change from today |
|---|---|---|---|
| Mesh version and settings | R, A | I | same |
| Shared rate-limit service and tiers | R, A | C | same |
| Identity provider realm, consumer clients, roles | R, A | C | same (a seam to automate later, ADR-0009) |
| `Tenant`: namespaces and mesh/waypoint labels | R, A | C | same |
| **The gateway chart and the `Template`** | R, A | I | **moves to platform** (each team copied the chart today) |
| **Gateway security defaults** (token check, consumer authz, strip, `gw-only`, rate-limit hook, mTLS) | R, A | I | **moves to platform** (switches in each team's values today) |
| **Upgrading all gateways to a new version** | R, A | I | **moves to platform** (each team, by hand, today) |
| Create a gateway (a `TemplateInstance`) | C | R, A | same (the values file becomes a `TemplateInstance`) |
| Change a gateway (host, path, backend, tier) | I | R, A | same |
| Deploy and run the application | I | R, A | same |
| First-line troubleshooting (`401`/`403`/`429`, routing) | C | R, A | same |
| Mesh or `Template` problems | R, A | I | same |
| Promotion test → prod | C | R, A | same; process to define (`roadmap.md`) |

## What moves, and what stays

- **Moves to the platform:** the gateway chart, its security defaults, and its
  upgrades. These are exactly the things a team gets wrong or lets drift today.
- **Stays with the application team:** a team still **creates, changes and
  troubleshoots its own gateways** — it just can't weaken them, and it sets only
  API-shaped parameters. Self-service is unchanged; the footguns are gone.
- **The one-line test:** the only way a tenant gets an ingress gateway is a
  `TemplateInstance` of the platform's Template (ADR-0006). A hand-written
  gateway is refused.
