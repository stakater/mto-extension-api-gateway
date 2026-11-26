# Acceptance scenarios

The security contract, as testable scenarios. Stories cite these by id. Each
scenario names its **level**: **R** = render test (no cluster), **L** = live
(the kind lab in `hack/lab/` with upstream Istio in ambient mode and Template
Operator v2; the OpenShift-only parts on an OpenShift lab with Service Mesh 3,
the Multi-Tenant Operator and RHBK), **R+L** = both.

Rules for every live scenario:

- Call as the caller: a real token from the issuer for the fixture client,
  through the gateway's Service (kind) or the real OpenShift `Route`
  (OpenShift), never a port-forward to a gateway pod.
- A denial counts only with its status code (`401`, `403`, `429`, or a refused
  connection for the backend lock) **and** a matching allow on the same path by
  a caller who should pass.
- A denial must test a capability the caller would have if the guard broke.
- The backend is an echo service that returns the request headers it got, so a
  scenario can assert what reached the application.
- Mutation-test every new denial: break the guard on purpose and see the
  scenario fail.

Istio refuses a request without a token with `403` (the token floor is an
authorization rule), and a request with an invalid token with `401`.

Fixture:

- Tenants `team-a` (namespaces `team-a-dev`, `team-a-test`, and
  `team-a-outside`, which is not in the mesh), `team-b` (`team-b-dev`) and
  `team` (`team-core`), whose name is a prefix of `team-a`'s. `team-a` is
  granted the extra hostname `api.team-a.example.org` and the internal host
  `orders-team-a.apps.cluster.example.com` on the cluster router. The
  platform exempts `team-b` from the rate limit.
- Gateway requests (`TemplateInstance`s of `api-gateway`, no parameters):
  `api-gateway` in `team-a-dev` (team-a's gateway), with the annotations
  `claim-headers: client_id=x-client` and `correlation-id: "on"`; `gw` in
  `team-b-dev`, with the annotations `claim-headers: sub=authorization` (a
  reserved header) and `replicas: "9"` (not a knob); `gw` in `team-core`; a
  later second request `extra` in `team-a-test`; and a request
  `stray-request` in `unlabelled`, a namespace of no tenant.
- APIs (`api` instances with an echo backend, ADR-0005): `orders` in
  `team-a-dev` on `orders.team-a.apis.example.com` (`/orders/v2` →
  `/orders/v1`), `payments` in `team-a-test` on the same host
  (`/payments/v1`), `reports` in `team-a-dev` on
  `reports.team-a.apis.example.com` (`/reports/v1`), `billing` in `team-b-dev` on
  `billing.team-b.apis.example.com`, and `a-orders` in `team-core` on
  `a-orders.team.apis.example.com`.
- Routes without the annotation, written by an admin (tenants can't write
  routes, AC-ISO-6), attached to `team-a`'s gateway: `plain` (on
  `plain.team-a.apis.example.com`) and `plain-extra` (on
  `api.team-a.example.org`), both in `team-a-dev`.
- APIs whose backend can't be locked: `legacy` in `team-a-dev`
  (an `ExternalName` Service) and `stray` in `team-a-outside`.
