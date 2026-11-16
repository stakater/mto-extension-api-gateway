# Design

**Status:** proposed; every story is Draft; the build is gated on M.0
(`vision.md`). Baseline: Red Hat OpenShift Service Mesh 3.4 (Istio 1.30,
Gateway API GA), ambient mode, on OpenShift 4.20+. Facts are cited to
`api-gateway-baseline.md` by row (e.g. **A1**, **sm:T6**); decisions to ADRs.

## 1. Scope

Four things (`vision.md`):

1. **The gateway Template:** one secure Envoy gateway per API per environment,
   rendered from a `TemplateInstance` a team commits (§3, §4).
1. **Baked security:** token validation, consumer authorization, header
   stripping, rate-limit hook, `gw-only` backend access and mTLS — in the
   Template, not parameters (§5).
1. **The backend side:** `ReferenceGrant`, `gw-only` and the waypoint rendered
   into the application namespace; mesh and waypoint labels from the `Tenant`
   (§6).
1. **Health:** reported in one place (§12).

Not features, but answered here: composition with the service-mesh extension
(§7), rate limiting (§8), telemetry (§9), configuration surface (§10).

## 2. Architecture

Two charts, no operator (ADR-0001, ADR-0004). See `diagrams.md`.

| Part | Repo | Does |
|---|---|---|
| `api-gateway-mto-bootstrap` chart | this repo | installed once per cluster: publishes the `api-gateway` `Template` and the `api-backend` `Template`; the backend-side `TemplateGroupInstance` per tenant; the optional admission guardrail (§7); a parent TemplateInstance for health; the values schema |
| `api-gateway` + `api-backend` charts | this repo, OCI | held inside the Templates; `api-gateway` is rendered per gateway by a **team-authored** `TemplateInstance`; `api-backend` is rendered per application namespace by the platform `TemplateGroupInstance` |

**The Template is a library, not a per-tenant fan-out.** Unlike the
service-mesh extension (one child render per tenant), the gateway is authored
by the **team**: it commits a `TemplateInstance` of `api-gateway` in its gateway
namespace, synced by its own Argo CD app (sm:T6). The platform publishes the
Template; the team instantiates it; Template Operator renders the chart into the
team's namespace (ADR-0004). This is exactly the self-service model the
reference architecture proposed, made un-weakenable by keeping security in the
Template (§5) and gateways out of tenants' hands by admission (§7).

**Where things live.** Rendered objects carry
`app.kubernetes.io/managed-by: api-gateway-mto` and `sync.mode: revert` (sm:T6),
so a hand edit is reverted. Gateway-side objects live in the gateway namespace;
backend-side objects in the application namespace.

## 3. The gateway, per API per environment (ADR-0004)

One gateway serves **one API in one environment**. A team with two APIs and
three environments has six gateways, each its own `TemplateInstance`. Why not
one gateway per tenant or one shared gateway:

- Each API has its own external host, backend, consumer scope and tier; folding
  them into one gateway would mean per-route security config — the very thing a
  team gets wrong today.
- A gateway is a blast-radius boundary: a bad route change affects one API.
- It matches how teams already reason ("the orders gateway in test").

Cost: each `Gateway` is its own Deployment+Service (J1), plus one waypoint per
application namespace (J2). Scale is a spike question (**Q10**).

## 4. The `api-gateway` Template — rendered objects

Shown for the running example (`orders` in `test`). Gateway namespace
`orders-gateway-test`:

