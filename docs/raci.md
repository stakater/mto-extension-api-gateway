# Ownership and RACI

Who owns what — **without** this extension (the copy-the-chart world it
replaces) and **with** it — and the split between the **platform team** and the
**API team**. The running example and terms are in `concepts.md`; the problem
table is in `vision.md`. This doc is the detailed ownership view behind both.

## Without the extension today (the copy-the-chart model)

The platform runs the shared pieces; each API team runs its own gateways by
**copying a gateway Helm chart into its own repository**, keeping the full
values file — security switches included — and wiring header handling and rate
limits as `EnvoyFilter` patches.

| Layer | Who owns it | How |
|---|---|---|
| Service Mesh (operator, control plane, mTLS, settings) | platform | GitOps, one set of values per cluster |
| The Envoy rate-limit service (+ Redis) and tiers | platform | GitOps, a platform namespace |
| Identity provider (realm, clients, roles) | platform | a separate chart against the identity provider |
| Tenant namespaces and mesh labels | platform | the `Tenant`, through the Multi-Tenant Operator |
| **The gateway package** (gateway, routes, token checks, header `EnvoyFilter`s, rate-limit hook, backend lock) | **each API team** | **a copy of the base chart per team repo**, a full values file, a GitOps app **per API per environment** |

What that costs — the failure modes this extension removes (`vision.md`):

| # | Problem today |
|---|---|
| 1 | **Drifting copies of one chart.** A base-chart fix is copied into every team repo by hand; versions diverge. |
| 2 | **Security is a switch in a team-editable values file.** The token check, the backend lock and the rate limit are toggles; one wrong value ships an open API, and nothing checks it. |
| 3 | **The allowed-API rule is free text.** Nothing stops `api-*` or `*`. |
| 4 | **Header handling and rate limits are `EnvoyFilter` patches.** An Istio upgrade can break them silently; unsupported in production. |
| 5 | **One gateway per API per environment, at a fixed replica count.** Two APIs × three environments = six gateways, each running whether or not the API is called. |
| 6 | **Three owners, no single request.** Mesh labels, identity-provider roles and gateway values are owned separately; a gateway deploys "green" while a label is missing. |

## With the extension (one tenant gateway, `api` instances)

The gateway becomes a platform-defined, per-tenant `Gateway`: a team requests
it with one parameterless `TemplateInstance`, and Template Operator renders it
in the team's namespace (ADR-0002). An API team publishes an API with a
`TemplateInstance` of `api`, which renders its `HTTPRoute` (ADR-0005). The security baseline is
platform-rendered Istio policy plus three platform-owned, tested `EnvoyFilter`s
(ADR-0003, ADR-0004, proposed); the allowed-API rule is derived and
tenant-qualified (ADR-0006); the backend is locked with a `DENY` (ADR-0007);
mesh labels come from the `Tenant`.

**R** = does the work · **A** = owns the result · **C** = consulted ·
**I** = informed. The last column is what changes from the copy-the-chart model.

| Task | Platform team | API team | Change from today |
|---|---|---|---|
| Service Mesh version and settings | R, A | I | same |
| The rate limit service and its tiers | R, A | I | same service; the tiers become platform values, and the header and rate limit `EnvoyFilter`s become platform-owned and tested on each Istio upgrade (ADR-0003) |
| Identity provider realm, clients, `api.<tenant>.<api>.<tier>` roles | R, A | C | same (automated from the route later, G.11) |
| `Tenant`: namespaces and mesh labels | R, A | C | same |
| **The gateway charts and the Template** | R, A | I | **moves to platform** (each team copied the chart today) |
| **Request the tenant's gateway** (one parameterless `TemplateInstance`) | A | R | **new** — one request per tenant; the platform decides how the gateway runs (ADR-0002) |
| **Tune the gateway's team settings** (claim headers, correlation ID, access log, trace headers: annotations on the request) | C | R, A | **changed** — validated annotations instead of a values file (ADR-0012) |
| **The per-tenant gateway and its security baseline** (token check, allowed-API rule, header handling, rate limit, deny-by-default) | R, A | I | **moves to platform** (switches in each team's values today) |
| **Autoscaling the gateway** (HPA, PDB) | R, A | I | **new** — fixed replica counts per API today (ADR-0002) |
| **Upgrading every gateway** | R, A | I | **moves to platform** (each team, by hand, today) |
| Publish an API (a `TemplateInstance` of `api`) | C | R, A | **changed** — a copied values file becomes one `TemplateInstance` with checked parameters (ADR-0005) |
| Change an API (host, path, backend, route rules) | I | R, A | same |
| Deploy and run the application | I | R, A | same |
| First-line troubleshooting (`401`/`403`/`429`, routing) | C | R, A | same |
| Gateway, policy or Template problems | R, A | I | same |
| Promotion across environments | C | R, A | same; process to define (`roadmap.md`) |

## What moves, and what stays

- **Moves to the platform:** the gateway chart, its security baseline, the
  gateway's lifecycle and autoscaling, and all upgrades — exactly the things an
  API team gets wrong or lets drift today.
- **Stays with the API team:** a team still **publishes, changes and
  troubleshoots its own APIs** — now with one `api` `TemplateInstance`, not a
  chart copy, and with no switch for the token check, the API rule or the
  headers to get wrong. Self-service is unchanged; the
  footguns are gone.
- **The one-line test:** the only way a tenant exposes an API is an `api`
  `TemplateInstance`, which renders a route on its platform-owned gateway
  (ADR-0005, ADR-0008). An API can't remove the token check, the API rule or
  the header replacement; it can turn off only its own rate limit and backend
  lock, unless the platform locks the tenant.
