# Design

**Status:** proposed; every story is Draft. Baseline: OpenShift Service Mesh 3
in ambient mode, Gateway API v1, Red Hat Connectivity Link, Template Operator
v2 (versions in `gateway-baseline.md`). Facts are cited to
`gateway-baseline.md` by row (e.g. **K6**); decisions to ADRs. Open questions
are **Q1–Q12** in the baseline, owned by story G.0.

The extension reuses the shape of `mto-extension-vault-enterprise`, which is
built and tested: a bootstrap chart, a per-tenant chart pulled by Template
Operator, the parent fan-out per `Tenant`, the skipped-tenants ConfigMap,
`tenantValues`, the render harness and its rules (ADR-0001). Read its
`charts/README.md` first.

## 1. Scope

Every Multi-Tenant Operator tenant gets one API gateway, with the platform's
security baseline built in: token check, allowed-API rule, caller headers set
from the token, rate limit tiers, and a lock that makes the gateway the only
way to the backend. An API team publishes an API with a standard `HTTPRoute`
and one annotation. Non-goals: see `vision.md`.

## 2. Architecture

Two Helm charts, rendered through Template Operator v2 (ADR-0001). See
`diagrams.md`.

| Chart | Installed | Renders |
|---|---|---|
| `mto-extension-api-gateway-bootstrap` | once per cluster, by Helm | the parent `Template` and `TemplateInstance`; the child `Template`; the gateway namespace's shared objects; **per `Tenant`**: `Gateway` `<tenant>`, its autoscaling ConfigMap, its TLS certificate request, the gateway-level `AuthPolicy` (baseline, `overrides`), the gateway-level default deny, the gateway-level `RateLimitPolicy` (tiers, `overrides`); the skipped-tenants ConfigMap |
| `mto-extension-api-gateway` | never by hand; pulled per tenant | **per annotated `HTTPRoute`**: the route-level `AuthPolicy` (allowed-API rule) and the backend lock (Istio `AuthorizationPolicy`), in the route's namespace; the tenant's status ConfigMap |

The parent finds a tenant's namespaces by the label `stakater.com/tenant`
(T1). The child `TemplateInstance` gets the tenant's `HTTPRoute`s and
`Service`s as list parameters, scoped to those namespaces (T2), the same way
the Enterprise chart gets ServiceAccounts.

**Not rendered:** the GatewayClass, Service Mesh and its mesh settings,
Connectivity Link and its `Kuadrant` instance, the RHBK realm, clients and
roles, DNS records, OpenShift `Route`s or load balancers for the gateway
Services (§9), namespace labels (the `Tenant` sets them).

## 3. What is rendered

### 3.1 Per tenant, in the gateway namespace (bootstrap chart)

For tenant `team-a`, base domain `apis.example.com`, gateway namespace
`mto-api-gateways`.

| Kind | Name | What it does |
|---|---|---|
| `Gateway` (class from the bootstrap values: `istio`, or `openshift-default` on the OpenShift-provided mesh, K1) | `team-a` | One HTTPS listener `tenant` for `*.team-a.apis.example.com`, routes only from `stakater.com/tenant=team-a` namespaces (A1, A3); Service Mesh deploys `team-a-<class>` (M3) |
| `ConfigMap` | `team-a-gateway` | `spec.infrastructure.parametersRef` target: autoscaler and disruption budget, pod labels with the tenant (M3) |
| `Certificate` (or a platform-provided Secret) | `team-a-tls` | the listener's certificate (Q10) |
| `AuthPolicy` | `team-a-baseline` | targets the `Gateway`; `overrides` with `strategy: merge`: JWT from the platform issuer and audience; the tenant floor (the token must carry some `api.team-a.` value); `x-sub` and `x-roles` set from the token (K2–K4, K6) |
| `AuthPolicy` | `team-a-default-deny` | targets listener `tenant` (`sectionName`, A5); `defaults`: refuse every request; a route-level policy replaces it (K6, Q3) |
| `RateLimitPolicy` | `team-a-tiers` | targets the `Gateway`; `overrides`: one limit per tier, counted per caller (K5, K6) |

