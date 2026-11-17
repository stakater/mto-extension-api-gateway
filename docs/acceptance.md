# Acceptance scenarios

> **Pending decision (2026-11-17).** ADR-0003 now proposes Istio-native
> policies plus two platform-owned, tested `EnvoyFilter`s instead of Kuadrant
> (Connectivity Link) policies; ADR-0011 is rejected. This page (the AuthPolicy wording, and AC-R-1 on `EnvoyFilter`s) still
> describes the Kuadrant form. It changes when the code owner decides; until
> then, ADR-0003 and ADR-0004 describe the proposed form.

The security contract, as testable scenarios. Stories cite these by id. Each
scenario names its **level**: **R** = render test (no cluster), **L** = live
(an OpenShift lab with Service Mesh 3 in ambient mode, Connectivity Link,
Template Operator v2, the Multi-Tenant Operator and RHBK), **R+L** = both.

Rules for every live scenario:

- Call as the caller: a real token from RHBK for the fixture client, through
  the real OpenShift `Route` or load balancer, never a port-forward to the
  gateway pod.
- A denial counts only with its status code (`401`, `403`, `429`, or a refused
  connection for the backend lock) **and** a matching allow on the same path by
  a caller who should pass.
- A denial must test a capability the caller would have if the guard broke.
- The backend is an echo service that returns the request headers it got, so a
  scenario can assert what reached the application.
- Mutation-test every new denial: break the guard on purpose and see the
  scenario fail.

Fixture:

- Tenants `team-a` (namespaces `team-a-dev`, `team-a-test`, and
  `team-a-outside`, which is not in the mesh), `team-b` (`team-b-dev`) and
  `team` (`team-core`), whose name is a prefix of `team-a`'s. `team-a` is
  granted the extra hostname `api.team-a.example.org`.
- Gateway requests (`TemplateInstance`s of `api-gateway`, no parameters):
  `api-gateway` in `team-a-dev` (team-a's gateway), `gw` in `team-b-dev` and
  `gw` in `team-core`; a later second request `extra` in `team-a-test`; and a
  request `stray-request` in `unlabelled`, a namespace of no tenant.
- APIs (annotated `HTTPRoute`s with an echo backend):
  `orders` in `team-a-dev` (`/orders/v2` → `/orders/v1`),
  `billing` in `team-b-dev`, and `a-orders` in `team-core`.
- Routes without the annotation, attached to `team-a`'s gateway: `plain` (on
  `*.team-a.apis.example.com`) and `plain-extra` (on `api.team-a.example.org`),
  both in `team-a-dev`.
- Annotated routes whose backend can't be locked: `legacy` in `team-a-dev`
  (an `ExternalName` Service) and `stray` in `team-a-outside`.
- RHBK clients: `shop` (`allowed_apis: [api.team-a.orders]`, tier `silver`),
  `bank` (`[api.team-b.billing]`, `gold`), `near` (`[api.team-a.orders2]`,
  `silver`), `core` (`[api.team.a-orders]`, `silver`), `bare` (no
  `allowed_apis`, no tier).
- A pod `intruder` in `team-a-test`, in the mesh, and a pod `outsider` in
  `team-a-outside`, not in the mesh.
- A user `alice` with the Multi-Tenant Operator's editor role in `team-a`.

## Tenant separation

**AC-ISO-1 — A route can't attach to another tenant's gateway.** *(R+L)* An
`HTTPRoute` in `team-b-dev` with a `parentRef` to `team-a`'s gateway
(`api-gateway` in `team-a-dev`) is not
accepted (route status `Accepted=False`); a request for its host through
`team-a`'s gateway gets no route. `billing`, attached to `team-b`, is accepted.

**AC-ISO-2 — A host outside the tenant's hostnames is never served.** *(L)* A
route in `team-a-dev` for `x.team-b.apis.example.com` doesn't attach
(`Accepted=False`, listed as `unattached`); a request for that host through
the real entry point never reaches `team-a`'s backend. A route for
`dev.team-a.apis.example.com` attaches and serves.

**AC-ISO-3 — A caller for another tenant's API is refused.** *(L)* `bank` is
refused `orders` with `403`; `shop` gets `200` on the same path.

**AC-ISO-4 — A prefix tenant doesn't reach its neighbour.** *(R+L)* The rule
rendered for `team-core`'s `a-orders` is `api.team.a-orders`, and no rule
rendered for tenant `team` matches a value that starts `api.team-a.`. `core` is
refused `orders` (`403`) and allowed `a-orders` (`200`).

