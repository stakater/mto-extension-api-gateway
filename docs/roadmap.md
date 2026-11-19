# Roadmap

Phases → milestones → user stories. **Every story delivers a demo-able outcome.**

## How we work

- **Story format:** *As a `<role>`, I want `<capability>`, so that `<value>`.*
  Every story has a **Done:** line and cites the acceptance scenarios it
  satisfies (`acceptance.md`, e.g. **AC-ISO-1**).
- **Lifecycle:** **📝 Draft** (written, not agreed — may be re-scoped or killed)
  → **👍 Approved** (a human said build it) → **🔨 In progress** → **✅ Done**
  (Done line met, `make verify` green, planning doc linked). Nothing moves from
  Draft to In progress without explicit approval.
- **One story at a time**, end to end. Walking skeleton first: one tenant, one
  API, one caller, checked and proven, then thicken.
- **Reuse, don't redesign.** The bootstrap chart shape, the per-tenant
  fan-out, the skipped-tenants ConfigMap, the render harness and the version
  rules come from `mto-extension-vault-enterprise` (ADR-0001).
- The method: `method.md`.

## Phases

| Phase | Demo outcome |
|---|---|
| **0 · Prove the ground** | Every open question in `gateway-baseline.md` answered: on kind with upstream Istio (ambient) and Template Operator first, then on a live OpenShift with Service Mesh 3; ADRs moved to Accepted or superseded. |
| **1 · Walking skeleton** | A team asks for its tenant's gateway → it appears in the team's namespace and scales → the team creates one `api` instance → `shop` gets `200`, a caller without the API gets `403`, too fast gets `429`, a pod calling the backend directly is refused → the team tunes its claim headers and correlation ID with annotations. |
| **2 · Trustworthy** | Status and preflight, lifecycle, admission, migration from per-API gateways, an upgrade test — ready for a design partner. |
| **3 · Complete** | RHBK roles from the route, a gateway of its own when an API needs one, observability per tenant, docs. |

---

## Phase 0 — Prove the ground

**Story G.19 — Kind spike** 📝 *Draft*

As the engineer building the extension, I want the riskiest Istio and
Template Operator assumptions tested on a kind cluster first, so that every
chart story builds on observed behaviour, not on docs alone.