- Clients of the issuer (roles in `allowed_apis`, one per API and tier):
  `shop` (`[api.team-a.orders.silver]`, `client_id: shop-app`), `bank`
  (`[api.team-b.billing.gold]`), `near` (`[api.team-a.orders2.silver]`),
  `core` (`[api.team.a-orders.silver]`), `bare` (no `allowed_apis`), `anon`
  (`[api.team-a.orders.silver]`, no `azp`), `legacy-shop`
  (`[api-orders-consumer-gold]`, today's role name).
- A pod `intruder` in `team-a-test`, in the mesh, and a pod `outsider` in
  `team-a-outside`, not in the mesh.
- A user `alice` with the Multi-Tenant Operator's editor role in `team-a`.

## Tenant separation

**AC-ISO-1 — A route can't attach to another tenant's gateway.** *(R+L)* An
`HTTPRoute` in `team-b-dev`, written by an admin (tenants can't write routes,
AC-ISO-6), with a `parentRef` to `team-a`'s gateway
(`api-gateway` in `team-a-dev`) is not accepted (route status
`Accepted=False`); a request for its host through `team-a`'s gateway gets no
route. `billing`, attached to `team-b`, is accepted.

**AC-ISO-2 — A host outside the tenant's hostnames is never served.** *(L)* A
route in `team-a-dev`, written by an admin, for `x.team-b.apis.example.com`
doesn't attach
(`Accepted=False`, listed as `unattached`); a request for that host through
the real entry point never reaches `team-a`'s backend. `orders` attaches and
serves.

**AC-ISO-3 — A caller for another tenant's API is refused.** *(L)* `bank` is
refused `orders` with `403`; `shop` gets `200` on the same path.

**AC-ISO-4 — A prefix tenant doesn't reach its neighbour.** *(R+L)* The rule
rendered for `team-core`'s `a-orders` is `api.team.a-orders`, and no rule
rendered for tenant `team` matches a value that starts `api.team-a.`. `core` is
refused `orders` (`403`) and allowed `a-orders` (`200`).

**AC-ISO-5 — The backend answers only its tenant gateway, except the open
paths.** *(L)* `intruder` calling Service `orders` on `/orders/v1` is refused
by the waypoint (`403`); the same request through `team-a`'s gateway, as
`shop`, gets `200`; `intruder` calling `/metrics` and `/healthz` on the
Service gets the backend's answer; kubelet probes and the platform's
monitoring keep working. After a cluster admin adds an `ALLOW` policy for any
source on Service `orders`, `intruder` is still refused. A call from
`intruder` to an `orders` pod's IP, and calls from `outsider` (outside the
mesh) to the Service and to a pod's IP, are recorded as the known limit (M21,
Q21).

**AC-ISO-6 — Tenants can't change or impersonate their gateway.** *(L)* As
`alice`, each of these is refused, with the reason: creating a `Gateway`,
`EnvoyFilter`, `WasmPlugin` or `TrafficExtension` in `team-a-dev`; creating a
`RequestAuthentication`, `AuthorizationPolicy` or `Telemetry` that targets
`team-a`'s `Gateway` or selects its pods; creating a pod that uses the service
account `api-gateway-istio`; `exec`, `attach` or `port-forward` into a gateway
pod; labelling a pod `istio.io/dataplane-mode=none`; creating an OpenShift
`Route` for a host under `apis.example.com` (OpenShift); creating an
`HTTPRoute` in a tenant namespace; creating an `api` or `api-gateway` instance
with a `valueFrom` parameter. Creating an `api` instance, and an
`AuthorizationPolicy` for `alice`'s own workloads, is allowed.

**AC-ISO-7 — A backend the lock can't cover serves nothing.** *(R+L)* No
allowed-API rule is rendered for `legacy` or `stray`; both are refused for
every caller and listed as `invalid` and `outside-mesh`. An API whose
namespace has no `istio.io/use-waypoint` label is listed as `outside-mesh` and
serves nothing. `orders` serves.

**AC-ISO-8 — Every listener denies by default.** *(R+L)* The root-namespace
`ALLOW` that selects every tenant gateway has no rules; `plain-extra`, on the
extra hostname's listener, is refused for every caller, as `plain` is.
Render: a mutation that gives that `ALLOW` an empty rule (`rules: [{}]`)
fails the check.

**AC-ISO-9 — A request can't choose its tenant.** *(R+L)* A request in
`team-a-test` whose own labels say `stakater.com/tenant: team-b` gets a
listener for `team-a`'s namespaces and `*.team-a.apis.example.com`, never
team-b's. A request can set no parameter: every parameter of `api-gateway` is
`disableOverride`, and an instance that sets one fails
(`OverrideNotAllowed`).

**AC-ISO-10 — A shared host is split by path between tenants.** *(R+L,
OpenShift)* The platform grants `front.example.com` with `/orders` to
`team-a` and `/billing` to `team-b`. Through the real router, `shop` gets
`200` from `orders` on `/orders/v2/x`, and `bank` gets `200` from `billing` on
`/billing/x`; each request reaches only its own tenant's gateway. An `api`
instance of `team-a` with the path `/billing/x` on that host is `refused`. A
platform value that also grants `/orders/admin` to `team-b` is refused by the
parent and listed under `team-b.paths`. As `alice`, an OpenShift `Route` for
`front.example.com` is refused (AC-ISO-6). Render: each granted prefix has
one reencrypt `Route` to its tenant's gateway Service, and only a tenant with
prefixes has the `entry` listener.

