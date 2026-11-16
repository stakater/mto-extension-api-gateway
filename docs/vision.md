# Vision

## The verdict first

**Question (Rasheed Amir, 2026-11-16):** how would an API gateway extension
look, and what value would it bring?

**Answer: the value is real, but it is governance and a golden path, not the
usual "every tenant gets a scoped login".** The reference architecture this is
drawn from is already running in production: dozens of per-API ingress gateways
on OpenShift Service Mesh 3 (ambient), each an Envoy proxy that validates a
token, authorizes the caller against the API, rate-limits it, and forwards to
the application over mTLS. The platform team owns the mesh and a shared
rate-limit service; each team deploys its own gateways by **copying a Helm
chart into its own repository**. That copy is where the value — and the problem
— sits.

| What a per-API gateway does well | What the copy-the-chart model breaks |
|---|---|
| One Envoy gateway per API: token check, consumer authorization, rate limit, mTLS to the backend | **Security is a parameter.** `auth.enabled`, `allowGatewayAccessOnly`, `rateLimit.enabled` are plain switches in a values file a team edits. One wrong value silently ships an **unauthenticated** API. In the reference cluster, one gateway runs today with its token check off, and nothing flags it. |
| Backend reachable only through the gateway (a `gw-only` rule), encrypted | **Authorization is free text.** The allowed-consumer scope is a hand-typed string; nothing stops `*`. |
| Lives inside the team's namespaces, in the mesh | **N drifting forks.** Each team keeps a full copy of the chart and the whole values file; a base-chart fix is copied by hand into every repo, and versions diverge. Upgrading every gateway is N manual jobs. |
| Self-service: a team ships an API without a platform ticket | **No single request.** A new API touches three owners (tenant namespace labels, the identity-provider client, the gateway values) with no one object that means "I want a gateway". |

The extension's job is to make the gateway a **platform-owned Template** that a
team instantiates with a handful of parameters, with every security-critical
setting baked in and **not exposable as a parameter**. The team says *which*
API, backend and host; the platform owns *how* it is secured, and upgrades it
once for everyone.

### Why this is an extension, and not just a better Helm chart

Most of "one chart, no drift, secure defaults" is achievable with a shared
Helm chart and GitOps alone. Three things need the Multi-Tenant Operator, and
they are the reason this is an extension:

1. **The Template is a contract, not a copy.** Template Operator v2 renders the
   chart from a `TemplateInstance` the team commits; the team can set only the
   parameters the Template exposes. Security configuration is in the Template,
   out of reach. A values file a team can edit cannot give that guarantee.
1. **The tenant is the unit.** The gateway lives in the team's Tenant
   namespaces; mesh membership and the waypoint binding come from the `Tenant`,
   reviewed in Git; the derived consumer scope and the per-tenant hostname are
   bounded by the tenant. The gateway is "the team's", by construction.
1. **A tenant can't route around it.** A team could otherwise hand-write a raw
   Gateway with no token check. The same guardrail the service-mesh extension
   already uses — tenants may not create Gateway API `Gateway`s or waypoints,
   only the platform identity may — makes the Template the **only** way a
   tenant gets an ingress gateway (ADR-0006). North-south ingress becomes as
   governed as the service-mesh extension makes east-west traffic.

### Be honest about what it is **not**

- **It is not the "scoped login to a shared tool" pattern.** The gateway
  authenticates **API consumers** — machine clients with a bearer token and a
  consumer claim — not tenant members. It adds no card to the "become a tenant,
  log in to every tool scoped to you" catalog. Human access (who may edit the
  `TemplateInstance`) is ordinary Tenant RBAC through the group contract.
- **It leans on two platform prerequisites it does not build:** the shared
  rate-limit service, and the identity provider that issues consumer tokens.
  v1 provisions neither (scope, below; ADR-0009).
- **The rate-limit attachment may still be an `EnvoyFilter`,** which Istio
  discourages as unstable (baseline **D4**, service-mesh **R3**). Whether
  OpenShift Service Mesh 3 offers a supported alternative for a Gateway API
  gateway is the first thing the spike settles (ADR-0007, **VERIFY Q1**).
- **Fewer customers run Gateway-API ingress on a mesh** than run plain
  OpenShift Routes. Like the service-mesh extension, this is a door-opener for
  API-platform and regulated accounts, not a volume driver.

### Recommendation

**Build — generic, reference-driven, and spike-gated.** Concretely:

- **Design generic from day one.** The reference architecture is anonymised
  throughout (`team-a`, the `orders` API, `apps.example.com`, a generic Red Hat
  build of Keycloak realm). No customer name appears in this repo.
- **Now:** run story **M.0**, a live-install spike, to settle the open rows in
  `api-gateway-baseline.md` — chiefly the rate-limit attachment (Q1), whether
  `RequestAuthentication`/`AuthorizationPolicy` attach to a Gateway API
  `Gateway` by `targetRefs` (Q4), and how the two namespaces of one gateway are
  rendered (Q2). Keep the backlog position (#7).
- **Build phases 1–2** (the gateway Template with its baked security, and the
  two-sided wiring) once M.0 is green. The reference deployment is the pilot:
  its migration from the copy-the-chart model is the first validation.
- **Don't build** the shared rate-limit service or the identity-provider client
  provisioning here. They are prerequisites; the identity-provider client is a
  seam with `mto-extension-keycloak` for later (ADR-0009).

### What would change the verdict

- **Upward:** if the spike shows a supported, stable rate-limit and JWT path
  for Gateway API gateways (no `EnvoyFilter`), the durability objection falls
  and this becomes a confident build.
- **Downward:** if the only way to attach a shared rate-limit service or strip
  caller headers is an `EnvoyFilter` that the platform would have to own and
  carry across mesh upgrades anyway, the "platform owns one Template" saving
  shrinks, and the honest pitch narrows to "secure defaults no team can switch
  off" — still worth it, but a smaller story.

## The problem

Teams expose internal services as external APIs behind an ingress gateway. On a
mesh, each gateway is an Envoy proxy doing a specific, security-critical job:
reject calls without a valid token, reject callers not authorized for *this*
API, rate-limit per caller, strip any identity headers the caller tried to
spoof, and forward to the backend over mTLS where the backend accepts only the
gateway. Get any of these wrong and the API is exposed.

Today each team owns that configuration by copying a chart:

| What the platform wants | What the copy model gives | What breaks |
|---|---|---|
| "every API checks its token" | a `auth.enabled` switch in each team's values | a gateway ships with the check off; nothing notices (**the real failure**) |
| "a caller may use only the APIs it's entitled to" | a free-text allowed-consumer string per gateway | `*` or a typo widens it; no one reviews the string |
| "one gateway design, kept current" | N copies of the chart in N repos | a fix lands in one repo; the others drift; upgrading all is N jobs |
| "the backend is reachable only through the gateway" | a `gw-only` rule the same values file can turn off | one flag and the backend is open inside the cluster |

The Multi-Tenant Operator knows which namespaces form each team, labels them
for the mesh, and can render a chart teams cannot edit. The gateway chart,
copied into team repos, knows none of that.

## The vision

> **Secure ingress by default, self-served per team.** A team gets an API
> gateway by committing one short `TemplateInstance`: the API name, its backend,
> its host. Token validation, consumer authorization, header stripping, rate
> limiting and mTLS to the backend are in the platform's Template, not in the
> team's hands and not optional. The platform upgrades every gateway at once.
> No team can ship an unauthenticated API, and no team can route around the
> gateway.

## Who it is for

| Persona | Job to be done | What they get |
|---|---|---|
| **Platform / API-platform team** | run secure ingress for many teams without owning each team's config or trusting each team's switches | one Template, secured once; every gateway on one version; no gateway can disable its own token check |
| **API team member** | expose my service as an external API | one `TemplateInstance` with a few parameters; no security YAML to get right, no platform ticket |
| **API consumer** (a machine client) | call an API I'm entitled to | a token from the identity provider; the gateway admits it only for the APIs its claim lists |
| **Security and audit** | prove every external API checks tokens and authorizes callers | the security configuration is identical across all gateways and lives in one Template; no per-gateway exceptions to review |
| **Tenant owner** | let my team self-serve gateways without being able to weaken them | gateways in the tenant's namespaces, bounded by the tenant's hostname and consumer scope; edits gated by the group contract |

## Value proposition

- **Security is not a switch.** Token validation, consumer authorization,
  header stripping, `gw-only` backend access and mTLS are in the Template. There
  is no parameter to turn them off (ADR-0002).
- **Authorization is derived, not typed.** The allowed-consumer scope comes
  from the API name (`api-<apiName>-consumer-*`); a team cannot set `*` because
  there is no field for it (ADR-0003).
- **One Template, one version.** The platform owns the chart and upgrades every
  gateway at once, instead of chasing N forks.
- **Self-service that stays governed.** A team ships an API with one commit; the
  tenant bounds its host and its consumer scope; the guardrail stops a team
  hand-rolling a gateway that bypasses the Template (ADR-0006).
- **Built on what the customer runs.** Standard Gateway API, Istio
  `RequestAuthentication`/`AuthorizationPolicy`, and the platform's existing
  rate-limit service and identity provider. The extension renders objects; it
  runs no component of its own (ADR-0001).

### How it sells Multi-Tenant Operator subscriptions

The Tenant becomes the unit of **governed ingress**. The reason a team can
self-serve a gateway *and* can't weaken it is that the Multi-Tenant Operator
renders the chart as a contract and labels the namespaces for the mesh.
Commercial API gateways (3scale, Kong, Gloo) solve consumer management and rate
limiting, but they are another product to buy and run; this turns the ingress a
customer **already** builds on OpenShift Service Mesh into a per-team,
self-service, un-weakenable platform capability. It pairs with the service-mesh
extension: that one governs east-west (tenant-to-tenant); this one governs
north-south (into the tenant). Together, the Tenant is the unit of trust in
both directions.

## Principles

1. **Deterministic first.** Every gateway is rendered from a `TemplateInstance`
   in Git and the `Tenant`; nothing decides at run time.
1. **Security in the Template, API shape in the parameters.** The team chooses
   what to expose; the platform chooses how it is secured (ADR-0002).
1. **Enforce on the server side.** The backend's `gw-only` policy and the
   gateway's token check are enforced by the mesh where traffic arrives, not by
   anything the caller does (baseline **S1**).
1. **Derive, don't trust free text.** Consumer scope and hostname are derived
   from the API name and the tenant, not typed by the team (ADR-0003).
1. **Wrap the platform.** No operator, no API calls, no gateway of its own:
   charts and standard Kubernetes, Istio and Gateway API objects (ADR-0001).
1. **Compose, don't duplicate.** Mesh membership, the rate-limit service and the
   identity provider belong to the platform (and, for the mesh boundary, to the
   service-mesh extension); this extension renders the gateway on top.
1. **When the gateway can't do something safely, say so.**

## Scope — deliberately small

1. Publish the `api-gateway` Template (gateway side): `Gateway`, routes,
   `HTTPRoute`, `RequestAuthentication`, consumer `AuthorizationPolicy`, the
   header-strip and rate-limit hooks, and telemetry — secured in the Template.
1. Render the backend side (`ReferenceGrant`, the `gw-only` `AuthorizationPolicy`,
   and the waypoint) into the application namespace, and wire mesh/waypoint
   membership from the `Tenant` (ADR-0005).
1. Keep security un-switchable and the consumer scope derived (ADR-0002, 0003).
1. Report health: gateways whose backend namespace is not in the mesh, missing
   waypoint labels, invalid hostnames, rendering lag.

## Non-goals

- Installing or running the identity provider, the shared rate-limit service,
  or OpenShift Service Mesh (prerequisites; `design.md`).
- Provisioning the identity-provider consumer client and its role in v1 (a seam
  with `mto-extension-keycloak`; ADR-0009).
- The east-west tenant boundary and tenant connections (that is the
  service-mesh extension; this one composes with it, ADR-0006).
- A gateway per tenant, or a single shared gateway for all APIs — the unit is
  one gateway per API per environment (ADR-0004).
- L7 consumer policy beyond the token/claim/host/rate-limit set in v1.
- Egress gateways, multi-cluster, and any per-user (human) binding.

## How we'll know it works

- A team commits a `TemplateInstance` for API `orders`; one render later the
  gateway is live, and there is **no parameter** anywhere that disables its
  token check or sets its consumer scope to `*`.
- A call with no token gets `403`; a valid token for the wrong API gets `403`;
  an invalid token gets `401`; a valid token for `orders` gets `200`.
- A caller that floods the gateway gets `429` after its tier's limit.
- A caller-supplied `x-sub`/`x-roles` header is stripped; the backend sees only
  what the gateway set from the token.
- A pod calling the backend Service directly (not through the gateway) is
  refused; only the gateway identity gets through, over mTLS.
- The platform bumps the Template version once; every gateway is on the new
  version at the next render, with no team doing anything.
- A gateway whose application namespace lost its mesh or waypoint label is
  reported, not silently out of the mesh.