```yaml
# 1. The gateway (Gateway API, class istio) — its own Deployment + Service
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: orders-gateway
  namespace: orders-gateway-test
  labels: { app.kubernetes.io/managed-by: api-gateway-mto }
spec:
  gatewayClassName: istio
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
      tls: { mode: Terminate, certificateRefs: [{ name: orders-gateway-tls }] }
---
# 2. Route (OpenShift, re-encrypt) — the external host in front of the gateway (J5)
#    and an HTTPRoute — backend ref (needs the ReferenceGrant in team-a-test, §6) + path rewrite
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: orders, namespace: orders-gateway-test }
spec:
  parentRefs: [{ name: orders-gateway }]
  hostnames: ["api-team-a-test.apps.example.com"]
  rules:
    - matches: [{ path: { type: PathPrefix, value: /v2 } }]
      filters:
        - type: URLRewrite
          urlRewrite: { path: { type: ReplacePrefixMatch, replacePrefixMatch: /v1 } }
      backendRefs: [{ name: orders-api, namespace: team-a-test, port: 80 }]
---
# 3. Token validation — issuer/JWKS/audience from bootstrap values, not parameters (A1)
apiVersion: security.istio.io/v1
kind: RequestAuthentication
metadata: { name: orders-gateway, namespace: orders-gateway-test }
spec:
  targetRefs: [{ group: gateway.networking.k8s.io, kind: Gateway, name: orders-gateway }]  # VERIFY Q4
  jwtRules:
    - issuer: "https://keycloak.apps.example.com/realms/apis"
      jwksUri: "https://keycloak.apps.example.com/realms/apis/protocol/openid-connect/certs"
      audiences: ["api"]
---
# 4. Consumer authorization — require a valid token whose claim matches the DERIVED scope + the host (A2, ADR-0003)
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata: { name: orders-gateway-consumer, namespace: orders-gateway-test }
spec:
  targetRefs: [{ group: gateway.networking.k8s.io, kind: Gateway, name: orders-gateway }]
  action: ALLOW
  rules:
    - from: [{ source: { requestPrincipals: ["*"] } }]        # a valid token is required
      to:   [{ operation: { hosts: ["api-team-a-test.apps.example.com"] } }]
      when:
        - key: request.auth.claims[allowed_apis]
          values: ["api-orders-consumer-*"]                   # DERIVED from apiName; no free text
```

Plus, on the same gateway and **always rendered** (§5): the header-strip and
rate-limit hooks (an `EnvoyFilter` in v1 unless **Q1** finds a supported
alternative), and a `Telemetry` object for log format and tracing (§9).

| Rendered object | Why it is always there |
|---|---|
| `Gateway` (class `istio`) | the proxy; one per API/env (J1, ADR-0004) |
| `Route` (re-encrypt) + `HTTPRoute` (rewrite) | external host and path; backend via `ReferenceGrant` (J3, J5) |
| `RequestAuthentication` | validates the token (A1) — issuer/audience from bootstrap values |
| `AuthorizationPolicy` (consumer) | **requires** a valid token and the derived claim and host (A1, A2, ADR-0003) |
| header-strip hook | removes caller `x-sub`/`x-roles` before the gateway sets its own (A4) |
| rate-limit hook | calls the shared service; tier from the parameter, enforcement not optional (§8) |
| `Telemetry` | one telemetry path (§9) |

## 5. Security is baked, not switched (ADR-0002, ADR-0003)

The core decision. The Template exposes **only API-shaped parameters**; every
security-critical setting is inside the chart and has **no parameter**:

| Baked (no parameter) | What the team-model gets wrong today |
|---|---|
| a `RequestAuthentication` **and** a token-requiring `AuthorizationPolicy` are always rendered together | a `RequestAuthentication` alone, or `auth.enabled: false`, ships an open API (A1) |
| consumer scope = `api-<apiName>-consumer-*`, derived from `apiName` | a free-text `allowedApis`, `*` or a typo (ADR-0003) |
| caller `x-sub`/`x-roles` stripped before the gateway sets its own | a spoofed identity header reaching the backend (A4) |
| `gw-only` `AuthorizationPolicy` in the backend namespace, always | `allowGatewayAccessOnly: false` and an open backend (M2) |
| mTLS gateway → backend through the waypoint | plaintext to the backend |
| the rate-limit hook, always wired; tier is the only knob | `rateLimit.enabled: false` (§8) |