**AC-ISO-11 — A team turns its backend lock off, unless the platform locks
it.** *(R+L)* With `backendLock: "off"` on `stray`, no lock and no waypoint are
rendered for it, the API serves, and `api-gateway-apis` lists it under
`unlocked`. With `team-a` in `backendLock.lockedTenants`, the same parameter
is refused with the reason in `api.stray`, the lock stays on, and the API
still serves nothing.
A render check fails on an open path that isn't in the platform's list, or
that uses a pattern.

**AC-ISO-12 — STRICT mTLS closes the path from outside the mesh, per
tenant.** *(R+L)* With `team-a` in `backendLock.strictMtlsTenants`,
`outsider` calling Service `orders` and an `orders` pod's IP is refused
(connection reset) on `/orders/v1` and on `/metrics`; `shop` through
`team-a`'s gateway gets `200`; the `orders` pod's kubelet probes pass and it
doesn't restart. Without the value, `outsider` reaches the open paths, as in
AC-ISO-5. Render: a `PeerAuthentication` `STRICT` is rendered only for a
locked API of a listed tenant, with the backend Service's selector.

**AC-ISO-13 — An internal host serves only the tenant it is granted to.**
*(R+L, OpenShift)* `orders` sets `internalHost:
orders-team-a.apps.cluster.example.com`. Through the cluster router, `shop`
gets `200` from `orders` on that host and `/orders/v2/x`, and `403` on
`/payments/v1/x` there. An `api` instance of `team-b` that names the same
internal host is `refused`; a platform value that grants it to `team-b` too is
refused by the parent. As `alice`, an OpenShift `Route` for that host is
refused (G.23). Render: one reencrypt `Route` with no path per granted
internal host, to `team-a`'s gateway Service, and the `entry` listener.

**AC-EXT-1 — An API with a backend outside the cluster.** *(R+L)* The `api`
instance `partner` sets `externalHost` to a lab host outside the mesh, with
`tls: SIMPLE` and the lab CA in `tlsSecret`. `shop`, with a token for
`api.team-a.partner`, gets the host's answer; the host saw its own name in
`Host`, the rewritten path, `x-sub` and `x-roles`, and no `Authorization`
header. A caller without the API's role gets `403`, and the rate limit
applies. With a wrong CA in the Secret, the call fails, and the API is never
served in plain text. With `tls: MUTUAL`, the host sees the gateway's client
certificate. Render: the `ServiceEntry` and `DestinationRule` are in the
gateway's namespace, the `ExternalName` Service in the instance's; the API is
listed as `external`, with no lock.

**AC-EXT-2 — Only the extension's external backends.** *(R)* An `api` instance
that sets both `service` and `externalHost`, or neither, is `refused`. A route
to an `ExternalName` Service written by hand serves nothing and is listed as
`invalid`.

## Authentication and authorization

**AC-AUTH-1 — No token, no entry.** *(L)* A request to `orders` without a token
is refused with `403`; with `shop`'s token, `200`.

**AC-AUTH-2 — An invalid token is refused.** *(L)* An expired token, a token
from another issuer, and a token for another audience are each refused (`401`
or `403`); a fresh `shop` token gets `200`.

**AC-AUTH-3 — A valid token without the API is refused.** *(L)* `bare` and
`near` are refused `orders` with `403` (`near`'s `api.team-a.orders2` must not
match `api.team-a.orders`); `shop` gets `200`.

**AC-AUTH-4 — Caller headers never reach the application.** *(L)* `shop` sends
`x-sub: admin`, `x_sub: admin` and `x-roles: api.team-b.billing`; the echo
backend reports `x-sub` = `shop`, `x-roles` = `shop`'s `allowed_apis` as
Istio encodes a list claim, and no `x_sub`. A request without the headers
reports the same values.

