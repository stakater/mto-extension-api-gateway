# Design

**Status:** proposed; every story is Draft. Baseline: OpenShift Service Mesh 3
in ambient mode, Gateway API v1, Red Hat Connectivity Link, Template Operator
v2 (versions in `gateway-baseline.md`). Facts are cited to
`gateway-baseline.md` by row (e.g. **K6**); decisions to ADRs. Open questions
are **Q1–Q13** in the baseline, owned by story G.0.

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
roles, DNS records, namespace labels (the `Tenant` sets them). The entry point
to each gateway (OpenShift `Route` or load balancer) is open until G.0 (§9).

## 3. What is rendered

### 3.1 Per tenant, in the gateway namespace (bootstrap chart)

For tenant `team-a`, base domain `apis.example.com`, gateway namespace
`mto-api-gateways`.

| Kind | Name | What it does |
|---|---|---|
| `Gateway` (class `istio`, from the ambient mesh's own control plane, K1) | `team-a` | One HTTPS listener `tenant` for `*.team-a.apis.example.com`, routes only from `stakater.com/tenant=team-a` namespaces (A1, A3); Service Mesh deploys `team-a-istio` (M3) |
| `ConfigMap` | `team-a-gateway` | `spec.infrastructure.parametersRef` target: autoscaler and disruption budget, pod labels with the tenant (M3) |
| `Certificate` (or a platform-provided Secret) | `team-a-tls` | the listener's certificate (Q10) |
| `AuthPolicy` | `team-a-baseline` | targets the `Gateway`; `overrides` with `strategy: merge`: a fixed top-level condition; JWT from the platform issuer, with the issuer pinned and the audience checked; the tenant floor (the token must carry some `api.team-a.` value); `x-sub` and `x-roles` set from the token; `azp` and `tier` exported for the rate limit (K2–K4, K6, K10) |
| `AuthPolicy` | `team-a-deny-<listener>` | one per listener (`sectionName`, A5), extra-hostname listeners included; `defaults`: refuse every request; a route-level policy replaces it (K6, Q3) |
| `RequestAuthentication` + Istio `AuthorizationPolicy` | `team-a-jwt-floor` | target the `Gateway`; Istio itself refuses a request without a valid token from the platform issuer, even before Connectivity Link has programmed a new route (M6, Q13) |
| `RateLimitPolicy` | `team-a-tiers` | targets the `Gateway`; `overrides`: one limit per tier, counted per caller (K5, K6) |

A policy holds bare rules, `defaults` or `overrides`, never two of them (K6).
So the baseline and the default deny are policies at two levels: the
override on the `Gateway`, a default on each listener. `merge` keeps a
route's own rules (its allowed-API rule) next to the overrides; the default
`atomic` would replace them.

`merge` replaces rules by name only, so the override also fixes what a
route-level policy could otherwise add to weaken it: the top-level condition
(`when`, merged as one rule; a route's `false` would skip the whole policy)
and the issuer (an `authorization` rule on `iss`, so a second
`authentication` source added by a route can't let in another issuer's
tokens). The render check refuses any route-level `authentication` rule or
`when` (§4).

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
    when:                    # fixed; a route can't add a condition that skips the policy
      - predicate: "true"
    rules:
      authentication:
        platform-issuer:
          jwt:
            issuerUrl: https://sso.example.com/realms/apis   # bootstrap value
      authorization:
        issuer:              # pinned: no other authentication source counts
          patternMatching:
            patterns:
              - predicate: "auth.identity.iss == 'https://sso.example.com/realms/apis'"
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
          filters:           # what the RateLimitPolicy can read as auth.identity.* (K10)
            identity:
              json:
                properties:
                  azp:  { expression: auth.identity.azp }
                  tier: { expression: "has(auth.identity.tier) ? auth.identity.tier : ''" }
---
apiVersion: kuadrant.io/v1
kind: AuthPolicy
metadata:
  name: team-a-deny-tenant   # one per listener: team-a-deny-<listener>
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
        when: [{ predicate: "!(auth.identity.tier in ['gold', 'silver'])" }]   # catch-all
```

The Istio-native token floor (no `EnvoyFilter`; M6):

```yaml
apiVersion: security.istio.io/v1
kind: RequestAuthentication
metadata: { name: team-a-jwt-floor, namespace: mto-api-gateways }
spec:
  targetRefs: [{ group: gateway.networking.k8s.io, kind: Gateway, name: team-a }]
  jwtRules: [{ issuer: https://sso.example.com/realms/apis }]
---
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata: { name: team-a-jwt-floor, namespace: mto-api-gateways }
spec:
  targetRefs: [{ group: gateway.networking.k8s.io, kind: Gateway, name: team-a }]
  action: DENY
  rules:
    - from: [{ source: { notRequestPrincipals: ["*"] } }]
```

Tier names, rates, the tier claim, the caller claim (`azp`), issuer, audience,
the allowed-APIs claim and the header names are **bootstrap values**, one set
per cluster (ADR-0004). Example rates are the ones we see in practice.
`bronze` is the catch-all: a token with no tier, or a tier the platform didn't
define, gets the lowest limit, never none. The tier claim is a single string
set by the platform in RHBK; callers can't choose it.

Which tenants get a gateway is a bootstrap value too: every tenant (default)
or a list. A tenant without a gateway has no listener, so its routes attach
nowhere.

### 3.2 Per API, in the route's namespace (per-tenant chart)

For the `HTTPRoute` `orders` in `team-a-dev` with
`api-gateway.stakater.com/api: orders` and a backend Service `orders`:

| Kind | Name | What it does |
|---|---|---|
| `AuthPolicy` | `api-gateway-orders` | targets `HTTPRoute` `orders`; replaces the default deny with the allowed-API rule `api.team-a.orders` (ADR-0006) |
| Istio `AuthorizationPolicy` | `api-gateway-orders-<service>` | one per backend Service of the route (every `backendRef`, mirrors included); selects the Service's pods; `DENY` on the Service's target ports from any identity but the tenant gateway's (ADR-0007, M4, M9) |

The route-level `AuthPolicy` is rendered **only when every backend can be
locked**: each `backendRef` is a `Service` with a selector, in the route's
namespace, and the namespace is in the mesh. Otherwise the route keeps the
default deny and serves nothing, and the status ConfigMap says why (§7). The
extension fails closed.

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
  action: DENY                         # an ALLOW from anyone else can't widen it
  rules:
    - from:
        - source:
            notPrincipals: [cluster.local/ns/mto-api-gateways/sa/team-a-istio]
      to:
        - operation:
            ports: ["8080"]            # the Service's target ports only
```

A caller outside the mesh has no identity, so it matches `notPrincipals` and is
refused too (M9). A metrics port that is not one of the Service's target ports
stays open to the platform's monitoring; metrics served on the API's own port
are refused (Q5).

No `ReferenceGrant`: the route and its backends are in the same namespace
(A2). The extension never writes to the `HTTPRoute` itself.

## 4. The security baseline (ADR-0004)

Every request on a tenant gateway passes, in order:

1. **Token floor** (Istio, on the gateway): a valid JWT from the platform
   issuer. Otherwise refused, even for a route that Connectivity Link has not
   programmed yet (Q13).
1. **Authentication** (override): a JWT from the platform issuer, valid, for
   the platform audience, with the issuer pinned. Otherwise `401` or `403`.
1. **Tenant floor** (override): the allowed-APIs claim holds some value under
   `api.<tenant>.`. Otherwise `403`. A token for another tenant's API never
   passes this gateway, even on a route that has no rule of its own.
1. **Allowed-API rule** (route-level): the claim holds `api.<tenant>.<api>`,
   closed. Otherwise `403`. A route without one keeps the default deny: `403`.
1. **Headers** (override, on success of the steps above): `x-sub` and
   `x-roles` set from the token, replacing anything the caller sent.
1. **Rate limit** (override): the caller's tier limit. Otherwise `429`.
1. **Backend lock** (mesh): on the API's ports, the backend refuses every
   identity but the tenant gateway's, and every caller outside the mesh.

The **render check** (`hack/`, in `make verify` from G.1) fails when, for any
fixture:

- a tenant gateway lacks any of the objects of §3.1 (a deny for every
  listener, the Istio floor included), or a baseline policy uses `defaults`
  where it must use `overrides`, or lacks the fixed `when`, the issuer pin or
  the exported `azp` and `tier`;
- a route-level policy has an `authentication` rule, a top-level `when`, or a
  rule named like a baseline rule;
- a route-level `AuthPolicy` is rendered for a route with a backend that can't
  be locked (§3.2), or a backend lock lacks its port list;
- some tier value, missing or unknown, matches no rate limit;
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
| Gateway Deployment, Service, ServiceAccount | `<tenant>-istio` (M3) | tenant ≤ 57 |
| Gateway-level objects | `<tenant>-baseline`, `<tenant>-deny-<listener>` (listeners `tenant`, `extra-<n>`), `<tenant>-jwt-floor`, `<tenant>-tiers`, `<tenant>-gateway`, `<tenant>-tls` | tenant ≤ 48 |
| Route-level objects | `api-gateway-<api>`, `api-gateway-<api>-<service>` | API name + Service name ≤ 50 |
| Hostname | `*.<tenant>.<base domain>` | DNS limits: label ≤ 63, name ≤ 253 |

The parent skips a tenant whose name is not a DNS label or is longer than
48 characters, and one named like a reserved name, and lists it in the
skipped-tenants ConfigMap with the reason.

## 7. Status, skips and conflicts

The per-tenant chart renders one ConfigMap, `api-gateway-status`, in each
tenant namespace that has a route attached to the tenant gateway:

| Key | Lists |
|---|---|
| `apis` | each API: route, host, path, backend, the rule `api.<tenant>.<api>` |
| `not-apis` | routes attached to the tenant gateway without the annotation (they serve nothing) |
| `duplicates` | routes that reuse an API name in the tenant: the oldest route keeps the API, later ones are skipped |
| `invalid` | an API name that is not a DNS label; a backend that is not a `Service` with a selector in the route's namespace (for example `ExternalName`, a Service without a selector, another kind): the route serves nothing |
| `outside-mesh` | a route whose namespace lacks the mesh labels (M5): the route serves nothing |
| `unattached` | annotated routes the gateway didn't accept, with the reason from the route's status (for example a host outside the tenant's hostnames) |

The parent lists **hostname conflicts** in the skipped-tenants ConfigMap: an
extra hostname granted to two tenants, or one that falls inside another
tenant's `*.<tenant>.<base domain>`. The check is a wildcard intersection,
not an equality. Neither tenant gets a conflicting hostname.

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
- An entry point per tenant gateway, decided in G.0 (Q10): a load balancer
  Service; an OpenShift `Route` (re-encrypt) per host; or one wildcard
  OpenShift `Route` per tenant, which needs the router to allow wildcard
  routes (`routeAdmission.wildcardPolicy: WildcardsAllowed`, refused by the
  default IngressController). G.1 renders the chosen one. DNS for
  `*.<tenant>.<base domain>` points at the entry point.
- **No tenant may claim a host under the base domain at any entry point.** A
  tenant can create OpenShift `Route`s; one for `dev.team-a.<base domain>` on
  the shared router would receive callers' tokens. So the base domain gets its
  own entry point (a dedicated IngressController for the gateway namespace, or
  a load balancer), DNS for the base domain points only there, and admission
  refuses a tenant's OpenShift `Route` under the base domain (G.8, Q10).
- The gateway class is `istio`, from the ambient mesh's control plane. The
  OpenShift-provided `openshift-default` class runs a separate control plane
  and certificate authority, so its gateway has no identity the ambient
  backends trust, and the backend lock can't work (K1).

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
- **The backend lock covers the API's ports on the pods behind annotated
  routes only.** Other ports and services keep the platform's other rules.
  Other in-mesh callers of the same ports are refused too; allowing named
  internal callers is G.17.
- **Backends outside the cluster are refused in v1.** An `ExternalName`
  backend can't be locked and could point anywhere, so the route serves
  nothing (G.16).
- **Unauthenticated floods are refused, not rate limited.** Rate limits count
  authenticated callers; the entry point (router or load balancer) limits the
  rest.
- **A hand-made policy by a cluster admin** in a tenant namespace can add
  authorization rules on a route. The fixed condition and the issuer pin keep
  it from weakening the overrides (AC-AUTH-6); the render check only covers
  what the charts render.
- **Behaviour under ambient mode, list-claim matching, header replacement,
  policy merging and the programming window** is read from docs and source,
  not yet observed (Q1–Q5, Q13). G.0 settles them before any chart is
  written.
