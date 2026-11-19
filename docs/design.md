# Design

**Status:** proposed; G.1 is built, the other stories are Draft. Baseline:
OpenShift Service Mesh 3 in ambient mode (upstream Istio on the kind lab),
Gateway API v1, Template Operator v2 (versions in `gateway-baseline.md`).
Facts are cited to `gateway-baseline.md` by row (e.g. **M6**); decisions to
ADRs. Open questions are **Q1–Q15** in the baseline, owned by stories G.19
(kind) and G.0 (OpenShift).

The extension reuses the shape of `mto-extension-vault-enterprise`, which is
built and tested: a bootstrap chart, a child `TemplateInstance` per tenant
fanned out by a parent, the skipped-tenants ConfigMap, the render harness and
its rules (ADR-0001). Read its `charts/README.md` first.

## 1. Scope

Every Multi-Tenant Operator tenant can have one API gateway, on request, with
the platform's security baseline built in: token check, allowed-API rule,
caller headers set from the token, rate limit tiers, and a lock that makes the
gateway the only way to the backend. A team asks for its gateway with one
`TemplateInstance` of the platform's `api-gateway` Template, in the namespace
where the gateway should run, and tunes a few non-security settings with
annotations on it. Then it publishes each API with a standard `HTTPRoute`, on
its own host, and one annotation. Non-goals: see `vision.md`.

## 2. Architecture

One Helm chart, rendered once per cluster, and Template Operator v2 objects
(ADR-0001). See `diagrams.md`.