**AC-AUTH-5 — A route without the annotation serves nothing.** *(L)* Every
fixture caller is refused on `plain` (`403`); `plain` is listed as "not an
API" in `team-a`'s `api-gateway-apis` ConfigMap.

**AC-AUTH-6 — An extra policy can't let in a request without a valid token.**
*(L)* As a cluster admin (past admission), add to `team-a-dev`, one at a time:
an `AuthorizationPolicy` `ALLOW` for any request on `team-a`'s gateway; a
second `RequestAuthentication` for another issuer. In every case a request
without a token, or with the other issuer's token, never gets a `2xx`; `shop`
still gets `200`.

**AC-AUTH-7 — No moment without a token check.** *(L)* From the moment a new
API's route is accepted, and while `team-a`'s child is being applied or
deleted, a request to it without a token, sent in a tight loop, never gets a
`2xx`.

**AC-AUTH-8 — APIs share a host by path, and never overlap.** *(R+L)*
`orders` and `payments` share `orders.team-a.apis.example.com`. `shop` (only
`api.team-a.orders`) gets `200` on `/orders/v2/x`. It never reaches
`payments`' backend (`403` or `404`) on `/payments/v1/x`,
`/orders/v2/../../payments/v1/x`, `//payments/v1/x`,
`/orders/v2%2F..%2F..%2Fpayments/v1/x` or `/Payments/v1/x` (Q16). An `api` instance `orders-v2b` on `/orders/v2-beta`
does not overlap: all three APIs serve. An `api` instance `orders-admin` on
`/orders/v2/admin` overlaps `orders`: both get `403` for every caller and are
listed as a `path-conflict`; deleting `orders-admin` restores `200`. An `api`
instance with a wildcard host, a host outside the tenant's hostnames, or a
path with a `..` segment renders no route, and its ConfigMap says
`refused`.

**AC-AUTH-9 — Tokens come only from the `Authorization` header.** *(L)* `shop`'s
token sent as `?access_token=…`, with no `Authorization` header, is refused
(`403`); the same token in the header gets `200`.

**AC-AUTH-10 — A tenant trusts only its own issuers.** *(R+L)* The platform
trusts `shared` for every tenant and `team-b-sso` for `team-b` only. `bank`'s
token from `team-b-sso` gets `200` on `billing`. A token from `team-b-sso`
that claims `api.team-a.orders` never gets a `2xx` on `orders`. `shop`'s token
from `shared` is refused on `billing` when `team-b`'s list doesn't name
`shared`. Render: a platform value that puts `team-b-sso` in `auth.defaultIssuers`
or in `team-a`'s list is refused by the parent and listed; the floor lists
both issuers; `team-a`'s `RequestAuthentication` and API rules name only
`shared`.

**AC-AUTH-11 — An API's own Keycloak reaches only that API.** *(R+L)* The
platform registers `partner-kc` for `team-a`, and `orders` names it in
`issuers`. A `partner-kc` token with `api.team-a.orders` gets `200` on
`orders`; a `partner-kc` token that claims `api.team-a.payments` gets `403` on
`payments`; on `team-b`'s gateway it gets `401`. An `api` instance of `team-b`
that names `partner-kc` is `refused`. With `partner-kc` unreachable, its
tokens get `401` on `orders`, and `shared` tokens still get `200` on
`payments` (Q19).

**AC-AUTH-12 — Registering an issuer restarts nothing.** *(L)* While a client
calls `orders` once per second over one kept-open connection, the platform
registers a new issuer and an API starts to use it: no gateway, rate limit or
backend pod restarts, and the client sees no `5xx`; whether the connection is
closed and reopened is recorded (Q20).

## Rate limits

**AC-RL-1 — The tier limit holds.** *(L)* `shop` (`silver`) calling `orders`
in a loop gets `429` after its tier's limit within the window; the first
requests got `200`.

