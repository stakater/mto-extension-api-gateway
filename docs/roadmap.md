# Roadmap

Phases → milestones → user stories. **Every story delivers a demo-able
outcome.**

## How we work

- **Story format:** *As a `<role>`, I want `<capability>`, so that `<value>`.*
  Every story has a **Done:** line and cites the acceptance scenarios it
  satisfies (`acceptance.md`, e.g. **AC-SEC-2**).
- **Lifecycle:** **📝 Draft** → **👍 Approved** → **🔨 In progress** →
  **✅ Done**. Nothing moves from Draft to In progress without explicit
  approval.
- **The gate.** The value verdict (`vision.md`) is "build — generic,
  reference-driven, spike-gated". M.0 may start on approval. Phases 1–2 start
  when M.0 is green, chiefly **Q1** (rate limiting without `EnvoyFilter`),
  **Q4** (policy on a Gateway API gateway) and **Q2** (two-namespace render).
- **One story at a time**, end to end. Walking skeleton first: one gateway, one
  API, token check proven to be un-switchable.
- The method: `method.md`. Everything is built in this repo; no config
  operator (ADR-0001, ADR-0004).

## Phases

| Phase | Demo outcome |
|---|---|
| **0 · Prove the ground** | Every open question in `api-gateway-baseline.md` answered on a live OpenShift Service Mesh 3.4; chiefly whether rate limit, header strip and JWT attach to a Gateway API gateway without a fragile `EnvoyFilter`. |
| **1 · The secure gateway (walking skeleton)** | A team commits one `TemplateInstance`; the `orders` gateway is live; no token → `403`, wrong-API token → `403`, valid token → `200`; and there is **no parameter** that turns the token check off. |
| **2 · The backend side** | The backend is reachable only through the gateway, over mTLS; caller identity headers are stripped; mesh/waypoint labels come from the `Tenant`; deleting the `TemplateInstance` tears the gateway down cleanly. |
| **3 · Governed and observed** | A team's hand-written gateway is refused; `externalHost` is bounded by the tenant; rate-limit tiers enforced; health in one place; telemetry per tenant. |
| **4 · Later** | Per-consumer tiers; the Keycloak-extension seam for consumer clients; sidecar mode; L7 consumer policy; multi-cluster. |

---

## Phase 0 — Prove the ground

**Story M.0 — Live-install spike** 📝 *Draft*

As the engineer building the extension, I want every open gateway question
answered on a live install, so that the design rests on observed behaviour and
not on the reference architecture's `EnvoyFilter`.

Done: questions **Q1–Q11** in `api-gateway-baseline.md` answered with evidence
in `docs/spikes/m0-findings.md`; each Proposed ADR Accepted or superseded;
`design.md` updated, especially §8 (rate limiting) once **Q1** is known.
Planning: [`planning/M0-live-install-spike.md`](planning/M0-live-install-spike.md).

---

## Phase 1 — The secure gateway

**Story M.1 — Bootstrap: publish the Template** 📝 *Draft*

As a platform team, I want to install the extension once and have the
`api-gateway` Template available, so that teams can self-serve gateways.

Done: `api-gateway-mto-bootstrap` publishes the `api-gateway` `Template` (the
gateway chart), the values schema, and the bootstrap values (issuer, rate-limit
reference, hostname pattern); `make` runs helm lint, the version check and
golden render tests. Satisfies **AC-OPS-2**.

**Story M.2 — The gateway, with un-switchable security** 📝 *Draft*

As an API team member, I want to get a secure gateway from a short
`TemplateInstance`, so that I ship an API without writing security YAML and
can't get it wrong.

Done: `api-gateway` renders the `Gateway`, `Route`/`HTTPRoute`,
`RequestAuthentication`, consumer `AuthorizationPolicy` and `Telemetry` with
`sync.mode: revert`; the only parameters are the API-shaped ones (§5); golden
tests prove there is **no** parameter for `auth`, the consumer scope or
`gw-only`, and that the consumer scope is derived from `apiName`; on a live
install, no-token → `403`, wrong-API token → `403`, invalid token → `401`,
valid token → `200`. Satisfies **AC-SEC-1..4**, **AC-GW-1**.

**Story M.3 — Rate limiting** 📝 *Draft*

As a platform team, I want every gateway rate-limited through the shared
service with no off switch, so that no API can skip it.

Done: the rate-limit hook is always rendered (the mechanism chosen by **Q1**),
wired to the configured service; `tier` selects a class; a flood returns `429`
after the tier limit on a live install; golden test proves no disable
parameter. Satisfies **AC-RL-1**, **AC-RL-2**.

> **Phase 1 demo:** `ola` commits a `TemplateInstance` for `orders`. A curl
> with no token: `403`. With a token for another API: `403`. With a valid
> `orders` token: `200`. `ola` greps the Template for a way to turn auth off:
> there isn't one. A loop of calls: `429` after the tier limit.

---

## Phase 2 — The backend side

**Story M.4 — gw-only and mTLS to the backend** 📝 *Draft*

As a platform team, I want the backend reachable only through the gateway and
only over mTLS, so that the API can't be bypassed inside the cluster.

Done: the `api-backend` Template renders `ReferenceGrant`, the `gw-only`
`AuthorizationPolicy` (the gateway identity only) and the waypoint into the
application namespace via the platform `TemplateGroupInstance` (per **Q2**,
**Q3**); on a live install a direct call to the backend Service is refused and
the gateway's call succeeds over mTLS. Satisfies **AC-GW-2**, **AC-GW-3**.