**Exposed parameters** (the whole surface a team controls):

| Parameter | Meaning | Bounded by |
|---|---|---|
| `apiName` | the API this gateway serves | derives the consumer scope; must match `^[a-z][a-z0-9-]*$` |
| `backendNamespace`, `backendService`, `backendPort`, `backendPath` | where the backend is | `backendNamespace` must belong to the same tenant (T1) |
| `exposedPath` | the external path | — |
| `externalHost` | the external hostname | must be under the tenant's domain (§7, a guard) |
| `tier` | the rate-limit class | one of the platform's tiers (§8) |
| `corrId` (optional, default off) | add a correlation-id filter | — |
| `logFormat` (optional) | one of the platform's named log formats | an enum, not free text |

Install-time (bootstrap) values — one per cluster, not per gateway: the issuer
URL, JWKS URI and audiences; the rate-limit service reference; the per-tenant
domain pattern; the mesh mode; gateway replica count; the platform identities
for the guardrail (§7, §10).

## 6. The backend side, and membership from the Tenant (ADR-0005)

A gateway writes to **two** namespaces. The gateway side (§4) is the team's
`TemplateInstance`. The backend side is the platform's, because it is shared by
every gateway whose backend is in that application namespace, and because mesh
membership belongs in the reviewed `Tenant`, not the gateway chart.

**Mesh and waypoint labels come from the `Tenant`** (T2), set by the platform in
`platform-tenants`, exactly as the service-mesh extension does it:

```yaml
# Tenant team-a (excerpt)
spec:
  namespaces:
    withTenantPrefix: [test, prod]            # team-a-test, team-a-prod
    metadata:
      specific:
        - namespaces: [team-a-test]
          labels:
            istio.io/dataplane-mode: ambient
            istio.io/use-waypoint: team-a-test-waypoint
```

The extension writes **no** namespace label (sm:§3): the Multi-Tenant Operator
owns namespaces, and the label belongs in the `Tenant`.

**The `api-backend` Template**, rendered by a platform `TemplateGroupInstance`
once per application namespace (**Q2**, **Q3**):

```yaml
# in team-a-test
---
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant                            # let the gateway's HTTPRoute reach orders-api (J3)
metadata: { name: from-orders-gateway-test, namespace: team-a-test }
spec:
  from: [{ group: gateway.networking.k8s.io, kind: HTTPRoute, namespace: orders-gateway-test }]
  to:   [{ group: "", kind: Service }]
---
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy                        # gw-only: only the gateway identity may reach the backend (M2)
metadata: { name: gw-only, namespace: team-a-test }
spec:
  action: ALLOW
  rules:
    - from: [{ source: { principals: ["cluster.local/ns/orders-gateway-test/sa/orders-gateway-istio"] } }]
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway                                    # the waypoint for the namespace (J2)
metadata: { name: team-a-test-waypoint, namespace: team-a-test }
spec:
  gatewayClassName: istio-waypoint
  listeners: [{ name: mesh, port: 15008, protocol: HBONE }]
```

The waypoint is **one per application namespace**, shared by every gateway whose
backend lives there; the `gw-only` policy lists every gateway serving that
namespace. The `TemplateGroupInstance` reconciles both from the set of gateways
in the tenant (**Q2**).

### 6.1 Backend placement and hostnames (open decisions)

The reference architecture shows three backend placements and two hostname
models; v1's support for each is an open decision (`roadmap.md`).

| Backend placement | Backend side | Status |
|---|---|---|
| Separate application namespace (`<team>-<env>`); gateway in `<api>-gateway-<env>` | `ReferenceGrant` + `gw-only` + waypoint in the application namespace (§6) | **v1 default** |
| Gateway and backend in the **same** namespace | no `ReferenceGrant` needed; `gw-only` still scopes the backend to the gateway identity | candidate for v1 |
| Backend **outside the cluster** (an `ExternalName` Service) | no in-cluster `gw-only`; the gateway's egress and the external TLS are the boundary | later; needs its own egress security story |

