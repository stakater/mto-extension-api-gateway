# Acceptance scenarios

The secure gateway, the backend side, and the governance, as testable
scenarios. Stories cite these by id. Each scenario names its **level**:
**R** = render test (no cluster), **L** = live install (OpenShift 4.20+,
OpenShift Service Mesh 3.4 ambient, the shared rate-limit service, an identity
provider, the Multi-Tenant Operator with Template Operator v2), **R+L** = both.

Fixture: tenant `team-a` with gateway namespace `orders-gateway-test` and
application namespace `team-a-test` (service `orders-api` on port 80, meshed and
waypoint-labelled from the `Tenant`). API `orders`, external host
`api-team-a-test.apps.example.com`, tier `medium`. Identity provider realm
`apis`; consumer client `orders-consumer` whose token carries
`allowed_apis: [api-orders-consumer-read]`; a second client `other-consumer`
whose claim is `api-billing-consumer-read`. People: `ola` (team-a owner,
authors the `TemplateInstance`), `sam` (platform admin). The shared rate-limit
service runs in `api-gateway-system`.

## The secure gateway

**AC-GW-1 — One short request, a full gateway.** *(R+L)* `ola`'s
`TemplateInstance` (apiName, backend, host, tier) renders the `Gateway`,
`Route`/`HTTPRoute`, `RequestAuthentication`, consumer `AuthorizationPolicy`,
rate-limit and strip hooks, and `Telemetry`, and nothing else; on a live
install the external host serves `orders`.

**AC-GW-2 — Backend only through the gateway.** *(L)* A pod in `team-a-test`
calling `orders-api:80` directly is refused by `gw-only`; the gateway's call
succeeds.

**AC-GW-3 — mTLS to the backend.** *(L)* The gateway → `orders-api` call is
mTLS (HBONE via the waypoint); plaintext from the gateway is not accepted.

**AC-GW-4 — Shared waypoint.** *(R+L)* Two gateways whose backends are in
`team-a-test` share one waypoint; `gw-only` lists both gateway identities;
deleting one gateway leaves the waypoint and the other's entry.

## Security is baked, not switched

**AC-SEC-1 — No token, no entry.** *(L)* A call with no bearer token returns
`403`; an invalid/expired token returns `401`.

**AC-SEC-2 — Wrong API is refused.** *(L)* `other-consumer`'s token (claim
`api-billing-consumer-read`) against the `orders` gateway returns `403`;
`orders-consumer`'s token returns `200`.

**AC-SEC-3 — Security has no off switch.** *(R)* The Template exposes no
parameter named `auth*`, `allowedApis`, `allowGatewayAccessOnly` or
`rateLimit*`; a `TemplateInstance` that tries to set one is rejected by the
values schema. The `RequestAuthentication` and the token-requiring
`AuthorizationPolicy` are always both present.

**AC-SEC-4 — Consumer scope is derived.** *(R)* With `apiName: orders` the
consumer `AuthorizationPolicy` requires `allowed_apis` to match
`api-orders-consumer-*`; there is no field to set it to `*` or any other value.

**AC-SEC-5 — Caller identity headers stripped.** *(L)* A call with
`x-roles: admin` and `x-sub: attacker` reaches the backend with only the
gateway-set values (from the token); the caller's values are gone.

## Rate limiting

**AC-RL-1 — Always on.** *(R)* The rate-limit hook is rendered for every
gateway and references the configured service; no parameter disables it.

**AC-RL-2 — The tier is enforced.** *(L)* A loop of calls above the `medium`
tier's rate returns `429`; below it, `200`.

## Governance

**AC-GOV-1 — No route around the Template.** *(L)* `ola` hand-creating a
Gateway API `Gateway` or a waypoint, or setting `istio.io/use-waypoint`, in a
tenant namespace is refused at admission (by this extension's guardrail, or the
service-mesh extension's); the Template Operator and `sam` are not. (**Q9**.)

**AC-GOV-2 — Hostname bounded by the tenant.** *(R+L)* An `externalHost`
outside the tenant's `hostnamePattern` renders nothing and is reported
`InvalidHost`; two tenants cannot both claim one host.

## Lifecycle and operations

**AC-LIFE-1 — Clean teardown.** *(L)* Deleting the gateway `TemplateInstance`
removes its gateway-side objects and its `gw-only` entry; the shared waypoint
stays while another gateway uses the namespace.

**AC-LIFE-2 — Backend not meshed is reported.** *(R+L)* If `team-a-test` loses
its mesh or waypoint label, the gateway is reported `BackendNotMeshed`, not
silently out of the mesh.

**AC-OPS-1 — Health in one place.** *(R+L)* The parent TemplateInstance outputs
list per gateway: `Ready`, `BackendNotMeshed`, `InvalidHost`, `BackendMissing`,
and the last render time.

**AC-OPS-2 — Prerequisites are checked.** *(L)* An unreachable rate-limit
service or identity-provider JWKS is reported `PrerequisiteMissing` in the
outputs; rendering continues for gateways not affected.

**AC-OPS-3 — One Template, one version.** *(L)* The platform bumps the
`api-gateway` Template version; at the next render every gateway is on it, with
no change to any team's `TemplateInstance`.