A policy holds bare rules, `defaults` or `overrides`, never two of them (K6).
So the baseline and the default deny are two policies at two levels: the
override on the `Gateway`, the default on its listener. `merge` keeps a
route's own rules (its allowed-API rule) next to the overrides; the default
`atomic` would replace them.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: team-a
  namespace: mto-api-gateways
  labels: { stakater.com/tenant: team-a }
spec:
  gatewayClassName: istio
  infrastructure:
    labels: { stakater.com/tenant: team-a }
    parametersRef: { group: "", kind: ConfigMap, name: team-a-gateway }
  listeners:
    - name: tenant
      hostname: "*.team-a.apis.example.com"
      port: 443
      protocol: HTTPS
      tls:
        mode: Terminate
        certificateRefs: [{ name: team-a-tls }]
      allowedRoutes:
        kinds: [{ kind: HTTPRoute }]
        namespaces:
          from: Selector
          selector:
            matchLabels: { stakater.com/tenant: team-a }
```

The gateway-level baseline, in shape (field names per K2–K6; G.0 confirms
them):

```yaml
apiVersion: kuadrant.io/v1
kind: AuthPolicy
metadata:
  name: team-a-baseline
  namespace: mto-api-gateways
spec:
  targetRef: { group: gateway.networking.k8s.io, kind: Gateway, name: team-a }
  overrides:
    strategy: merge          # keep the route's own rules (K6)
    rules:
      authentication:
        platform-issuer:
          jwt:
            issuerUrl: https://sso.example.com/realms/apis   # bootstrap value
      authorization:
        audience:            # the token is for the platform audience
          patternMatching:
            patterns:
              - predicate: "'apis' in auth.identity.aud"     # Q4: aud as string or list
        tenant-floor:        # some allowed_apis value starts with "api.team-a."
          patternMatching:
            patterns:
              - predicate: "auth.identity.allowed_apis.exists(v, v.startsWith('api.team-a.'))"
      response:
        success:
          headers:           # replace what the caller sent (K4, Q2)
            x-sub:   { plain: { expression: auth.identity.azp } }
            x-roles: { plain: { expression: "auth.identity.allowed_apis.join(',')" } }
---
apiVersion: kuadrant.io/v1
kind: AuthPolicy
metadata:
  name: team-a-default-deny
  namespace: mto-api-gateways
spec:
  targetRef: { group: gateway.networking.k8s.io, kind: Gateway, name: team-a, sectionName: tenant }
  defaults:                  # atomic: a route-level policy replaces all of it
    rules:
      authorization:
        no-api-rule:
          patternMatching:
            patterns:
              - predicate: "false"
```

```yaml
apiVersion: kuadrant.io/v1
kind: RateLimitPolicy
metadata:
  name: team-a-tiers
  namespace: mto-api-gateways
spec:
  targetRef: { group: gateway.networking.k8s.io, kind: Gateway, name: team-a }
  overrides:
    limits:
      gold:
        rates: [{ limit: 1000, window: 1s }]
        counters: [{ expression: auth.identity.azp }]
        when: [{ predicate: "auth.identity.tier == 'gold'" }]
      silver:
        rates: [{ limit: 50, window: 1s }]
        counters: [{ expression: auth.identity.azp }]
        when: [{ predicate: "auth.identity.tier == 'silver'" }]
      bronze:
        rates: [{ limit: 10, window: 1s }]
        counters: [{ expression: auth.identity.azp }]
        when: [{ predicate: "!has(auth.identity.tier) || auth.identity.tier == 'bronze'" }]
```

Tier names, rates, the tier claim, the caller claim (`azp`), issuer, audience,
the allowed-APIs claim and the header names are **bootstrap values**, one set
per cluster (ADR-0004). Example rates are the ones we see in practice.

### 3.2 Per API, in the route's namespace (per-tenant chart)

For the `HTTPRoute` `orders` in `team-a-dev` with
`api-gateway.stakater.com/api: orders` and a backend Service `orders`:

| Kind | Name | What it does |
|---|---|---|
| `AuthPolicy` | `api-gateway-orders` | targets `HTTPRoute` `orders`; replaces the default deny with the allowed-API rule `api.team-a.orders` (ADR-0006) |
| Istio `AuthorizationPolicy` | `api-gateway-orders` | selects the pods of Service `orders`; `ALLOW` only from the tenant gateway's service account and the platform's monitoring identity (ADR-0007, M4) |

```yaml
apiVersion: kuadrant.io/v1
kind: AuthPolicy
metadata:
  name: api-gateway-orders
  namespace: team-a-dev