**AC-RL-2 — A caller without a known tier gets the lowest.** *(R+L)* A token
with `allowed_apis: [api.team-a.orders]` (no tier role), and one with
`api.team-a.orders.platinum` (a tier the platform doesn't define), each get
`429` at the `bronze` limit. A token with both `api.team-a.orders.bronze` and
`api.team-a.orders.gold` gets the `gold` limit. A token whose
`allowed_apis` is one string, not a list, is still limited (the expression
never fails, M20). A hyphenated API name gives the right tier. Render: every
API's tier expression checks the tiers from the highest rate down and ends
with the lowest tier.

**AC-RL-3 — Counters are per tenant, API and caller.** *(L)* While `shop` is
at its limit on `orders`, `shop` calling `payments` (another API of `team-a`
on the same host), `core` calling `a-orders` and a second `silver` client
calling `orders` still get `200`.

**AC-RL-4 — No caller id, no entry.** *(L)* `anon` (no `azp`) is refused
`orders` with `403`, so a token can't escape its counter; `shop` gets `200`.

**AC-RL-5 — The platform can exempt a tenant or one API.** *(R+L)* `bank`
calling `billing` far past the `gold` limit never gets `429`; `team-b`'s
gateway still has the rate limit filter (render), and its tenant is
`unlimited` in the rate limit service's configuration. With
`rateLimit.unlimitedApis: [team-a.payments]`, `shop` calling `payments` far
past its limit never gets `429`, and still gets `429` on `orders`. No gateway
annotation turns a limit off; only the `api` instance's `rateLimit` parameter
does (AC-RL-7).

**AC-RL-6 — A rate limiter outage follows the platform's choice.** *(L)* With
the rate limit service scaled to zero, `shop` gets `200` when the platform
value says fail open, and is refused when it says fail closed; both cases are
documented.

**AC-RL-7 — A team turns its API's limit off, unless the platform locks it.**
*(R+L)* With `rateLimit: "off"` on `reports`, `shop` calling `reports` far past
its limit never gets `429`, and still gets `429` on `orders`; the rate limit
filter stays, `reports` has no rate limit entry, and the tenant's status lists
it as off. With `team-a` in `rateLimit.lockedTenants`, the same parameter is
refused with the reason in `api.reports`, and `reports` keeps its limit.

**AC-RL-8 — A change of the limits rolls the service with no failed
request.** *(R+L)* While `shop` calls `orders` 10 times per second, the
platform changes the `silver` rate. A new `ratelimit-config-<hash>` is
rendered, the pods restart one at a time with none unavailable, no pod
restarts on its own, `shop` sees no `5xx`, and the new rate holds after the
rollout. Render: the `ConfigMap` is immutable and its name changes with its
content.

## Team settings

**AC-KNOB-1 — Valid settings apply.** *(R+L)* On `team-a`'s gateway, the echo
backend reports `x-client` = `shop-app` from the token, and a correlation
header with an id; `shop` sending `x-client: admin` still reports `shop-app`;
`shop` sending its own correlation header gets it back unchanged. With
`access-log` set and the platform's tracing on, the gateway's `Telemetry`
samples `telemetry.tracing.samplingPercentage` of its requests (render).

**AC-KNOB-2 — Invalid and unknown settings are refused and listed.** *(R+L)*
`team-b`'s `api-gateway-apis` ConfigMap lists `claim-headers` as refused
(`authorization` is reserved) and `replicas` as an unknown key, each with the
reason; `team-b`'s gateway serves `billing` with the defaults.

**AC-KNOB-3 — A setting can't touch the platform's headers.** *(R+L)* After
any change to `team-a`'s `claim-headers`, `x-sub` and `x-roles` are still set
from the token and a caller's copy never reaches the backend; a mapping to
`x-sub` is refused.

## Render

**AC-R-1 — Only the platform's filters.** *(R)* Every rendered `EnvoyFilter` is
one of the three allowlisted shapes (header removal, rate limit, correlation
ID), selects exactly one tenant gateway, matches only `jwt_authn`, `router` or
no name, and contains no Lua; no rendered object is a `WasmPlugin` or a
`TrafficExtension`. A fixture that adds any other filter fails.

**AC-R-2 — Every tenant gateway has its baseline.** *(R)* The bootstrap render
has the root-namespace `DENY` on `notRequestPrincipals` listing every issuer
in `auth.issuers`, and no other, and the empty `ALLOW`, both selecting the gateway label. For every
tenant with a gateway, the child renders the `RequestAuthentication` (token
only from the `Authorization` header), the header-removal filter and the rate
limit filter. Removing any of them from a template fails the check (mutation
test).

**AC-R-3 — No security knob on the gateway request.** *(R)* No team annotation
names the issuer, the audience, the allowed-APIs claim, the tiers, the rate
limit or the backend lock; such an annotation is listed as an unknown key and
changes nothing in the render. The team switches are an API's own rate limit
(AC-RL-7) and backend lock (AC-ISO-11), set on its `api` instance; no
annotation names either.

**AC-R-4 — Allowed-API rules are derived and closed.** *(R)* Every per-API
condition is exactly `api.<tenant>.<api>` and `api.<tenant>.<api>.*`, plus,
for an API in `migration.legacyRoles`, its old roles `<old>-<tier>` as exact
values, one per defined tier and never a wildcard; a platform prefix setting
without the tenant or the API in it fails the render.

**AC-R-5 — The listener takes only its tenant.** *(R)* Every tenant gateway's
listener has `allowedRoutes.namespaces.from: Selector` on
`stakater.com/tenant: <tenant>` and hostname `*.<tenant>.<base domain>` (or a
granted extra hostname); no listener has `from: All`. The only listener
without a hostname is `entry`, and only a tenant with shared-host prefixes
or internal hosts has it (ADR-0009); a fixture with any other listener without
a hostname, or with `entry` for a tenant with neither, fails.

**AC-R-6 — Per-API rules are scoped to their API's host and path.** *(R)*
Every per-API `ALLOW` names only its route's host, and its path as `<path>`
and `<path>/*` or its exact operations, requires `azp` and every mapped claim,
and accepts only its API's issuers; no per-API `ALLOW` has no hosts, and
only an API on `/` has no paths. A fixture that drops the hosts, the paths or
the `azp` condition fails.

**AC-R-7 — Gateways are internal.** *(R)* Every tenant `Gateway` sets
`networking.istio.io/service-type: ClusterIP` and the platform label in its
`infrastructure`.

## Lifecycle

**AC-LIFE-1 — A team's request gets the tenant's gateway.** *(R+L)* A new
tenant `team-c` has no gateway until its team creates a `TemplateInstance` of
`api-gateway`, with no parameters, in `team-c-dev`. Then `team-c-dev` has a
`Gateway` named like the request with `Programmed=True`, its autoscaler,
`<request>-status` saying `ok`, and the tenant's child renders the gateway's
policies, with no other step.

**AC-LIFE-2 — A deleted API takes its route and policies.** *(L)* Deleting
the `api` instance `orders` removes its route, its allowed-API rule and its
backend lock; `payments`, `billing` and `a-orders` are unchanged.

**AC-LIFE-3 — A deleted tenant takes its gateway.** *(L)* Deleting tenant
`team-b` removes its gateway (`gw` in `team-b-dev`) and its child; nothing in
`team-a` or `team` changes.

**AC-LIFE-4 — A hand edit is reverted.** *(L)* Editing `team-a`'s
`RequestAuthentication` (for example, removing the audience) is reverted by
Template Operator; AC-AUTH-2 passes afterwards.

**AC-LIFE-5 — A tenant has one gateway.** *(R+L)* `extra` in `team-a-test`
renders no `Gateway`; its `extra-status` says `refused` and names
`team-a-dev/api-gateway`. `stray-request` in `unlabelled` is refused too
(`targetNamespaces`, and the parent's list). Deleting `api-gateway` makes
`extra` the owner, and `team-a-test` gets the gateway.

**AC-LIFE-6 — A team can't change its gateway.** *(L)* As `alice`, editing or
deleting `team-a`'s `Gateway`, its settings ConfigMap or one of its policies is
refused at admission (sync mode `strict`). Deleting the request `api-gateway`
removes the gateway and everything it rendered.

## Operations

**AC-OPS-1 — The gateway follows the load.** *(L)* Idle, `team-a`'s gateway
runs at the platform's minimum replicas; under load it scales up and back down;
a `PodDisruptionBudget` keeps one pod during a node drain.

**AC-OPS-2 — Problems are visible.** *(R+L)* `team-a`'s status ConfigMaps
list: `stray` as `outside-mesh`, `legacy` as `invalid`, a second `api`
instance named `orders` in `team-a-test` as a duplicate (the older one keeps
serving), `plain` as not an API, overlapping paths on one host as a
`path-conflict`, an admin's route for a host outside the tenant's hostnames
as `unattached`. The skipped-tenants ConfigMap lists a
tenant whose name is not a DNS label, an extra hostname inside the base
domain, and two tenants' overlapping extra hostnames.

**AC-OPS-3 — Upgrades keep the contract.** *(L)* The whole suite is green
before and after a Service Mesh (Istio) minor upgrade, with no chart change.

**AC-OPS-4 — A chart release changes nothing until the platform promotes.**
*(L)* Installing a release with `[g1 g2]` and `rollout.default: g1` changes no
tenant's objects. Setting `rollout.default: g2` re-renders every tenant's
gateway and child within one sync, and the suite stays green.

**AC-OPS-5 — A new generation reaches a canary first.** *(R+L)* With
`rollout.canary.apis: [team-a.orders]`, only `orders`' route, rule, lock and
rate limit entry come from g2; `payments` and `team-b` stay on g1. With
`rollout.canary.tenants: [team-b]`, all of `team-b`'s objects come from g2.
Removing the entry moves them back to g1. A values file that names a
generation the release doesn't contain is refused by the schema, and the
error names it. A client calling `orders` once per second through every
change sees no `5xx` and no `403`.

**AC-OPS-6 — Restarts and mesh moves drop no request.** *(L)* Under a steady
load: a rolling restart of a tenant gateway and of a waypoint, and a move of
`team-a`'s gateway to another Istio revision and back, each end with no failed
request.

**AC-OPS-7 — The preflight works under Helm and Argo CD.** *(R+L)* Render:
the bootstrap chart contains no `lookup`; without an issuer, the schema
refuses the values and names the key; with `--api-versions` that lack
`security.istio.io/v1`, the render fails and names the API; no Template
carries a Helm hook. Live: on a cluster without the GatewayClass `istio`, the
preflight `Job` fails and its log names it, under `helm install` and as an
Argo CD `PreSync` hook; with everything in place it passes and the install
goes on.

**AC-OPS-8 — The gateway and the waypoint are scraped.** *(R+L)* With
`monitoring.podMonitor.enabled`, a `PodMonitor` selects `team-a`'s gateway
pods and one selects each waypoint, on the port `metrics` and
`/stats/prometheus`; Prometheus shows `istio_requests_total` for `orders`
from both. With the value off, neither is rendered.

## Migration

Production gateways move one API at a time, on the test cluster first. The
callers change nothing: not the address, the path, the token or the answer.

**AC-MIG-1 — An API moves, and moves back, without an outage.** *(L)* A
per-API gateway and the tenant gateway serve `orders` side by side, on the
same shared host and path. One change moves the entry point for that path to
the tenant gateway; one change moves it back. A client calling once per
second through both changes sees no `5xx` and no change of address. The
per-API gateway is removed only after the agreed period. An API with an
internal host keeps it: the platform grants the old name to the tenant, and
the old gateway's `Route` for it is deleted in the switch (R5).

**AC-MIG-2 — Today's tokens work unchanged.** *(L)* With
`migration.legacyRoles: {team-a.orders: api-orders-consumer}`, `legacy-shop`'s
current token (`api-orders-consumer-gold`) gets `200` and the `gold` limit on
`orders` through the tenant gateway, as through the per-API gateway; the same
token gets `403` on every other API. No change in the identity provider or in
any token is needed for the move. The parent refuses an old role name mapped
to APIs of two tenants.

**AC-MIG-3 — The backend gets what it reads today.** *(L)* Before the move,
the API team states which headers its backend reads (`x-sub`, `x-roles`,
others). The same test calls through both gateways give the backend the same
values for those headers, or the team accepts each difference in writing (for
example, `x-roles` now holds `api.<tenant>.<api>` names).

**AC-MIG-4 — The move is measured.** *(L)* For the moved path, the error rate,
the p95 latency and the count of `401`, `403` and `429` are compared for an
agreed period before and after the switch. A difference above the agreed
limit moves the path back.