| Piece | Created | Renders |
|---|---|---|
| `mto-extension-api-gateway-bootstrap` | once per cluster, by Helm, in the platform's namespace `mto-api-gateways` | the parent `Template` and `TemplateInstance`, the child Template `api-gateway-policy`, the token floor and default deny in the Istio root namespace (ADR-0004), the rate limit service (ADR-0003), the admission policy (ADR-0008) |
| The parent `TemplateInstance` | by the chart | the team-facing **`api-gateway` and `api` Templates**, the skipped-tenants ConfigMap, and **one child `TemplateInstance` per tenant that has a gateway** (ADR-0013) |
| A `TemplateInstance` of `api-gateway` | by the team, in the tenant namespace where its gateway should run; no parameters; optional knob annotations (ADR-0012) | **in its own namespace**: `Gateway` `<request>`, its settings ConfigMap, its certificates, and the request's status ConfigMap |
| A `TemplateInstance` of `api` | by the team, one per API, in the backend's namespace; six checked parameters (ADR-0005) | **in its own namespace**: the API's `HTTPRoute` `api.<api>` and its status ConfigMap `api.<api>` |
| A tenant's child `TemplateInstance` | by the parent, in `mto-api-gateways` | the tenant's gateway policy: `RequestAuthentication`, the platform's `EnvoyFilter`s, `Telemetry`; **per API route** the allowed-API rule (in the gateway's namespace) and the backend lock (in the route's namespace); the tenant's status ConfigMap `<request>-apis` |

**How the request stays trusted.** A team writes only the `TemplateInstance`'s
namespace, name and annotations. Every parameter of `api-gateway` is a
`disableOverride` default that the parent sets and keeps current (T2):

- `tenantOf` — namespace → tenant, from the label `stakater.com/tenant` (T1),
  for the tenants that may request a gateway. The team render reads its
  instance's tenant from here, never from the instance's labels;
- `owner` — tenant → the one request that gets its gateway: the oldest valid
  `TemplateInstance` of `api-gateway` in the tenant's namespaces. Every other
  request renders only a status ConfigMap that says why;
- `extraHostnames`, and the platform's gateway settings.

The annotations are read by the tenant's child, not by the team render, and
validated there (ADR-0012). The `api` Template gets the same platform
parameters, plus each tenant's gateway and hostnames, all `disableOverride`.
A team sets only an API's six parameters, which the template checks;
admission refuses `valueFrom` on both Templates' instances (ADR-0005, T9).
`api-gateway`, `api` and `api-gateway-policy` sync `strict`: Template
Operator's admission webhook refuses a team's edit or delete of anything
they rendered (T3). Only tenant namespaces may instantiate `api-gateway` and
`api` (`targetNamespaces` selector on the tenant label).

**Not rendered:** the GatewayClass, Service Mesh and its mesh settings
(including access log providers), Redis, the RHBK realm, clients and roles,
DNS records, namespace labels (the `Tenant` sets them). The entry point to
each gateway is open until G.0 measures it (§10).

## 3. What is rendered

Running example: tenant `team-a`, which asked with `TemplateInstance`
`api-gateway` in `team-a-dev`; base domain `apis.example.com`; one issuer for
every tenant, `https://sso.example.com/realms/apis`, audience `apis`. A
platform may also trust several issuers, or give a tenant its own
(ADR-0004).

### 3.1 Once per cluster (bootstrap chart)

| Kind | Name | What it does |
|---|---|---|
| `AuthorizationPolicy` (Istio root namespace) | `mto-api-gateway-token-floor` | `DENY` for every request without a valid token from one of the platform's issuers (`auth.issuers`), on every pod with the gateway label (M6, M12) |
| `AuthorizationPolicy` (Istio root namespace) | `mto-api-gateway-default-deny` | `ALLOW` with no rules on the same pods: whatever no API rule allows is refused (M12) |
| `Deployment`, `Service`, `ConfigMap` | `ratelimit` in `mto-api-gateways` | the rate limit service (Envoy's rate limit API) with its tier configuration from bootstrap values; Redis address and secret are values (ADR-0003) |
| `ValidatingAdmissionPolicy` + binding | `mto-api-gateway-tenants` | what tenant users may not do to a gateway (ADR-0008) |

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata: { name: mto-api-gateway-token-floor, namespace: istio-system }
spec:
  selector: { matchLabels: { api-gateway.stakater.com/gateway: "true" } }
  action: DENY
  rules:
    - from:
        - source:
            notRequestPrincipals: ["https://sso.example.com/realms/apis/*"]   # one per issuer
---
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata: { name: mto-api-gateway-default-deny, namespace: istio-system }
spec:
  selector: { matchLabels: { api-gateway.stakater.com/gateway: "true" } }
  action: ALLOW            # no rules: matches nothing (M12)
```

The rate limit service's configuration, built from the tiers (example rates
are the ones we see in practice):

```yaml
domain: mto-api-gateway
descriptors:
  - key: tenant
    value: team-b                 # a tenant exempted by the platform (ADR-0004)
    descriptors:
      - key: api
        descriptors:
          - key: tier
            descriptors: [{ key: azp, rate_limit: { unlimited: true } }]
  - key: tenant
    value: team-a                 # a tenant with one exempted API, team-a.reports
    descriptors:
      - key: api
        value: reports
        descriptors:
          - key: tier
            descriptors: [{ key: azp, rate_limit: { unlimited: true } }]
      - key: api                  # team-a's other APIs: the tiers, as below
        descriptors: [ ...the tier entries below... ]
  - key: tenant                   # every other tenant
    descriptors:
      - key: api                  # each API value gets its own counters
        descriptors:
          - key: tier
            value: gold
            descriptors: [{ key: azp, rate_limit: { unit: second, requests_per_unit: 100 } }]
          - key: tier
            value: silver
            descriptors: [{ key: azp, rate_limit: { unit: second, requests_per_unit: 50 } }]
          - key: tier             # bronze, and any tier the platform doesn't name
            descriptors: [{ key: azp, rate_limit: { unit: second, requests_per_unit: 10 } }]
```

A counter is kept for each tenant, API, tier and caller, so a caller's calls
to one API never use up its limit on another. The service matches a tenant's
own entry before the generic one and never falls back, so a tenant with an
exempted API gets the full tier tree under its own entry (M18).

### 3.2 Per request, in the request's namespace (`api-gateway` Template)

| Kind | Name | What it does |
|---|---|---|
| `Gateway` (class `istio`, ADR-0010) | `api-gateway` | listener `tenant` for `*.team-a.apis.example.com` (and `extra-<n>` per granted host, and `entry` with no hostname when the tenant has shared-host prefixes, ADR-0009), routes only from `stakater.com/tenant=team-a` namespaces (A1, A3); `ClusterIP` Service and the gateway label (M13, ADR-0002); Service Mesh deploys `api-gateway-istio` (M3) |
| `ConfigMap` | `api-gateway-infra` | `spec.infrastructure.parametersRef` target: autoscaler and disruption budget (M3) |
| `Certificate` (or a platform-provided Secret) | `api-gateway-tls`, `api-gateway-tls-extra-<n>` | one per listener (Q10); the `entry` listener's Secret `api-gateway-entry-tls` comes from OpenShift's service CA (R3) |
| OpenShift `Route` | `api-gateway-shared-<n>` | only with shared-host prefixes: one reencrypt `Route` per granted prefix, to the Service `api-gateway-istio` (ADR-0009, R1) |
| `ConfigMap` | `api-gateway-status` | `ok` with the tenant and host names, or `refused` with the reason |

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: api-gateway
  namespace: team-a-dev
  labels: { stakater.com/tenant: team-a }
spec:
  gatewayClassName: istio
  infrastructure:
    labels: { stakater.com/tenant: team-a, api-gateway.stakater.com/gateway: "true" }
    annotations: { networking.istio.io/service-type: ClusterIP }
    parametersRef: { group: "", kind: ConfigMap, name: api-gateway-infra }
  listeners:
    - name: tenant
      hostname: "*.team-a.apis.example.com"
      port: 443
      protocol: HTTPS
      tls:
        mode: Terminate
        certificateRefs: [{ name: api-gateway-tls }]
      allowedRoutes:
        kinds: [{ kind: HTTPRoute }]
        namespaces:
          from: Selector
          selector:
            matchLabels: { stakater.com/tenant: team-a }
```

### 3.3 Per tenant, in the gateway's namespace (child `api-gateway-policy`)

| Kind | Name | What it does |
|---|---|---|
| `RequestAuthentication` | `api-gateway-jwt` | targets the `Gateway`: one rule per issuer of the tenant, with its audiences (ADR-0004), token only from `Authorization` (M15); claim headers `x-sub` (`azp`), `x-roles` (`allowed_apis`) and the team's extras (ADR-0012) |
| `EnvoyFilter` | `api-gateway-strip-headers` | removes the caller's copies of every claim header, their underscore variants and the platform's reserved names, before `jwt_authn` (ADR-0003) |
| `EnvoyFilter` | `api-gateway-ratelimit` | Envoy's rate limit filter before `router`, and virtual-host actions with no name (M14): one entry per API, matched on the API's host and path, with the descriptors `tenant`, `api`, `tier` (default `bronze`), `azp` (M18) |
| `EnvoyFilter` | `api-gateway-correlation-id` | only with the knob: the platform's correlation header from `x-request-id` when the caller sent none |
| `Telemetry` | `api-gateway-telemetry` | only with the knobs: an access log provider from the platform's list, extra trace headers |
| `ConfigMap` | `api-gateway-apis` | the tenant's APIs, routes that are not APIs, conflicts, refused knobs (§7) |

```yaml
apiVersion: security.istio.io/v1
kind: RequestAuthentication
metadata: { name: api-gateway-jwt, namespace: team-a-dev }
spec:
  targetRefs: [{ group: gateway.networking.k8s.io, kind: Gateway, name: api-gateway }]
  jwtRules:                                   # one per issuer of team-a
    - issuer: https://sso.example.com/realms/apis
      audiences: [apis]
      fromHeaders: [{ name: Authorization, prefix: "Bearer " }]
      outputClaimToHeaders:
        - { header: x-sub, claim: azp }
        - { header: x-roles, claim: allowed_apis }
        - { header: x-client, claim: client_id }       # team extra (ADR-0012)
---
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata: { name: api-gateway-strip-headers, namespace: team-a-dev }
spec:
  workloadSelector:
    labels: { gateway.networking.k8s.io/gateway-name: api-gateway }
  configPatches:
    - applyTo: HTTP_FILTER
      match:
        context: GATEWAY
        listener:
          filterChain:
            filter:
              name: envoy.filters.network.http_connection_manager
              subFilter: { name: envoy.filters.http.jwt_authn }
      patch:
        operation: INSERT_BEFORE
        value:
          name: api-gateway.strip_claim_headers
          typed_config:
            "@type": type.googleapis.com/envoy.extensions.filters.http.header_mutation.v3.HeaderMutation
            mutations:
              request_mutations:
                - remove: x-sub
                - remove: x_sub
                - remove: x-roles
                - remove: x_roles
                - remove: x-client
                - remove: x_client
---
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata: { name: api-gateway-ratelimit, namespace: team-a-dev }
spec:
  workloadSelector:
    labels: { gateway.networking.k8s.io/gateway-name: api-gateway }
  configPatches:
    - applyTo: HTTP_FILTER
      match:
        context: GATEWAY
        listener:
          filterChain:
            filter:
              name: envoy.filters.network.http_connection_manager
              subFilter: { name: envoy.filters.http.router }
      patch:
        operation: INSERT_BEFORE
        value:
          name: envoy.filters.http.ratelimit
          typed_config:
            "@type": type.googleapis.com/envoy.extensions.filters.http.ratelimit.v3.RateLimit
            domain: mto-api-gateway
            failure_mode_deny: false          # platform value (rateLimit.failureModeAllow)
            timeout: 0.25s
            rate_limit_service:
              grpc_service:
                envoy_grpc:
                  cluster_name: "outbound|8081||ratelimit.mto-api-gateways.svc.cluster.local"
              transport_api_version: V3
    - applyTo: VIRTUAL_HOST
      match:
        context: GATEWAY
        routeConfiguration:
          vhost: { name: "", route: { action: ANY } }   # no generated name (M14)
      patch:
        operation: MERGE
        value:
          rate_limits:                # one entry per API of team-a
            - actions:
                - generic_key: { descriptor_key: tenant, descriptor_value: team-a }
                - header_value_match:   # no match: this entry gives no descriptor (M18)
                    descriptor_key: api
                    descriptor_value: orders
                    headers:
                      - name: ":authority"
                        string_match: { safe_regex: { regex: "^orders\\.team-a\\.apis\\.example\\.com(:[0-9]+)?$" } }
                      - name: ":path"
                        string_match: { safe_regex: { regex: "^/orders/v2([/?].*)?$" } }
                - metadata:
                    descriptor_key: tier
                    default_value: bronze
                    metadata_key:
                      key: envoy.filters.http.jwt_authn
                      path: [{ key: payload }, { key: tier }]
                - metadata:
                    descriptor_key: azp
                    metadata_key:
                      key: envoy.filters.http.jwt_authn
                      path: [{ key: payload }, { key: azp }]
```

With the correlation-ID knob on, a third filter merges into the route
configuration (`request_headers_to_add`: the platform's header from
`%REQ(X-REQUEST-ID)%`, `ADD_IF_ABSENT`). With the telemetry knobs on, a
`Telemetry` selects the gateway's pods with the chosen access log provider and
the extra trace headers as custom tags.

### 3.4 Per API, in the API's namespace (`api` Template)

A team publishes an API with a `TemplateInstance` of `api`, in the backend's
namespace (ADR-0005). Its name is the API name.

```yaml
apiVersion: templates.v2.stakater.com/v2alpha1
kind: TemplateInstance
metadata: { name: orders, namespace: team-a-dev }
spec:
  templateRef: { name: api, namespace: mto-api-gateways }
  parameters:
    - { name: host,    value: orders.team-a.apis.example.com }   # default <api>.<tenant>.<base domain>
    - { name: path,    value: /orders/v2 }
    - { name: rewrite, value: /orders/v1 }                       # optional
    - { name: service, value: orders }
    - { name: port,    value: "80" }
    # optional, instead of all paths under `path`, and not with `rewrite`:
    # - { name: operations, value: "POST /orders/v2/fetch" }
```

| Parameter | Required | Checks |
|---|---|---|
| `host` | no | a lowercase host name, no wildcard; one of the tenant's hostnames, or a shared host when `path` is under one of the tenant's prefixes there (ADR-0009) |
| `path` | yes | starts with `/`; segments of letters, digits, `-`, `.`, `_`, `~`; no empty, `.` or `..` segment; no trailing `/`, except `/` alone |
| `rewrite` | no | as `path`; not with `operations` |
| `service`, `port` | yes | a `Service` name (DNS label) in the instance's namespace; a port 1–65535 |
| `operations` | no | `METHOD /exact/path`, comma-separated, at most 10; each path under `path` |

It renders, in `team-a-dev`, the `HTTPRoute` and the ConfigMap `api.orders`
(`status: ok` with the URL and the rule, or `status: refused` with the
reason). An invalid parameter, or a tenant with no gateway, renders no route.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api.orders
  namespace: team-a-dev
  annotations: { api-gateway.stakater.com/api: orders }
spec:
  parentRefs: [{ name: api-gateway, namespace: team-a-dev }]   # the tenant's gateway, from the platform
  hostnames: ["orders.team-a.apis.example.com"]
  rules:
    - matches: [{ path: { type: PathPrefix, value: /orders/v2 } }]
      filters:
        - type: URLRewrite
          urlRewrite: { path: { type: ReplacePrefixMatch, replacePrefixMatch: /orders/v1 } }
      backendRefs: [{ name: orders, port: 80 }]
```

### 3.5 Per API rule and lock (child `api-gateway-policy`)

For the API `orders` (the route `api.orders` in `team-a-dev`, host
`orders.team-a.apis.example.com`, path `/orders/v2`) and a backend Service
`orders`:

| Kind | Namespace | Name | What it does |
|---|---|---|---|
| `AuthorizationPolicy` `ALLOW` | the gateway's (`team-a-dev`) | `api.orders` | targets the `Gateway`; the route's host and path (or exact operations); the closed rule `api.team-a.orders` (ADR-0006); `azp` and every mapped claim required; the tenant's issuers only |
| `AuthorizationPolicy` `DENY` | the route's | `api.orders.<service>` | one per backend Service: L4 `DENY` on the target ports from every identity but `api-gateway-istio` (ADR-0007) |

The allowed-API rule is rendered **only when every backend can be locked** and
**its path overlaps no other route's path on the same host** (ADR-0005).
Otherwise the route serves nothing,
and `api-gateway-apis` says why (§7). The extension fails closed.

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata: { name: api.orders, namespace: team-a-dev }
spec:
  targetRefs: [{ group: gateway.networking.k8s.io, kind: Gateway, name: api-gateway }]
  action: ALLOW
  rules:
    - from:
        - source: { requestPrincipals: ["https://sso.example.com/realms/apis/*"] }
      to:
        - operation:
            hosts: ["orders.team-a.apis.example.com", "orders.team-a.apis.example.com:*"]
            paths: ["/orders/v2", "/orders/v2/*"]     # the route's prefix, segment by segment (A6, M16)
      when:
        - key: request.auth.claims[allowed_apis]
          values: ["api.team-a.orders", "api.team-a.orders.*"]
        - key: request.auth.claims[azp]
          values: ["*"]
        - key: request.auth.claims[client_id]   # mapped by the team (ADR-0012)
          values: ["*"]
---
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata: { name: api.orders.orders, namespace: team-a-dev }
spec:
  selector:
    matchLabels: { app: orders }      # copied from Service orders' selector
  action: DENY                         # an ALLOW from anyone else can't widen it
  rules:
    - from:
        - source:
            notPrincipals: [cluster.local/ns/team-a-dev/sa/api-gateway-istio]
      to:
        - operation:
            ports: ["8080"]            # the Service's target ports only
```

A caller outside the mesh has no identity, so it matches `notPrincipals` and is
refused too (M9). A metrics port that is not one of the Service's target ports
stays open to the platform's monitoring (Q5). No `ReferenceGrant`: the route
and its backends are in the same namespace (A2). The extension never writes to
the `HTTPRoute` itself.

## 4. The security baseline (ADR-0004)

Every request on a tenant gateway passes, in order:

1. **Header removal** (platform filter): the caller's copies of every claim
   header are removed.
1. **Token check** (`RequestAuthentication`): a token in the `Authorization`
   header must be valid: signature, issuer, audience, expiry. An invalid one
   is refused with `401`.
1. **Token floor** (root namespace `DENY`): no valid token from one of the
   platform's issuers: `403`. Holds whatever else exists. A token from an
   issuer that is not the tenant's is not validated by its gateway, so it
   fails here too (Q18).
1. **Allowed-API rule** (per-API `ALLOW`): the request's host belongs to an
   API, the allowed-APIs claim names that API (closed), and `azp` and every
   mapped claim are present. Otherwise the default deny: `403`.
1. **Headers:** `x-sub`, `x-roles` and the team's extras set from the token.
1. **Rate limit** (platform filter): the caller's tier limit, counted per
   tenant, API and caller. Otherwise `429`.
1. **Backend lock** (mesh): on the API's ports, the backend refuses every
   identity but the tenant gateway's, and every caller outside the mesh.

The **render check** (`hack/`, in `make verify`) fails when, for any fixture:

- the bootstrap render lacks the root-namespace floor (listing every issuer
  in `auth.issuers`, and no other) or the empty `ALLOW`, or that `ALLOW` has any rule (AC-ISO-8);
- a tenant's child lacks the `RequestAuthentication` (token only from the
  `Authorization` header), the header-removal filter or the rate limit filter
  (AC-R-2);
- an `EnvoyFilter` is not one of the three allowlisted shapes, selects more
  than one gateway, matches a generated name, or contains Lua; or any rendered
  object is a `WasmPlugin` or `TrafficExtension` (AC-R-1);
- a per-API `ALLOW` has no hosts, a wildcard host, an issuer that is not its tenant's, a rule not
  derived from the tenant and the API name or not closed, or no `azp`
  condition (AC-R-4, AC-R-6);
- an allowed-API rule is rendered for a route with a backend that can't be
  locked or a host it doesn't own; or a backend lock lacks its port list;
- a listener allows routes `from: All` or `Same`, or has no hostname (AC-R-5);
- a gateway is not `ClusterIP` or lacks the gateway label (AC-R-7).

Every guard in the check has a mutation test, as in the Enterprise harness.

## 5. The allowed-API rule (ADR-0006)

| Part | Rule |
|---|---|
| Format | `<prefix>.<tenant>.<api>`, optionally followed by `.<anything>`; prefix `api` by default |
| Tenant | the `Tenant` name, a DNS label (no dot) |
| API | the `api` instance's name, a DNS label (no dot), unique in the tenant (ADR-0005) |
| Closed | `api.team-a.orders` never matches `api.team-a.orders2`; `api.team.a-orders` never matches `api.team-a.orders` |
| Claim | `allowed_apis` by default; a list claim in the token. The platform may rename it |
| Istio | the condition values `api.team-a.orders` (exact) and `api.team-a.orders.*` (prefix ending in the dot); a list claim matches when any value matches (M10) |

G.19 tests a missing claim and a claim that is a single string (Q4).

## 6. Names

| Object | Name | Budget |
|---|---|---|
| `Gateway` | `<request>`: the `TemplateInstance` name | a DNS label ≤ 48 (the parent refuses others) |
| Gateway Deployment, Service, ServiceAccount | `<request>-istio` (M3) | fits |
| Per-request objects | `<request>-infra`, `<request>-tls`, `<request>-tls-extra-<n>`, `<request>-status` | request ≤ 48, so the longest stays ≤ 63 |
| Per-tenant objects (child) | `<request>-jwt`, `<request>-strip-headers`, `<request>-ratelimit`, `<request>-correlation-id`, `<request>-telemetry`, `<request>-apis` | ≤ 63 |
| The child `TemplateInstance` | `api-gateway-policy-<tenant>`, in `mto-api-gateways` | tenant ≤ 63; the parent shortens with a hash when needed |
| Per-API objects | `HTTPRoute` and ConfigMap `api.<api>` (the API's namespace, from the `api` instance); `api.<api>` (gateway's namespace), `api.<api>.<service>` (route's namespace): dot-joined, so they never meet a request's hyphen-joined names | API name + Service name ≤ 240 |
| Root-namespace objects | `mto-api-gateway-token-floor`, `mto-api-gateway-default-deny` | fixed |
| Hostname | `*.<tenant>.<base domain>`; an API's host under it or a granted host; APIs share a host by path (ADR-0005) | DNS limits: label ≤ 63, name ≤ 253 |

The parent skips a tenant whose name is not a DNS label or is longer than 63
characters (a label value), and refuses a request whose name is not a DNS
label of at most 48 characters. Both are listed, with the reason, in the
skipped-tenants ConfigMap (`mto-extension-api-gateway-skipped-tenants`), keys
`<tenant>` and `request.<namespace>.<name>`.

## 7. Status, skips and conflicts

Every request renders its own status ConfigMap, `<request>-status`, in its
namespace: `status: ok` with the tenant and the host names, or
`status: refused` with the reason (not a tenant namespace, an invalid name,
or "tenant team-a already has its API gateway, from TemplateInstance
team-a-dev/api-gateway").

Every `api` instance renders `api.<api>` in its namespace: `status: ok` with
the URL and the rule, or `status: refused` with the reason (an invalid
parameter, or no gateway in the tenant yet).

The tenant's child renders `<request>-apis` in the gateway's namespace:

| Key | Lists |
|---|---|
| `apis` | each API: route, hosts, backend, the rule `api.<tenant>.<api>` |
| `not-apis` | routes attached to the tenant gateway without the annotation (they serve nothing) |
| `duplicates` | `api` instances that reuse an API name in the tenant: the oldest keeps the API, later ones are skipped |
| `path-conflicts` | APIs on one host whose paths overlap (one equals, or is a segment prefix of, the other), and a route that is not an API on an API's host and path: none of them serves (ADR-0005) |
| `invalid` | a backend that is not a `Service` with a selector and numeric target ports in the route's namespace (for example `ExternalName`) |
| `outside-mesh` | a route whose namespace lacks the mesh labels (M5): the route serves nothing |
| `unattached` | annotated routes the gateway didn't accept, with the reason from the route's status (G.6) |
| `settings` | the knobs in effect, and each refused or unknown annotation with the reason (ADR-0012) |

The parent refuses an extra hostname that is not a valid host name, that
overlaps the base domain (reserved for `<tenant>.<base domain>` names, also
of tenants that don't exist yet), or that overlaps an extra hostname of
another tenant. Overlap is a wildcard intersection, not an equality:
`*.wild.example.org` overlaps `x.wild.example.org`. Neither tenant gets a
conflicting hostname. Refusals are listed in the skipped-tenants ConfigMap
under `<tenant>.hostnames`, one line per host.

The parent also refuses a shared host under the base domain or equal to an
extra hostname, a prefix that is not a valid path, and two tenants' prefixes
on one host where one equals, or is a segment prefix of, the other
(`/orders` and `/orders/admin`, not `/orders` and `/orders-v2`). Neither
tenant gets the conflicting prefix. Refusals are listed under
`<tenant>.paths`.

## 8. Team settings (ADR-0012)

A team sets these as annotations on its gateway request; the child validates
them and lists each refused or unknown key:

```yaml
metadata:
  annotations:
    api-gateway.stakater.com/claim-headers: "client_id=x-client"
    api-gateway.stakater.com/correlation-id: "on"
    api-gateway.stakater.com/access-log: "json-default"
    api-gateway.stakater.com/trace-headers: "x-consumer-transaction-id"
```

| Annotation | Effect | Limits |
|---|---|---|
| `claim-headers` | more claim headers for the backend, added to `x-sub` and `x-roles` | ≤ 5; no platform or reserved header |
| `correlation-id` | the platform's correlation header from `x-request-id`, when the caller sent none | `on` or `off` |
| `access-log` | an access log provider for the gateway | from the platform's list |
| `trace-headers` | request headers recorded on the gateway's traces | ≤ 5; only when the platform configures tracing |

## 9. Health and preflight

- **Preflight** (bootstrap chart, at install and on upgrade): the GatewayClass
  exists; the Gateway API and Istio security, networking and telemetry CRDs
  exist; at least one issuer is set, and every name in `defaultIssuers` and `tenantIssuers` is defined; the Redis address is set. A missing piece
  fails the install and names it.
- **Outputs** (Template Operator status outputs, as in the Enterprise
  extension): per tenant, the gateway's `Programmed` condition and the child's
  apply status (G.6).

## 10. Install requirements

- OpenShift with Gateway API CRDs and OpenShift Service Mesh 3 in ambient mode
  (K1 for versions); the Istio root namespace known to the chart.
- Template Operator v2 at the version the Enterprise extension needs (T2), with
  RBAC on the kinds of §3 (Q6).
- The Multi-Tenant Operator; tenant namespaces with the mesh labels set
  through the `Tenant` (M5).
- One or more OIDC issuers (RHBK), each with tokens that carry the caller
  (`azp`), the allowed-APIs claim and the tier claim, with the same claim
  names.
- A Redis for the rate limit counters; its address and password secret are
  bootstrap values.
- Access log providers, when teams may choose one, defined in the mesh
  configuration; their names listed in the bootstrap values.
- An entry point per tenant gateway, measured in G.0 and rendered in G.18:
    - the listener's hostname needs the caller's TLS server name (SNI). A
      reencrypt OpenShift `Route` is reported not to send it, and a
      passthrough `Route` does (ADR-0009);
    - options: a passthrough `Route` per host; one wildcard passthrough
      `Route` per tenant on a dedicated IngressController
      (`routeAdmission.wildcardPolicy: WildcardsAllowed`); or reencrypt
      `Route`s with a listener without hostname, which supersedes ADR-0009.
- **No tenant may claim a host under the base domain at any entry point.** A
  tenant can create OpenShift `Route`s; one for `orders.team-a.<base domain>`
  on the shared router would receive callers' tokens. So the base domain gets
  its own entry point, DNS for the base domain points only there, and
  admission refuses a tenant's OpenShift `Route` under the base domain (G.23).
- **Shared hosts** (ADR-0009): the router that serves them sets
  `routeAdmission.namespaceOwnership: InterNamespaceAllowed` (R2), terminates
  TLS with the host's certificate, and trusts the service CA (R3). Admission
  refuses a tenant's OpenShift `Route` for a shared host (G.23).
- The gateway class is `istio`, from the ambient mesh's control plane
  (ADR-0010).

## 11. Where this differs from the first proposal

The first proposal (a gateway chart published as a Template, one
`TemplateInstance` per API with a few parameters) set the goals this design
keeps: one chart owned by the platform, no security switches, a derived
allowed-API rule, one upgrade for all. It differs in four places:

| First proposal | This design | Why |
|---|---|---|
| a `TemplateInstance` per API, with parameters, that renders a gateway | a `TemplateInstance` of `api` per API, with six checked parameters, that renders only the route; one parameterless `TemplateInstance` per tenant for the gateway, with a few validated annotations | the team asks for everything with a `TemplateInstance`; the API rule is derived from the rendered route; admission refuses `valueFrom` (ADR-0002, ADR-0005, ADR-0012) |
| one gateway per API | one gateway per tenant, only when the team asks | fewer idle pods, one place for the baseline (ADR-0002) |
| hand-written `EnvoyFilter`s per team, with Lua | Istio policies, and three platform-owned, tested `EnvoyFilter`s with no Lua | supported APIs for the auth path; tested filters (ADR-0003) |
| `api-<name>-consumer-*` | `api.<tenant>.<api>`, closed | no collision across tenants, no wildcard (ADR-0006) |

It also answers the proposal's open point about two namespaces: the route and
its backend are in one namespace, so the child renders the lock there; the
gateway and its API rules live in the namespace the team chose for its
request.

## 12. What this design can't do (documented, not hidden)

- **A shared host needs a platform path map.** Tenants share a front-door
  host only on path prefixes the platform grants (ADR-0009); the router
  matches them as string prefixes (R1), and its `InterNamespaceAllowed`
  setting makes admission the only guard against a tenant's own `Route` on
  that host (R2).
- **Routes have only the `api` parameters.** No header filters, timeouts,
  retries, weights, or regular-expression, header or query matches; each is
  a new parameter (ADR-0005).
- **Stakater owns three `EnvoyFilter`s,** a Developer Preview API in Service
  Mesh 3, and depends on Istio's outbound cluster name; the upgrade suite
  (G.10) runs on every Service Mesh minor before a release supports it.
- **Every issuer issues the same claims.** An issuer whose tokens lack the
  allowed-APIs claim or `azp`, such as an older gateway's own token server,
  is not supported (G.9).
- **Identity-provider roles are manual.** The platform creates
  `api.<tenant>.<api>` roles in RHBK (G.11).
- **The gateway's pods run in the team's namespace** and count against the
  tenant's quota; admission keeps tenants from acting as the gateway
  (ADR-0008).
- **A shared gateway still shares pods.** One tenant's APIs share one gateway's
  capacity (G.12 for an API that needs its own).
- **One gateway per tenant, also across environments.** Two environments of
  one tenant on one cluster share its gateway, its settings and its issuers;
  keep them in separate tenants or clusters (ADR-0002).
- **The backend lock covers the API's ports on the pods behind annotated
  routes only.** Other in-mesh callers of the same ports are refused too;
  allowing named internal callers is G.17.
- **Backends outside the cluster are refused in v1** (G.16).
- **Team settings are per gateway,** shared by all APIs of a tenant.
- **`x-roles` carries a list claim base64-encoded**, as Istio sends it;
  backends decode it.
- **Unauthenticated floods are refused, not rate limited.** Rate limits count
  authenticated callers; the entry point limits the rest.
- **Behaviour on kind and on OpenShift** is read from docs and source until
  G.19 and G.0 observe it.