spec:
  targetRef: { group: gateway.networking.k8s.io, kind: HTTPRoute, name: orders }
  rules:
    authorization:
      allowed-api:     # exactly api.team-a.orders, or api.team-a.orders.<role>
        patternMatching:
          patterns:
            - predicate: "auth.identity.allowed_apis.exists(v, v == 'api.team-a.orders' || v.startsWith('api.team-a.orders.'))"   # Q4
---
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: api-gateway-orders
  namespace: team-a-dev
spec:
  selector:
    matchLabels: { app: orders }      # copied from Service orders' selector
  action: ALLOW
  rules:
    - from:
        - source:
            principals:
              - cluster.local/ns/mto-api-gateways/sa/team-a-istio
              - cluster.local/ns/openshift-monitoring/sa/prometheus-k8s   # bootstrap value
```

No `ReferenceGrant`: the route and its backend are in the same namespace
(A2). The extension never writes to the `HTTPRoute` itself.

## 4. The security baseline (ADR-0004)

Every request on a tenant gateway passes, in order:

1. **Authentication** (override): a JWT from the platform issuer, valid, for
   the platform audience. Otherwise `401`.
1. **Tenant floor** (override): the allowed-APIs claim holds some value under
   `api.<tenant>.`. Otherwise `403`. A token for another tenant's API never
   passes this gateway, even on a route that has no rule of its own.
1. **Allowed-API rule** (route-level): the claim holds `api.<tenant>.<api>`,
   closed. Otherwise `403`. A route without one keeps the default deny: `403`.
1. **Rate limit** (override): the caller's tier limit. Otherwise `429`.
1. **Headers** (override): `x-sub` and `x-roles` set from the token,
   replacing anything the caller sent.
1. **Backend lock** (mesh): the backend accepts the call because it comes from
   the tenant gateway's identity.

The **render check** (`hack/`, in `make verify` from G.1) fails when, for any
fixture:

- a tenant gateway lacks any of the objects of §3.1, or a baseline policy uses
  `defaults` where it must use `overrides`;
- any rendered object is an `EnvoyFilter`, `WasmPlugin` or `TrafficExtension`
  (AC-R-1);
- an allowed-API pattern is not derived from the tenant and the API name, or
  is not closed (AC-R-4);
- a listener allows routes `from: All` or `Same`, or has no hostname
  (AC-R-5);
- the per-tenant chart's values schema has a key for a baseline setting
  (AC-R-3).

Every guard in the check has a mutation test, as in the Enterprise harness.

## 5. The allowed-API rule (ADR-0006)

| Part | Rule |
|---|---|
| Format | `<prefix>.<tenant>.<api>`, optionally followed by `.<anything>`; prefix `api` by default |
| Tenant | the `Tenant` name, a DNS label (no dot) |
| API | the annotation value, a DNS label (no dot), unique in the tenant |
| Closed | `api.team-a.orders` never matches `api.team-a.orders2`; `api.team.a-orders` never matches `api.team-a.orders` |
| Claim | `allowed_apis` by default; a list claim in the token. The platform may rename it |

The claim can hold several values; the check passes when any one value
matches. The `incl` operator only finds an exact value in a list (K3), so the
closed rule is a CEL `exists()` predicate. G.0 tests it on real tokens,
including a missing claim and a claim that is a single string (Q4); the
closed-segment rule is the contract either way.

## 6. Names

| Object | Name | Budget |
|---|---|---|
| `Gateway` | `<tenant>` | tenant name ≤ 63 (label value) |
| Gateway Deployment, Service, ServiceAccount | `<tenant>-<class>` (M3): `team-a-istio` | tenant ≤ 63 − 1 − class length (46 with `openshift-default`) |
| Gateway-level policies, ConfigMap, certificate | `<tenant>-baseline`, `<tenant>-default-deny`, `<tenant>-tiers`, `<tenant>-gateway`, `<tenant>-tls` | tenant ≤ 50 |
| Route-level objects | `api-gateway-<api>` | API name ≤ 52 |
| Hostname | `*.<tenant>.<base domain>` | DNS limits: label ≤ 63, name ≤ 253 |

The parent skips a tenant whose name is not a DNS label or is longer than
the budget above (50, or less with a long GatewayClass name), and one named
like a reserved name, and lists it in the
skipped-tenants ConfigMap with the reason.

## 7. Status, skips and conflicts

The per-tenant chart renders one ConfigMap, `api-gateway-status`, in each
tenant namespace that has a route attached to the tenant gateway:

| Key | Lists |
|---|---|
| `apis` | each API: route, host, path, backend, the rule `api.<tenant>.<api>` |
| `not-apis` | routes attached to the tenant gateway without the annotation (they serve nothing) |
| `duplicates` | routes that share an API name in the tenant (all of them skipped) |
| `invalid` | an API name that is not a DNS label; a backend not in the route's namespace |
| `outside-mesh` | a route whose namespace lacks the mesh labels (M5); its backend lock can't hold |

The parent lists **hostname conflicts** (an extra hostname granted to two
tenants: neither gets it) in the skipped-tenants ConfigMap.

## 8. Health and preflight

- **Preflight** (bootstrap chart, at install and on upgrade): the GatewayClass
  exists; the Gateway API, Connectivity Link and Istio security CRDs exist; a
  `Kuadrant` instance is ready; the issuer URL is set. A missing piece fails the
  install and names it.
- **Outputs** (Template Operator status outputs, as in the Enterprise
  extension): per tenant, the gateway's `Programmed` condition and each
  policy's `Enforced` condition, so a platform team sees a tenant whose
  baseline is not enforced.

## 9. Install requirements

- OpenShift with Gateway API CRDs, OpenShift Service Mesh 3 in ambient mode,
  and Red Hat Connectivity Link with a ready `Kuadrant` instance (K1).
- Template Operator v2 at the version the Enterprise extension needs (T2), with
  RBAC on the kinds of §3 (Q6).
- The Multi-Tenant Operator; tenant namespaces with the mesh labels set
  through the `Tenant` (M5).
- An OIDC issuer (RHBK) whose tokens carry the caller, the allowed-APIs claim
  and the tier claim.
- An entry point per tenant gateway: an OpenShift `Route` (re-encrypt) to the
  gateway Service, or a load balancer (Q10). The bootstrap chart renders the
  OpenShift `Route` when `exposure: route` (default); DNS for
  `*.<tenant>.<base domain>` points at the entry point.

## 10. Where this differs from the first proposal

The first proposal (a gateway chart published as a Template, one
`TemplateInstance` per API with a few parameters) set the goals this design
keeps: one chart owned by the platform, no security switches, a derived
allowed-API rule, one upgrade for all. It differs in four places:

| First proposal | This design | Why |
|---|---|---|
| a `TemplateInstance` per API, written by the team | an annotated `HTTPRoute`, written by the team | the standard API; no new contract to learn (ADR-0005) |
| one gateway per API | one gateway per tenant | fewer idle pods, one place for the baseline (ADR-0002) |
| `EnvoyFilter` for headers and rate limit | Connectivity Link policies | supported through upgrades (ADR-0003) |
| `api-<name>-consumer-*` | `api.<tenant>.<api>`, closed | no collision across tenants, no wildcard (ADR-0006) |

It also answers the proposal's open point about two namespaces: the route and
its backend are in one namespace, so the per-tenant chart renders both
route-level objects there, and the gateway lives in the platform namespace.

## 11. What this design can't do (documented, not hidden)

- **One issuer per cluster.** All tenants trust the same identity provider
  (G.13 if ever needed).
- **Identity-provider roles are manual.** The platform creates
  `api.<tenant>.<api>` roles in RHBK (G.11).
- **A shared gateway still shares pods.** One tenant's APIs share one gateway's
  capacity (G.12 for an API that needs its own).
- **The backend lock covers the pods behind annotated routes only.** Other
  services in the namespace keep the platform's other rules.
- **A hand-made policy by a cluster admin** in a tenant namespace can add
  rules on a route. It can't weaken the overrides (AC-AUTH-6), and the status
  outputs show it.
- **Behaviour under ambient mode, list-claim matching, header replacement and
  policy merging** is read from docs, not yet observed (Q1–Q5). G.0 settles
  them before any chart is written.