**AC-ISO-5 — The backend answers only its tenant gateway.** *(L)* `intruder`
and `outsider` calling Service `orders` directly are refused; the same request
through `team-a`'s gateway, as `shop`, gets `200`. After a cluster admin adds
an `ALLOW` policy for any source on `orders`' pods, `intruder` is still
refused.

**AC-ISO-6 — Tenants can't create gateways, policies or filters.** *(L)* As
`alice`, creating a `Gateway`, `AuthPolicy`, `RateLimitPolicy`, `EnvoyFilter`,
`WasmPlugin` or `TrafficExtension` in `team-a-dev`, labelling a pod
`istio.io/dataplane-mode=none`, or creating an OpenShift `Route` for a host
under `apis.example.com` is refused (RBAC or admission, with the reason);
creating an `HTTPRoute` is allowed.

**AC-ISO-7 — A backend the lock can't cover serves nothing.** *(R+L)* No
route-level `AuthPolicy` is rendered for `legacy` or `stray`; both are refused
for every caller and listed as `invalid` and `outside-mesh`. `orders` serves.

**AC-ISO-8 — Every listener denies by default.** *(R+L)* Each listener of
`team-a`'s gateway, the extra hostname's included, has its own default deny;
`plain-extra` is refused for every caller, as `plain` is.

**AC-ISO-9 — A request can't choose its tenant.** *(R+L)* A request in
`team-a-test` whose own labels say `stakater.com/tenant: team-b` gets a
listener for `team-a`'s namespaces and `*.team-a.apis.example.com`, never
team-b's. A request can set no parameter: every parameter of `api-gateway` is
`disableOverride`, and an instance that sets one fails
(`OverrideNotAllowed`).

## Authentication and authorization

**AC-AUTH-1 — No token, no entry.** *(L)* A request to `orders` without a token
is refused with `401`; with `shop`'s token, `200`.

**AC-AUTH-2 — An invalid token is refused.** *(L)* An expired token, a token
from another issuer, and a token for another audience are each refused with
`401`; a fresh `shop` token gets `200`.

**AC-AUTH-3 — A valid token without the API is refused.** *(L)* `bare` and
`near` are refused `orders` with `403` (`near`'s `api.team-a.orders2` must not
match `api.team-a.orders`); `shop` gets `200`.

**AC-AUTH-4 — Caller headers never reach the application.** *(L)* `shop` sends
`x-sub: admin` and `x-roles: api.team-b.billing`; the echo backend reports
`x-sub` = `shop` and `x-roles` = `shop`'s `allowed_apis` from the token. A
request without the headers reports the same values.

**AC-AUTH-5 — A route without the annotation serves nothing.** *(L)* Every
fixture caller is refused on `plain` (`403`); `plain` is listed as "not an
API" in `team-a`'s status ConfigMap.

**AC-AUTH-6 — A route-level policy can't weaken the baseline.** *(L)* As a
cluster admin (past admission), add to `orders`, one at a time, a route-level
`AuthPolicy` with: an anonymous authentication source; a second issuer whose
tokens carry the platform audience; a top-level `when` that is false. In every
case a request without a token, or with the second issuer's token, never gets
a `2xx`; `shop` still gets `200`.

**AC-AUTH-7 — No moment without a token check.** *(L)* From the moment a new
annotated route is accepted, a request to it without a token, sent in a
tight loop, never gets a `2xx`.

## Rate limits

**AC-RL-1 — The tier limit holds.** *(L)* `shop` (`silver`) calling `orders`
in a loop gets `429` after its tier's limit within the window; the first
requests got `200`.

**AC-RL-2 — A caller without a known tier gets the lowest.** *(R+L)* A token
with `allowed_apis: [api.team-a.orders]` and no tier claim, and one with tier
`platinum` (not defined by the platform), each get `429` at the `bronze`
limit. Render: every token matches at least one tier predicate.

**AC-RL-3 — Counters are per caller.** *(L)* While `shop` is at its limit,
`core` calling `a-orders` and a second `silver` client calling `orders` still
get `200`.

## Render

**AC-R-1 — No `EnvoyFilter`, no `WasmPlugin`.** *(R)* For every fixture, no
rendered object is an `EnvoyFilter`, a `WasmPlugin` or a `TrafficExtension`.