**Hostnames.** v1 gives each gateway a **per-API host** bounded by the tenant's
`hostnamePattern` (§7). A **shared host** with path-based routing across a
tenant's APIs (one hostname, many `HTTPRoute`s) is an alternative; it
concentrates blast radius on one host and is deferred.

**Parameter derivation.** The Template may derive `backendNamespace` and
`externalHost` from the gateway namespace name, so that between environments
only the namespace changes and a team sets as little as `apiName` and the
backend service. Whether to derive these or keep them explicit parameters is an
open decision — fewer parameters against clearer intent.

## 7. Composition with the service-mesh extension (ADR-0006)

This extension governs **north-south** (into a tenant); the service-mesh
extension governs **east-west** (between tenants). They compose:

- The service-mesh extension forbids tenants from creating Gateway API
  `Gateway`s and waypoints, but **exempts platform identities** (X1, sm:ADR-0005).
  The gateway and waypoint here are rendered by the **Template Operator
  identity**, so they are the sanctioned exception. A team's hand-written
  `Gateway` is refused. This is what makes the Template the only way in.
- **If the service-mesh extension is not installed,** this extension ships its
  own optional admission guardrail (the same shape) so a team still can't
  route around the Template. With it installed, that guardrail is redundant and
  turned off (**Q9**).
- A gateway fronts its **own** tenant's backend, so the service-mesh boundary
  needs no cross-tenant exception for it (same-tenant calls pass, sm:A1). The
  gateway namespace and application namespace are both the tenant's.
- **Hostname ownership:** the `externalHost` parameter is checked against the
  tenant's domain pattern (e.g. `*.team-a.apps.example.com` or
  `api-team-a-<env>.apps.example.com`), so one tenant can't claim another's
  host — the same shape as the service-mesh extension's ingress-hostname guard.

Neither extension depends on the other at install time (X3).

## 8. Rate limiting (ADR-0007)

- The shared Envoy rate-limit service (+ Redis) is a **platform prerequisite**,
  not built here (D1). Its reference is a bootstrap value.
- Every gateway is wired to call it; there is **no parameter to disable** it.
  The `tier` parameter picks a request-rate class the platform defines.
- **The attachment mechanism is the open risk.** In the reference architecture
  it is an `EnvoyFilter`, which Istio discourages as unstable across upgrades
  (D3, D4). **Q1** settles whether 3.4 offers a supported alternative for a
  Gateway API gateway. If not, the extension owns a small, well-tested
  `EnvoyFilter` and carries it across mesh upgrades — a cost ADR-0007 accepts
  explicitly and the vision flags.
- **Tier placement** — per gateway or per consumer token — is **Q8**; the
  design treats `tier` as a per-gateway default and leaves per-consumer tiering
  to a later story if the spike shows the token carries it.

## 9. Telemetry (ADR-0010)

**One path, no second pipeline** — the same decision as the service-mesh
extension (sm:ADR-0007). The gateway's `Telemetry` object sets the platform's
log format and enables tracing through the platform's OpenTelemetry collector;
the collector routes to the tenant by the pod's namespace through the Grafana
extension's telemetry gateways. The extension renders the per-gateway
`Telemetry` object (log format, tracing on); it renders no collector or
pipeline.

## 10. Configuration surface