**Story M.5 — Header stripping** 📝 *Draft*

As a security owner, I want caller-supplied identity headers stripped, so that
a caller can't spoof identity to the backend.

Done: the gateway removes inbound `x-sub`/`x-roles` and sets its own from the
token; on a live install a caller sending `x-roles: admin` reaches the backend
with only the gateway-set value. Satisfies **AC-SEC-5**.

**Story M.6 — Membership from the Tenant, and clean teardown** 📝 *Draft*

As a platform team, I want mesh/waypoint membership to come from the `Tenant`
and a deleted gateway to tear down cleanly, so that the namespace labels stay
reviewed and nothing is orphaned.

Done: the extension writes no namespace label; the waypoint is shared per
application namespace and survives while any gateway uses it; deleting a
`TemplateInstance` removes its gateway-side objects and its `gw-only` entry.
Satisfies **AC-GW-4**, **AC-LIFE-1**, **AC-LIFE-2**.

> **Phase 2 demo:** a pod in `team-a-test` curls `orders-api` directly:
> refused. The gateway's call: `200` over mTLS. A caller sends `x-roles: admin`;
> the backend logs show only the gateway's value. `ola` deletes the gateway;
> the `Gateway` and its `gw-only` entry are gone, the waypoint stays (another
> API still uses it).

---

## Phase 3 — Governed and observed

**Story M.7 — No route around the Template** 📝 *Draft* — the guardrail
(this extension's own, or deferred to the service-mesh extension, **Q9**)
refuses a team's hand-written `Gateway`/waypoint; the Template Operator
identity passes. Satisfies **AC-GOV-1**.

**Story M.8 — Hostname bounded by the tenant** 📝 *Draft* — `externalHost`
outside the tenant's `hostnamePattern` is refused at render (and reported);
two tenants can't claim the same host. Satisfies **AC-GOV-2**.

**Story M.9 — Health in one place** 📝 *Draft* — parent TI outputs per
gateway: ready, backend-not-meshed, invalid host, backend-missing,
prerequisites. Satisfies **AC-OPS-1**, **AC-OPS-2**.

**Story M.10 — Telemetry per tenant, verified** 📝 *Draft* — the gateway's
`Telemetry` object routes logs and traces through the platform collector to the
tenant's partition; exercised by the live suite. Satisfies **AC-TEL-1**.

---

## Phase 4 — Later

**Story M.11 — Per-consumer tiers** 📝 *Draft* — if **Q8** shows the token
carries a tier, apply it per consumer instead of per gateway.

**Story M.12 — Consumer client seam with the Keycloak extension** 📝 *Draft*
— derive the identity-provider consumer client and `allowed_apis` role from the
gateway request, through `mto-extension-keycloak` (ADR-0009), so a new API is
one object end to end.

**Story M.13 — Sidecar mode** 📝 *Draft* — the same gateway and backend wiring
for tenants in sidecar mode (ADR-0008).

**Story M.14 — L7 consumer policy** 📝 *Draft* — per-path/method authorization
for a consumer, on the waypoint, beyond the token/claim/host set.

---

## Open decisions

The forks the design leaves open. The **decided** positions are the ADRs
(`docs/adr/`); these are the ones still to settle, each before or during the
phase that depends on it. "Proposed" marks the design's current lean.

1. **Build gate.** Is "M.0 green, chiefly Q1" the gate for phases 1–2, or should
   a pilot migration of an existing copy-the-chart deployment also be a gate?
1. **Rate-limit mechanism (Q1).** If only `EnvoyFilter` works, does the platform
   own that filter across mesh upgrades (ADR-0007, proposed), or is "secure
   defaults, bring your own rate limiting" an acceptable v1?
1. **Guardrail ownership (Q9).** Ship this extension's own ingress guardrail
   (proposed), or require the service-mesh extension for it (ADR-0006)?
1. **Consumer provisioning.** Stay a prerequisite (ADR-0009, proposed), or pull
   the Keycloak-extension seam into v1 so a new API is one object (M.12)?
1. **Tier placement (Q8).** Per gateway (proposed) or per consumer token (M.11)?
1. **Backend placement.** Which does v1 support (design §6.1): the backend in a
   separate application namespace (proposed default); the gateway and backend in
   the **same** namespace; a backend **outside the cluster** (an `ExternalName`
   Service)? Each changes the backend-side render and the `gw-only` rule.
1. **Hostname model.** A per-API external host bounded by the tenant (proposed),
   only — or also a **shared host** with path-based routing across a tenant's
   APIs (design §6.1)?
1. **Parameter derivation.** Should the Template derive `backendNamespace` and
   `externalHost` from the gateway namespace name, so only `apiName` and the
   backend service differ between environments (fewest parameters), or keep them
   explicit (clearer)? (design §6.1)
1. **Two-namespace mechanism (Q2).** Team `TemplateInstance` + platform
   `TemplateGroupInstance` (proposed, ADR-0005), one tenant-level
   `TemplateGroupInstance` over both namespaces, or two split Templates?
1. **Promotion.** How a gateway is promoted test → prod — same Template,
   per-environment values; driven by the team, the platform, or a shared
   pipeline (process to define).
1. **Sidecar support.** Ambient only in v1 (proposed, ADR-0008), or sidecar mode
   from day one?

## Not on the roadmap (non-goals)

Installing the mesh, the rate-limit service or the identity provider ·
provisioning consumer clients in v1 · the east-west tenant boundary (the
service-mesh extension) · one gateway per tenant · end-user authentication ·
egress gateways · multi-cluster. See `vision.md`.