**AC-R-2 — Every tenant gateway has its baseline.** *(R)* For every tenant:
one `Gateway`, its autoscaling ConfigMap, the Istio token floor, a default
deny per listener, a gateway-level `AuthPolicy` with `overrides`, the fixed
`when`, the issuer pin and the `azp` and `tier` export, and a gateway-level
`RateLimitPolicy` with `overrides`. Removing any of them from the template
fails the render check (mutation test).

**AC-R-3 — No security switch reaches a tenant.** *(R)* The per-tenant chart's
values schema has no key for the issuer, audience, claim names, header names,
tiers or the backend lock; a `tenantValues` entry for any of them fails the
render with a message naming the key.

**AC-R-4 — Allowed-API rules are derived and closed.** *(R)* Every route-level
rule is `api.<tenant>.<api>` or that value followed by `.`; a platform prefix
setting without the tenant or the API in it fails the render.

**AC-R-5 — The listener takes only its tenant.** *(R)* Every tenant gateway's
listener has `allowedRoutes.namespaces.from: Selector` on
`stakater.com/tenant: <tenant>` and hostname `*.<tenant>.<base domain>` (or a
granted extra hostname); no listener has `from: All`.

**AC-R-6 — Route-level policies can't weaken the baseline.** *(R)* No
rendered route-level `AuthPolicy` has an `authentication` rule, a top-level
`when`, or a rule named like a baseline rule; a fixture that adds one fails
the render check.

## Lifecycle

**AC-LIFE-1 — A team's request gets the tenant's gateway.** *(R+L)* A new
tenant `team-c` has no gateway until its team creates a `TemplateInstance` of
`api-gateway`, with no parameters, in `team-c-dev`. Then `team-c-dev` has a
`Gateway` named like the request with `Programmed=True`, its autoscaler, its
gateway-level policies, and `<request>-status` saying `ok`, with no other
step.

**AC-LIFE-5 — A tenant has one gateway.** *(R+L)* `extra` in `team-a-test`
renders no `Gateway`; its `extra-status` says `refused` and names
`team-a-dev/api-gateway`. `stray-request` in `unlabelled` is refused too
(`targetNamespaces`, and the parent's list). Deleting `api-gateway` makes
`extra` the owner, and `team-a-test` gets the gateway.

**AC-LIFE-6 — A team can't change its gateway.** *(L)* As `alice`, editing or
deleting `team-a`'s `Gateway`, its settings ConfigMap or a gateway-level
policy is refused at admission (sync mode `strict`). Deleting the request
`api-gateway` removes the gateway and everything it rendered.

**AC-LIFE-2 — A deleted route takes its policies.** *(L)* Deleting route
`orders` removes its route-level `AuthPolicy` and its backend lock; `billing`
and `a-orders` are unchanged.

**AC-LIFE-3 — A deleted tenant takes its gateway.** *(L)* Deleting tenant
`team-b` removes its gateway (`gw` in `team-b-dev`) and its gateway-level policies; nothing in
`team-a` or `team` changes.

**AC-LIFE-4 — A hand edit is reverted.** *(L)* Editing `team-a`'s gateway-level
`AuthPolicy` (for example, removing the audience) is reverted by Template
Operator; AC-AUTH-2 passes afterwards.

## Operations

**AC-OPS-1 — The gateway follows the load.** *(L)* Idle, `team-a`'s gateway
runs at the platform's minimum replicas; under load it scales up and back down;
a `PodDisruptionBudget` keeps one pod during a node drain.

**AC-OPS-2 — Problems are visible.** *(R+L)* `team-a`'s status ConfigMaps
list: `stray` as `outside-mesh`, `legacy` as `invalid`, a second route that
reuses `orders` as a duplicate (the older route keeps serving), `plain` as
not an API, a route for a host outside the tenant's hostnames as
`unattached`. The skipped-tenants ConfigMap lists a tenant whose name is not
a DNS label, an extra hostname inside the base domain, and two tenants'
overlapping extra hostnames.

**AC-OPS-3 — Upgrades keep the contract.** *(L)* The whole suite is green
before and after a Service Mesh minor upgrade, with no chart change.

**AC-OPS-4 — One version bump upgrades every tenant.** *(L)* Bumping the
per-tenant chart version re-renders every tenant within one sync, and the suite
stays green.

## Migration

**AC-MIG-1 — An API moves without an outage.** *(L)* A per-API gateway and the
tenant gateway serve `orders` side by side; the external entry point moves to
the tenant gateway; a client calling once per second through the move sees no
`5xx`; the per-API gateway is then removed.