```yaml
# bootstrap (install-time) values — one per cluster
issuer:
  url: https://keycloak.apps.example.com/realms/apis
  jwksUri: https://keycloak.apps.example.com/realms/apis/protocol/openid-connect/certs
  audiences: [api]
  consumerClaim: allowed_apis               # the claim the gateway authorizes on
rateLimit:
  service: ratelimit.api-gateway-system.svc.cluster.local:8081
  tiers: [low, medium, high]                # the allowed values of the `tier` parameter
hostnamePattern: "api-{tenant}-{env}.apps.example.com"   # bounds externalHost per tenant (§7)
mesh:
  mode: ambient                             # ambient | sidecar (ambient first, ADR-0008)
gateway:
  replicas: 3
guardrail:
  mode: Deny                                # Deny | Warn | Off (Off when the service-mesh extension guards)
platformIdentities:
  serviceAccounts:
    - system:serviceaccount:template-operator:template-operator-controller-manager
    - system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller
  groups: [platform-admins]
render:
  syncMode: revert
```

## 11. Lifecycle

| Event | Rendered |
|---|---|
| Team commits a gateway `TemplateInstance` | the gateway side (§4); the backend side appears when the application namespace is in the tenant and labelled |
| Team changes a parameter (host, path, backend) | re-rendered; security unchanged (it has no parameter) |
| Team deletes the `TemplateInstance` | gateway-side objects go; the backend-side `gw-only` entry for that gateway is removed; the waypoint stays while another gateway uses the namespace |
| Platform bumps the Template version | every gateway on the new version at the next render |
| Namespace loses the mesh/waypoint label | reported (§12); gateway is effectively out of the mesh until the `Tenant` is fixed |
| Tenant deleted | gateways go with its namespaces |

## 12. Health

In the parent TemplateInstance outputs, per gateway: `Ready`;
`BackendNotMeshed` (the application namespace lacks the mesh or waypoint label);
`InvalidHost` (`externalHost` outside the tenant's pattern); `BackendMissing`
(the backend Service not found); last render time. Cluster-wide
`PrerequisiteMissing`: no rate-limit service reachable at the configured
reference; the identity provider's JWKS unreachable; Template Operator missing.

## 13. Install prerequisites (documented, checked where observable)

- OpenShift 4.20+; Red Hat OpenShift Service Mesh 3.4 (3.3 floor), ambient
  enabled, discovery selectors covering tenant namespaces.
- A shared Envoy rate-limit service (+ Redis) reachable at a known address.
- An identity provider (Red Hat build of Keycloak) with a realm issuing
  consumer tokens, and the consumer clients/roles provisioned (a prerequisite
  in v1; ADR-0009).
- The Multi-Tenant Operator with Template Operator v2; tenant namespaces
  labelled for the mesh and the waypoint from the `Tenant` (ADR-0005).
- TLS certificates for the external hosts (the platform's certificate flow).
- Recommended: the service-mesh extension, for the guardrail that makes the
  Template the only ingress path (§7); otherwise this extension's own guardrail.
- For telemetry: the platform collector and the Grafana extension's telemetry
  gateways (§9).

## 14. What it can't do — say so

| Wanted | Why not | Instead |
|---|---|---|
| one gateway for all of a tenant's APIs | per-API security/host/scope would become per-route config — the footgun this removes | one gateway per API per environment (ADR-0004) |
| provision the consumer client and role | the identity provider is a prerequisite; this is a REST API, not a rendered object | a platform chart in v1; a seam with the Keycloak extension later (ADR-0009) |
| rate-limit without an `EnvoyFilter` | depends on what 3.4 supports for a Gateway API gateway | **Q1**; the extension owns a tested `EnvoyFilter` meanwhile (ADR-0007) |
| per-consumer tiers | the reference ties the tier to the gateway; token-carried tiers are unproven here | **Q8**; a later story |
| stop a compromised backend pod sending traffic | the mesh secures the server side, not a pod against itself (sm:S1) | out of scope; the boundary and `gw-only` still apply |
| human (end-user) authentication at the gateway | the gateway authenticates **machine consumers**; end-user auth is the application's job | out of scope; see `vision.md` honesty |
| several clusters | one mesh per cluster in v1 | later, with Advanced Cluster Management |