Done: the lab in `hack/lab/` (kind, Gateway API, upstream Istio in ambient
mode, Template Operator v2 with a stub `Tenant` CRD, a lab issuer, an echo
backend, the rate limit service with Redis), with no customer data; evidence
in `docs/spikes/g19-kind-findings.md` on Istio 1.27.9 and 1.30.8 for: root
namespace `selector` policies combined with `targetRefs` policies on a
gateway; the empty `ALLOW` denying and `rules: [{}]` allowing; claim headers
overwritten and caller copies removed, `x_sub` included; virtual-host rate
limit actions with no name (M14), a missing `azp` and an unknown tier; a token of another tenant's issuer (M17, Q18); the
gateway's HBONE identity at a locked backend; Template Operator's empty LIST
and missing-key behaviour (T6, T7); the default Service type of a gateway
(M13); that an `AuthorizationPolicy` scoped by host and path keeps two APIs
on one host apart, with segment prefixes, `//`, `/./`, `/../`, `%2F`, a query
string, a path in another case, and a rewrite on the route (M16, Q16); whether
a render can detect and refuse a name that an existing object
already holds, and that deleting a request never removes such an object (T4,
issue #11); that no request passes while the policies are applied in any order
(issue #10); `gateway-baseline.md` rows updated.

**Story G.0 — Live spike on OpenShift** 📝 *Draft*

As the engineer building the extension, I want the OpenShift-only questions
answered on a live cluster, so that the entry point and the Service Mesh
operator behave as the charts expect.

Done: on an OpenShift lab with Service Mesh 3 (ambient) and Template Operator:
the SNI a reencrypt and a passthrough `Route` send to a gateway with
hostname-bound listeners (R4); a wildcard passthrough `Route` on a dedicated
IngressController; one shared host split by path between two tenants'
gateways with reencrypt `Route`s, `InterNamespaceAllowed`, the `entry`
listener and the service CA certificate (R1–R3, Q17); the Service Mesh operator's `istio` GatewayClass, port
mapping and `parametersRef`; the open questions in `gateway-baseline.md` that
kind can't answer; evidence in `docs/spikes/g0-findings.md`; each ADR
Accepted or superseded. Planning:
[`planning/G0-live-spike.md`](planning/G0-live-spike.md).

---

## Phase 1 — Walking skeleton

**Story G.1 — A gateway per tenant, on request** ✅ *Done*

As an API team, I want to ask for my tenant's gateway with one
`TemplateInstance`, so that I get a gateway with the platform's settings
without configuring one; as a platform team, I want each tenant to have at most
one, and to decide everything about it.

Done: bootstrap chart with the parent `Template` and `TemplateInstance`; the
parent publishes the `api-gateway` Template (only tenant namespaces, sync
`strict`, every parameter `disableOverride`: `tenantOf`, `owner`, granted
extra host names, gateway settings); a team's parameterless request renders,
in its own namespace, `Gateway` `<request>` with the listeners of ADR-0002 and
ADR-0009, its autoscaling ConfigMap and its certificates, or only a status
ConfigMap that says why not; one owner per tenant (the oldest valid request);
invalid tenant names, refused host names and refused requests listed; the
render harness (golden, CRD validation against vendored Gateway API and
cert-manager CRDs, listener, trust and forbidden-kind checks) wired into
`make verify`. Live checks wait for G.0. Satisfies **AC-ISO-1**,
**AC-ISO-2**, **AC-ISO-9**, **AC-R-1**, **AC-R-5**, **AC-LIFE-1**,
**AC-LIFE-5**. Planning:
[`planning/G1-gateway-per-tenant.md`](planning/G1-gateway-per-tenant.md).

**Story G.20 — The harness renders like Template Operator** 📝 *Draft*

As the engineer building the extension, I want the offline render to fail
where Template Operator fails, so that a green `make verify` means the chart
renders live.

Done: a Go renderer in `hack/render/` (Go templates with Sprig, as Template
Operator's engine, and `missingkey=error`) replaces the helm `tpl` shim for
every gotemplate; Istio CRDs (`security.istio.io`, `networking.istio.io`,
`telemetry.istio.io`) vendored for `crd-validate`; fixtures for an empty
LIST and for listed objects without annotations, each failing offline as it
would live; golden unchanged.

**Story G.21 — Gateways are internal and labelled** 📝 *Draft*

As a platform team, I want every tenant gateway reachable only through the
entry point and recognisable by one label, so that no tenant gets a load
balancer and the cluster-wide floor finds every gateway.

Done: the team render sets `networking.istio.io/service-type: ClusterIP` and
the platform label in the `Gateway`'s `infrastructure`; render check and
mutation test; golden regenerated. Satisfies **AC-R-7**.

**Story G.2 — The security baseline** 📝 *Draft*

As a security owner, I want every tenant gateway to refuse a request without
a valid token and to deny by default, before any API exists, so that no API is
ever served without the checks.

Done: the bootstrap chart renders, in the Istio root namespace, the
issuer-pinned `DENY` floor and the empty `ALLOW`, both selecting the gateway
label; the parent emits the per-tenant child `TemplateInstance` (ADR-0013),
which renders the `RequestAuthentication` (token from the `Authorization`
header only) and the header-removal `EnvoyFilter`; the `EnvoyFilter`
allowlist check replaces the forbidden-kind check; render checks and mutation
tests; live on the kind lab: no token, an invalid token, a token in the query
string, and a valid token without an API rule are all refused. Satisfies
**AC-R-1**, **AC-R-2**, **AC-ISO-8**, **AC-AUTH-1**, **AC-AUTH-2**,
**AC-AUTH-6**, **AC-AUTH-7**, **AC-AUTH-9**, **AC-LIFE-1**.

**Story G.13 — One issuer, many, or one per tenant** 📝 *Draft*

As a platform team, I want to trust one issuer, several, or a tenant's own
issuer for that tenant only, so that environments and teams with their own
Keycloak share one cluster without trusting each other's tokens.

Done: bootstrap values `auth.issuers`, `defaultIssuers` and `tenantIssuers`
(ADR-0004); the floor lists every issuer; each tenant's
`RequestAuthentication` and API rules name only its issuers; the parent
refuses an unknown name, a duplicate URL, and a tenant-run issuer used by
another tenant, and skips a tenant with no issuer; render checks for one,
two and per-tenant issuers; live on the kind lab with two lab issuers: each
tenant accepts its own tokens and refuses the other's, also with a forged
claim for its API. Satisfies **AC-AUTH-10**, **AC-R-2**.

**Story G.8 — Admission, before any API is served** 📝 *Draft*

As a security owner, I want a tenant user refused when it tries to change or
impersonate its gateway, so that the gateway's namespace being the tenant's
doesn't weaken the checks.

Done: a `ValidatingAdmissionPolicy` and binding in the bootstrap chart, for
tenant users only, refusing: a `Gateway`, `EnvoyFilter`, `WasmPlugin` or
`TrafficExtension`; a `RequestAuthentication`, `AuthorizationPolicy` or
`Telemetry` that targets a `Gateway` or selects gateway pods; a pod using a
gateway's service account; `exec`, `attach` and `port-forward` into gateway
pods; the label `istio.io/dataplane-mode=none` on a pod; an `HTTPRoute` in a
tenant namespace; a `valueFrom` parameter on an `api` or `api-gateway`
instance (T9, ADR-0005); Template Operator and
Istio's own writes allowed; render checks; live as a tenant editor on the kind
lab. Satisfies **AC-ISO-6**.

**Story G.26 — An API is a `TemplateInstance`** 📝 *Draft*

As an API team, I want to publish an API with one `TemplateInstance` that
names its host, path and backend, so that I never write a route and the
platform can check every route it serves.

Done: the parent publishes the `api` Template (tenant namespaces only, platform
parameters `disableOverride`, `strict`); an instance renders the `HTTPRoute`
`api.<api>` (prefix or exact operations, rewrite, backend in its namespace,
the annotation) and the ConfigMap `api.<api>`; each check of ADR-0005 has a
render test, and an invalid parameter or a tenant with no gateway renders
`refused` and no route; live: `orders` and `payments` attach to `team-a`'s
gateway. Satisfies **AC-AUTH-8** (refused parts), **AC-LIFE-2**.

**Story G.3 — The tenant's routes, listed** 📝 *Draft*

As an API team, I want to see which of my routes are APIs and which are not,
and why, so that I can fix a route before anyone calls it.

Done: the child lists the tenant's `HTTPRoute`s and `Service`s by the tenant
label; the status ConfigMap `<request>-apis` in the gateway's namespace lists
APIs, routes that are not APIs, duplicate API names (oldest wins), path
conflicts on one host (ADR-0005) and invalid backends; a tenant with no
routes renders cleanly. Satisfies **AC-OPS-2** (route parts).

**Story G.4 — The backend lock** 📝 *Draft*

As an API team, I want my backend to accept calls only from my tenant's
gateway, so that nobody in the cluster can skip the gateway's checks.

Done: per backend Service of an API's route, an Istio
`AuthorizationPolicy` (L4, ztunnel): `DENY` on the target ports from every
identity but the tenant gateway's; a backend that can't be locked (no
selector, `ExternalName`, a named `targetPort`, a namespace outside the mesh)
gets no API rule and is listed; live: `intruder` and `outsider` refused, also
after an extra `ALLOW`; the gateway allowed. Satisfies **AC-ISO-5**,
**AC-ISO-7**.

**Story G.24 — An API's route gets its rule** 📝 *Draft*

As an API team, I want my `api` instance to publish my API with the right
allowed-API rule, so that I never write a security rule and never get one
wrong.

Done: per valid API route, one `ALLOW` in the gateway's namespace scoped to
the route's host and path (or exact operations), with the closed rule of
ADR-0006 and `azp` required; overlapping paths on one host fail closed; live:
`shop` `200` with headers set from the token, `bank`, `near`, `bare` `403`,
`plain` and `plain-extra` serve nothing, the prefix tenant isolated,
`payments` on `orders`' host isolated from `orders`, an overlapping
`orders-admin` closes both.
Satisfies **AC-ISO-3**, **AC-ISO-4**, **AC-AUTH-3**, **AC-AUTH-4**,
**AC-AUTH-5**, **AC-AUTH-8**, **AC-R-4**, **AC-R-6**, **AC-LIFE-2**.

**Story G.5 — Rate limit tiers** 📝 *Draft*

As a platform team, I want each authenticated caller limited by its tier on
every API, so that no caller uses more than its share of a tenant's gateway.

Done: the bootstrap chart deploys the rate limit service with its tier
configuration from bootstrap values (Redis address and secret as values); the
child renders the rate limit `EnvoyFilter` (descriptors `tenant`, `tier`
defaulting to `bronze`, `azp`); per-tenant `unlimited` and the failure mode as
platform values; live: `429` at the limit, per caller, a missing or unknown
tier at `bronze`, an exempt tenant unlimited. Satisfies **AC-RL-1**,
**AC-RL-2**, **AC-RL-3**, **AC-RL-4**, **AC-RL-5**, **AC-RL-6**.

**Story G.25 — Team settings on the gateway request** 📝 *Draft*

As an API team, I want to set my backend's claim headers, a correlation ID and
my access logs and traces myself, so that I don't wait for the platform team
for settings that can't weaken security.

Done: the child reads the owner request's `api-gateway.stakater.com/*`
annotations (ADR-0012), validates them, renders the claim-header extras, the
correlation-ID `EnvoyFilter` and the `Telemetry`; refused and unknown keys
listed with the reason; live: a mapped header set from the token and the
caller's copy removed, the correlation header added when absent and kept when
sent. Satisfies **AC-KNOB-1**, **AC-KNOB-2**, **AC-KNOB-3**, **AC-R-3**.

**Story G.18 — The entry point** 📝 *Draft* — the entry point that G.0
measures, rendered per tenant gateway: for shared hosts, one reencrypt `Route`
per granted prefix and the `entry` listener (ADR-0009); for the tenant's own
and extra hostnames, a passthrough `Route` per host or one wildcard
passthrough `Route` on a dedicated IngressController, as G.0 shows;
certificates from the platform's issuer. Satisfies **AC-ISO-2** (live),
**AC-ISO-10**.

---

## Phase 2 — Trustworthy

**Story G.6 — Status and preflight** 📝 *Draft* — gateway `Programmed`, and
refused knobs, in the request's status; namespaces outside the mesh and hosts
outside the tenant's hostnames in `<request>-apis`; preflight for Service
Mesh, the Gateway API and Istio CRDs, Template Operator, the issuer and Redis.
Satisfies **AC-OPS-2**.

**Story G.7 — Lifecycle** 📝 *Draft* — route deleted, request deleted,
tenant deleted, a hand edit reverted or refused; nothing left behind, nothing
else touched. Satisfies **AC-LIFE-2**, **AC-LIFE-3**, **AC-LIFE-4**,
**AC-LIFE-6**.

**Story G.23 — Admission, agreed with the Service Mesh extension** 📝 *Draft* —
one shared list of refused kinds with the Service Mesh extension; a `parentRef`
to another tenant's gateway; a tenant's OpenShift `Route` under the base
domain or for a shared host (ADR-0009). Satisfies **AC-ISO-6** (shared list).

**Story G.9 — Migration from per-API gateways** 📝 *Draft* — the per-API
gateways serve production, so a runbook and a lab rehearsal that move one API
at a time, on the test cluster first, with no change for callers: the new
claims (`api.<tenant>.<api>`, `tier`) added to every caller's tokens next to
the old roles, and checked; the headers each backend reads compared through
both gateways; a values file turned into an `api` instance on the same shared
host and path; one change that moves the path's entry point and one that moves
it back; the error rate, latency and `401`/`403`/`429` counts compared before
and after; the old gateway removed after the agreed period. Satisfies
**AC-MIG-1**, **AC-MIG-2**, **AC-MIG-3**, **AC-MIG-4**.

**Story G.10 — Upgrades prove themselves** 📝 *Draft* — the live suite runs
before and after a Service Mesh minor upgrade and after a chart version bump;
both runs kept as evidence. Satisfies **AC-OPS-1**, **AC-OPS-3**, **AC-OPS-4**.

---

## Phase 3 — Complete

**Story G.11 — Identity-provider roles from the route** 📝 *Draft* — the
`api.<tenant>.<api>` role and the API's client created in RHBK from the
`api` instance, so that the three owners of a new API become one request.
Needs a supported way to configure RHBK from the cluster; decided in its
planning doc.

**Story G.12 — A gateway of its own** 📝 *Draft* — opt-in: a second gateway for
a tenant, for one API or one environment, chosen by the platform per tenant
(ADR-0002).

**Story G.14 — Observability per tenant** 📝 *Draft* — gateway access logs in
the platform's JSON format, traces and metrics labelled with the tenant and the
API, delivered through the Multi-Tenant Operator's telemetry gateways.

**Story G.15 — Documentation** 📝 *Draft* — the extension's page in the
Multi-Tenant Operator docs, and a tutorial that fits the free edition (two
tenants).

**Story G.16 — Backends outside the cluster** 📝 *Draft* — an API whose
backend is outside the cluster (today an `ExternalName` Service, refused in
v1): a platform-approved list of external hosts per tenant, reached through
the mesh's egress, with what the lock can and can't promise there.

**Story G.17 — Internal callers of an API backend** 📝 *Draft* — an API team
names ServiceAccounts of its own namespace that may also call the backend's
API ports, so internal callers don't have to go through the gateway.

---

## Developer experience — enforcing the method

The method (`method.md`) is enforced by `make verify` and the PR workflow. These
stories close the gaps it lists under "Known enforcement gaps".

**Story DX.1 — CI is a merge gate** 📝 *Draft*

As a reviewer, I want a red `verify` check to block the merge, so that the
method can't be skipped by merging past a failing check.

Done: `verify` listed in the required status checks for this repo in
`stakater-ab/stakater-github-config`; a PR with a failing check can't be
merged.

**Story DX.2 — The method on every edit** 📝 *Draft*

As an engineer or agent, I want the fast checks to run after every edit, so
that a broken rule shows up while I work rather than at the PR.

Done: a Claude Code PostToolUse hook in `.claude/settings.json` runs
`make method links` after each edit to a Markdown file; the hook is documented
in `CLAUDE.md`.

---

## Not on the roadmap (non-goals)

Running the identity provider · installing Service Mesh, Redis or the
Gateway API CRDs · mesh membership and east-west traffic · a shared
multi-tenant entry point · API management features. See `vision.md`.
