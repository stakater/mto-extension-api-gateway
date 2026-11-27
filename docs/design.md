# Design

**Status:** proposed; G.1 is built on the code branch (PR #14), the other
stories are Draft. Baseline:
OpenShift Service Mesh 3 in ambient mode (upstream Istio on the kind lab),
Gateway API v1, Template Operator v2 (versions in `gateway-baseline.md`).
Facts are cited to `gateway-baseline.md` by row (e.g. **M6**); decisions to
ADRs. Open questions are **Q1–Q22** in the baseline (Q1, Q3 and Q13–Q15
apply only to the Kuadrant alternative), owned by stories G.19 (kind) and G.0
(OpenShift).

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
parameters on it. Then it publishes each API with one `TemplateInstance` of
`api` (host, path, backend), and APIs can share a host by path (ADR-0005).
Non-goals: see `vision.md`.

## 2. Architecture

One Helm chart, rendered once per cluster, and Template Operator v2 objects
(ADR-0001). See `diagrams.md`.

| Piece | Created | Renders |
|---|---|---|
| `mto-extension-api-gateway-bootstrap` | once per cluster, by Helm, in the platform's namespace `mto-api-gateways` | the parent `Template` and `TemplateInstance`, the child Template `api-gateway-policy` (one per version the release ships, `api-gateway-policy-v1-0-0`, ADR-0015), the token floor and default deny in the Istio root namespace (ADR-0004), the rate limit service (ADR-0003), the admission policy (ADR-0008) |
| The parent `TemplateInstance` | by the chart | the team-facing **`api-gateway` and `api` Templates**, the skipped-tenants ConfigMap, and **one child `TemplateInstance` per tenant that has a gateway** (ADR-0013) |
| A `TemplateInstance` of `api-gateway` | by the team, in the tenant namespace where its gateway should run; the required `version` (ADR-0015) and four optional team settings, none a security setting (ADR-0012) | **in its own namespace**: `Gateway` `mto-api-gateway`, its settings ConfigMap, its certificates, and the request's status ConfigMap |
| A `TemplateInstance` of `api` | by the team, one per API, in the backend's namespace; checked parameters (ADR-0005) | **in its own namespace**: the API's `HTTPRoute` `api.<api>` and its status ConfigMap `api.<api>` |
| A tenant's child `TemplateInstance` | by the parent, in `mto-api-gateways` | the tenant's gateway policy: `RequestAuthentication`, the platform's `EnvoyFilter`s, `Telemetry`; **per API route** the allowed-API rule (in the gateway's namespace) and the backend lock (in the route's namespace); the tenant's status ConfigMap `mto-api-gateway-apis` |

**How the request stays trusted.** A team writes only the `TemplateInstance`'s
namespace, name, its version (§13) and its four settings (§8). Every other
parameter of `api-gateway` is a `disableOverride` default that the parent sets and keeps current (T2):

- `tenantOf` — namespace → tenant, from the label `stakater.com/tenant` (T1),
  for the tenants that may request a gateway. The team render reads its
  instance's tenant from here, never from the instance's labels;
- `owner` — tenant → the one request that gets its gateway: the oldest valid
  `TemplateInstance` of `api-gateway` in the tenant's namespaces. Every other
  request renders only a status ConfigMap that says why;
- `extraHostnames`, and the platform's gateway settings.

The four settings are read by the tenant's child from the request's
`spec.parameters`, not by the team render, and validated there (ADR-0012). The `api` Template gets the same platform
parameters, plus each tenant's gateway and hostnames, all `disableOverride`.
A team sets only an API's parameters, which the template checks;
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
| `Deployment`, `Service`, `HorizontalPodAutoscaler`, `PodDisruptionBudget` | `ratelimit` in `mto-api-gateways` | the rate limit service (Envoy's rate limit API), with today's values as defaults: 3 to 8 pods at 70 % CPU, at least 2 available during a drain, spread over nodes and zones, one extra pod and none unavailable during a rollout, the image pinned by digest, and health probes that fail without Redis. A small cluster may run 1 pod; the disruption budget then isn't rendered. It runs as the ServiceAccount `ratelimit` (principal `cluster.local/ns/mto-api-gateways/sa/ratelimit`, which a Redis that allows only known callers must allow). The Service's gRPC port has `appProtocol: grpc`, so gateways reach it over the mesh; the debug port is not on the Service. The Redis address (one server, or Sentinel addresses and master set), its password Secret and key, the log level, the Redis pool size and the local cache are values (ADR-0003) |
| `AuthorizationPolicy` | `ratelimit` in `mto-api-gateways` | `ALLOW` only the tenant gateways (principals ending in `/sa/mto-api-gateway-istio`, a name no tenant pod may use, ADR-0008): no other pod can use up a tenant's counters |
| `ConfigMap` | `ratelimit-config-<hash>` | the tier configuration, from bootstrap values, immutable. The name carries a hash of the content, so a change of the limits creates a new `ConfigMap` and rolls the pods at once, as today's chart does. The service could reload the file itself, but only after the kubelet syncs it, up to about 90 s later (S1) |
| `Job` (Helm hook) | `mto-api-gateway-preflight` | the live preflight, before every install, upgrade and Argo CD sync (§9, H3) |
| `ClusterRole` | `mto-api-gateway-templateinstance-edit` | create, change and delete `TemplateInstance`s, labelled `aggregate-to-edit` and `aggregate-to-admin`: the Multi-Tenant Operator binds tenant editors and owners to `edit` and `admin`, which have no such right otherwise (T11) |
| `ValidatingAdmissionPolicy` + binding | `mto-api-gateway-tenants` | what tenant users may not do to a gateway (ADR-0008) |
| `ValidatingAdmissionPolicy` + binding | `mto-api-gateway-no-adoption` | refuses any update that adds the label `api-gateway.stakater.com/managed` to an object without it, so Template Operator never takes over a live object (ADR-0001, T10); applied before the parent `TemplateInstance` |

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

An API whose limit is off (its team's `rateLimit: "off"`, or the platform's
exemption) gets no rate limit entry in the filter, so no counter at all; the
tenant's status lists it.

A counter is kept for each tenant, API, tier and caller, so a caller's calls
to one API never use up its limit on another. The service matches a tenant's
own entry before the generic one and never falls back, so a tenant with an
exempted API gets the full tier tree under its own entry (M18).

### 3.2 Per request, in the request's namespace (`api-gateway` Template)

| Kind | Name | What it does |
|---|---|---|
| `Gateway` (class `istio`, ADR-0010) | `mto-api-gateway` (always; ADR-0002) | listener `tenant` for `*.team-a.apis.example.com` (and `extra-<n>` per granted host, and `entry` with no hostname when the tenant has shared-host prefixes or internal hosts, ADR-0009), routes only from `stakater.com/tenant=team-a` namespaces (A1, A3); `ClusterIP` Service and the gateway label (M13, ADR-0002); Service Mesh deploys `mto-api-gateway-istio` (M3) |
| `ConfigMap` | `mto-api-gateway-infra` | `spec.infrastructure.parametersRef` target: autoscaler and disruption budget (M3) |
| `Certificate` (or a platform-provided Secret) | `mto-api-gateway-tls`, `mto-api-gateway-tls-extra-<n>` | one per listener (Q10); the `entry` listener's Secret `mto-api-gateway-entry-tls` comes from OpenShift's service CA (R3) |
| OpenShift `Route` | `mto-api-gateway-shared-<n>` | only with shared-host prefixes: one reencrypt `Route` per granted prefix, to the Service `mto-api-gateway-istio` (ADR-0009, R1) |
| OpenShift `Route` | `mto-api-gateway-internal-<n>` | only with internal hosts: one reencrypt `Route` per granted internal host, with no path, to the Service `mto-api-gateway-istio`, as today's internal host (ADR-0009) |
| `PodMonitor` | `mto-api-gateway` | the gateway pods' metrics: the port `metrics`, `/stats/prometheus`, every `monitoring.podMonitor.interval` (M23); only when `monitoring.podMonitor.enabled`, as today |
| `ConfigMap` | `mto-api-gateway-status.api-gateway` | `ok` with the tenant and host names, or `refused` with the reason |

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: mto-api-gateway                  # fixed and reserved, never the request's name (ADR-0002)
  namespace: team-a-dev
  labels: { stakater.com/tenant: team-a, api-gateway.stakater.com/managed: "true" }
  annotations: { networking.istio.io/service-type: ClusterIP }   # on the Gateway itself (M13)
spec:
  gatewayClassName: istio
  infrastructure:
    # Istio copies these onto the Deployment, Service and ServiceAccount it creates (observed, G.19)
    labels: { stakater.com/tenant: team-a, api-gateway.stakater.com/gateway: "true", api-gateway.stakater.com/managed: "true" }
    parametersRef: { group: "", kind: ConfigMap, name: mto-api-gateway-infra }
  listeners:
    - name: tenant
      hostname: "*.team-a.apis.example.com"
      port: 443
      protocol: HTTPS
      tls:
        mode: Terminate
        certificateRefs: [{ name: mto-api-gateway-tls }]
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
| `RequestAuthentication` | `mto-api-gateway-jwt` | targets the `Gateway`: one rule per issuer that the tenant or one of its APIs uses, with its audiences (ADR-0004), token only from `Authorization` (M15); claim headers `x-sub` (`azp`), `x-roles` (`allowed_apis`) and the team's extras (ADR-0012) |
| `EnvoyFilter` | `mto-api-gateway-strip-headers` | removes the caller's copies of every claim header (the platform's and the team's), their underscore variants, and the names in `headers.removed`, before `jwt_authn`; never `authorization`, `host` or another header the gateway needs (ADR-0003) |
| `EnvoyFilter` | `mto-api-gateway-ratelimit` | Envoy's rate limit filter before `router`, and virtual-host actions with no name (M14): one entry per API, matched on the API's host and path, with the descriptors `tenant`, `api`, `tier` (the caller's highest tier role for the API, by exact text; the lowest when none, ADR-0003, M20), `azp` (M18) |
| `EnvoyFilter` | `mto-api-gateway-correlation-id` | only with the knob: the platform's correlation header from `x-request-id` when the caller sent none |
| `Telemetry` | `mto-api-gateway-telemetry` | only with the knobs: an access log provider from the platform's list; trace tags for the correlation header and every claim header, as today, plus the team's extra trace headers; and, when the platform configures tracing, the platform's sampling rate (default 100 %, as today, ADR-0012) |
| `ConfigMap` | `mto-api-gateway-apis` | the tenant's APIs, routes that are not APIs, conflicts, refused knobs (§7) |

```yaml
apiVersion: security.istio.io/v1
kind: RequestAuthentication
metadata: { name: mto-api-gateway-jwt, namespace: team-a-dev }
spec:
  targetRefs: [{ group: gateway.networking.k8s.io, kind: Gateway, name: mto-api-gateway }]
  jwtRules:                                   # one per issuer that team-a or its APIs use
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
metadata: { name: mto-api-gateway-strip-headers, namespace: team-a-dev }
spec:
  workloadSelector:
    labels: { gateway.networking.k8s.io/gateway-name: mto-api-gateway }
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
metadata: { name: mto-api-gateway-ratelimit, namespace: team-a-dev }
spec:
  workloadSelector:
    labels: { gateway.networking.k8s.io/gateway-name: mto-api-gateway }
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
                - extension:            # the caller's tier role for this API (ADR-0003, M20)
                    name: envoy.rate_limit_descriptors.expr
                    typed_config:
                      "@type": type.googleapis.com/envoy.extensions.rate_limit_descriptors.expr.v3.Descriptor
                      descriptor_key: tier
                      # R stands for the claim, written out by the template:
                      # metadata.filter_metadata['envoy.filters.http.jwt_authn']['payload']['allowed_apis'],
                      # with a check that it is a list, so the expression can't fail.
                      text: >-
                        'api.team-a.orders.gold' in R || 'api-orders-consumer-gold' in R ? 'gold' :
                        'api.team-a.orders.silver' in R || 'api-orders-consumer-silver' in R ? 'silver' :
                        'bronze'
                - metadata:
                    descriptor_key: azp
                    metadata_key:
                      key: envoy.filters.http.jwt_authn
                      path: [{ key: payload }, { key: azp }]
```

With the correlation-ID knob on, a third filter merges into the route
configuration (`request_headers_to_add`: the platform's header from
`%REQ(X-REQUEST-ID)%`, `ADD_IF_ABSENT`). With the telemetry knobs on, a
`Telemetry` selects the gateway's pods with the chosen access log provider,
the correlation header and every claim header as custom tags (as today) plus
the extra trace headers, and
`randomSamplingPercentage: <telemetry.tracing.samplingPercentage>`. A
gateway without these knobs follows the mesh's own sampling rate, as today.

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
| `host` | no | a lowercase host name, no wildcard; one of the tenant's hostnames, or a shared host when `path` is under one of the tenant's prefixes there (ADR-0009); `"-"` for no public host, with `internalHost` set (as an API with only an internal host today) |
| `internalHost` | no | one of the internal hosts the platform granted to the tenant; the API also answers there, on the same path (ADR-0009) |
| `path` | yes | starts with `/`; segments of letters, digits, `-`, `.`, `_`, `~`; no empty, `.` or `..` segment; no trailing `/`, except `/` alone |
| `rewrite` | no | as `path`; not with `operations` |
| `service`, `port` | yes (`service` unless `externalHost`) | a `Service` name (DNS label) in the instance's namespace; a port 1–65535 |
| `operations` | no | `METHOD /exact/path`, comma-separated, at most 10; each path under `path` |
| `issuers` | no | issuers the platform registered for this API's use, by name; default: the tenant's (ADR-0004) |
| `rateLimit` | no | `"on"` (default) or `"off"`; `"off"` refused when the platform locks the tenant (ADR-0004) |
| `backendLock` | no | `"on"` (default) or `"off"`; with `"off"` the backend checks the caller itself; refused when the platform locks the tenant (ADR-0007) |
| `externalHost`, `tls`, `tlsSni`, `tlsSecret` | for a backend outside the cluster | instead of `service`: the host, TLS `SIMPLE` (default), `MUTUAL` or `DISABLE`, the SNI (default the host), and a Secret in the gateway's namespace with `ca.crt` (and `tls.crt`, `tls.key` for `MUTUAL`), as in today's chart (ADR-0014) |

"Under" a prefix means segment by segment (ADR-0005): `/orders-v2/v1` is
under `/orders-v2`, not under `/orders`.

With `internalHost`, the route, the API rule and the rate limit entry name
both hosts; the path checks of ADR-0005 apply on each host.

It renders, in `team-a-dev`, the `HTTPRoute` and the ConfigMap `api.orders`
(`status: ok` with the URL and the rule, or `status: refused` with the
reason). An invalid parameter, or a tenant with no gateway, renders no route.

For a backend outside the cluster (ADR-0014), the instance sets
`externalHost` instead of `service`, and also renders the `ExternalName`
Service `mto-api-<api>-external`; the route points to it and rewrites the `Host`
header to the external host. The tenant's child renders, in the gateway's
namespace, the `ServiceEntry` and the `DestinationRule` `api.<api>.external`
(TLS mode, SNI, the Secret), as today's chart does:

```yaml
- { name: externalHost, value: api.partner.example.com }
- { name: port,         value: "443" }
- { name: rewrite,      value: /partner/api }
- { name: tls,          value: SIMPLE }          # or MUTUAL, DISABLE
- { name: tlsSecret,    value: partner-ca }      # in the gateway's namespace: ca.crt
```

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api.orders
  namespace: team-a-dev
  annotations: { api-gateway.stakater.com/api: orders }
spec:
  parentRefs: [{ name: mto-api-gateway, namespace: team-a-dev }]   # the tenant's gateway, from the platform
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
| `AuthorizationPolicy` `ALLOW` | the gateway's (`team-a-dev`) | `api.orders` | targets the `Gateway`; the route's host and path (or exact operations); the closed rule `api.team-a.orders` (ADR-0006); `azp` required, other mapped claims optional (ADR-0012); the API's issuers only (ADR-0004) |
| `AuthorizationPolicy` `DENY` | the route's | `api.orders.<service>` | one per backend Service, enforced by the namespace's waypoint: `DENY` every path but the platform's open paths, from every identity but `mto-api-gateway-istio` (ADR-0007); not rendered when the team set `backendLock: "off"` |
| `Gateway` (class `istio-waypoint`) + `ConfigMap` | the route's | `mto-api-gateway-waypoint`, `mto-api-gateway-waypoint-infra` | one per namespace with a locked API, kept while the namespace's label names it: the waypoint that enforces the lock, autoscaled (3 to 5 pods at 80 % CPU, disruption budget 1, as today); the namespace selects it with the label `istio.io/use-waypoint`, set through the `Tenant`. Not rendered for a namespace in `backendLock.existingWaypoints`, which uses that waypoint, also one in another namespace (ADR-0007) |
| `PodMonitor` | the route's | `mto-api-gateway-waypoint` | the waypoint's metrics, as for the gateway (M23); only when `monitoring.podMonitor.enabled` |
| `PeerAuthentication` | the route's | `api.orders.<service>` | only for a tenant in `backendLock.strictMtlsTenants`, and only with the lock on: mode `STRICT` on the pods the Service selects, so a caller outside the mesh is refused on every path (ADR-0007, M24) |

The allowed-API rule is rendered **only when every backend can be locked, or
its team turned the lock off** and
**its path overlaps no other route's path on the same host** (ADR-0005).
Otherwise the route serves nothing,
and `mto-api-gateway-apis` says why (§7). The extension fails closed.

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata: { name: api.orders, namespace: team-a-dev }
spec:
  targetRefs: [{ group: gateway.networking.k8s.io, kind: Gateway, name: mto-api-gateway }]
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
          values: ["api.team-a.orders", "api.team-a.orders.*"]   # + the exact old roles, if mapped (ADR-0006)
        - key: request.auth.claims[azp]         # the caller; other mapped claims are optional (ADR-0012)
          values: ["*"]
---
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata: { name: api.orders.orders, namespace: team-a-dev }
spec:
  targetRefs: [{ group: "", kind: Service, name: orders }]   # enforced by the waypoint
  action: DENY                         # another ALLOW can't widen it
  rules:
    - from:
        - source:
            notPrincipals: [cluster.local/ns/team-a-dev/sa/mto-api-gateway-istio]
      to:
        - operation:
            notPaths: ["/metrics", "/health", "/health/live", "/health/ready", "/healthz"]   # backendLock.publicPaths
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: { name: mto-api-gateway-waypoint, namespace: team-a-dev }
spec:
  gatewayClassName: istio-waypoint
  listeners: [{ name: mesh, port: 15008, protocol: HBONE }]
```

The gateway's own traffic skips the waypoint (M4); every other caller of the
Service passes it and is refused on the API's paths. The open paths stay open
to anyone, as today, so probes and scrapers keep working. A call to a pod's
IP, and a call from outside the mesh, doesn't pass the waypoint (M21, §12);
STRICT mTLS, when the platform turns it on for the tenant, refuses the
callers outside the mesh. No `ReferenceGrant`: the route and
its backends are in the same namespace (A2). The extension never writes to
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
   issuer that the tenant's gateway doesn't trust is refused with `401` by the
   token check ("Jwt issuer is not configured", observed, Q18); today's
   contract said `403` for it.
1. **Allowed-API rule** (per-API `ALLOW`): the request's host and path belong
   to an API, the allowed-APIs claim names that API (closed), and `azp` is
   present. Otherwise the default deny: `403`, also for a path or method that
   no API serves (today's gateways answer `404` there).
1. **Headers:** `x-sub`, `x-roles` and the team's extras set from the token.
1. **Rate limit** (platform filter): the caller's tier limit, counted per
   tenant, API and caller. Otherwise `429`.
1. **Backend lock** (waypoint): a call through the backend's Service from
   any identity but the tenant gateway's is refused, except on the open
   paths; the team can turn the lock off for its API (ADR-0007).

The **render check** (`hack/`, in `make verify`) fails when, for any fixture:

- the bootstrap render lacks the root-namespace floor (listing every issuer
  in `auth.issuers`, and no other) or the empty `ALLOW`, or that `ALLOW` has any rule (AC-ISO-8);
- a tenant's child lacks the `RequestAuthentication` (token only from the
  `Authorization` header), the header-removal filter or the rate limit filter
  (AC-R-2);
- an `EnvoyFilter` is not one of the three allowlisted shapes, selects more
  than one gateway, matches a generated name, or contains Lua; or any rendered
  object is a `WasmPlugin` or `TrafficExtension` (AC-R-1);
- a per-API `ALLOW` has no hosts, a wildcard host, an issuer that is not one of the API's, a rule not
  derived from the tenant and the API name or not closed, or no `azp`
  condition (AC-R-4, AC-R-6);
- an allowed-API rule is rendered for a route with a backend that can't be
  locked (with the lock on) or a host it doesn't own; or a backend lock
  opens a path that isn't in the platform's list, or uses a pattern;
- a listener allows routes `from: All` or `Same`, or has no hostname, except
  `entry` for a tenant with shared-host prefixes or internal hosts (AC-R-5);
- a gateway is not `ClusterIP` or lacks the gateway label (AC-R-7);
- the bootstrap chart uses `lookup` (H1), or a Template carries a Helm hook
  annotation (AC-OPS-7);
- the header filter removes `authorization`, `host` or another name the
  gateway needs (`headers.refusedTargets` other than claim headers), or an
  issuer has no audience;
- an object rendered outside `mto-api-gateways` has a name that doesn't start
  with `mto-api-` or `api.`, or lacks the label
  `api-gateway.stakater.com/managed: "true"` (ADR-0001, AC-LIFE-7).

Every guard in the check has a mutation test, as in the Enterprise harness.

## 5. The allowed-API rule (ADR-0006)

| Part | Rule |
|---|---|
| Format | `<prefix>.<tenant>.<api>`, optionally followed by `.<anything>`; prefix `api` by default |
| Tenant | the `Tenant` name, a DNS label (no dot) |
| API | the `api` instance's name, a DNS label (no dot) of at most 46 characters, unique in the tenant (ADR-0005) |
| Closed | `api.team-a.orders` never matches `api.team-a.orders2`; `api.team.a-orders` never matches `api.team-a.orders` |
| Claim | `allowed_apis` by default; a list claim in the token. The platform may rename it |
| Istio | the condition values `api.team-a.orders` (exact) and `api.team-a.orders.*` (prefix ending in the dot); a list claim matches when any value matches (M10) |
| Migration | the platform may map an API to its old role name (`migration.legacyRoles`); the rule then also accepts `<old>-<tier>` for each defined tier, as exact values (ADR-0006) |
| Tier | the caller's role `api.<tenant>.<api>.<tier>` (or `<old>-<tier>`) gives the API's tier; the highest wins; none gives the lowest (ADR-0003) |

G.19 tests a missing claim and a claim that is a single string (Q4).

## 6. Names

| Object | Name | Budget |
|---|---|---|
| `Gateway` | `mto-api-gateway`, always: a reserved name, never the request's (ADR-0002) | fixed |
| Gateway Deployment, Service, ServiceAccount | `mto-api-gateway-istio` (M3) | fixed |
| Per-gateway objects | `mto-api-gateway-infra`, `-tls`, `-tls-extra-<n>`, `-shared-<n>`, `-internal-<n>`; the `PodMonitor` `mto-api-gateway` | ≤ 63 |
| The request's status | `mto-api-gateway-status.<request>`, in the request's namespace | the request's name is a DNS label |
| Per-tenant objects (child) | `mto-api-gateway-jwt`, `-strip-headers`, `-ratelimit`, `-correlation-id`, `-telemetry`, `-apis` | fixed |
| The child `TemplateInstance` | `api-gateway-policy-<tenant>`, in `mto-api-gateways` | tenant ≤ 63; the parent shortens with a hash when needed |
| The child Template | `api-gateway-policy-v<version>` (`api-gateway-policy-v1-0-0`), one per version the release ships; the team-facing `api-gateway` and `api` keep their names (ADR-0015) | fixed |
| Per-API objects | `HTTPRoute` and ConfigMap `api.<api>` (the API's namespace, from the `api` instance); `api.<api>` (gateway's namespace), `api.<api>.<service>` (route's namespace: the lock's `AuthorizationPolicy`, and the `PeerAuthentication` when STRICT): dot-joined, so they never meet a hyphen-joined name; the `ExternalName` Service `mto-api-<api>-external` (a Service name can't have a dot) | API name ≤ 46, so `mto-api-<api>-external` fits 63; API name + Service name ≤ 240 |
| Per backend namespace | the waypoint `Gateway` and its `PodMonitor`, both `mto-api-gateway-waypoint` | fixed |
| Rate limit configuration | `ratelimit-config-<hash>`, the first 10 characters of the content's SHA-256 | fixed length |
| Root-namespace objects | `mto-api-gateway-token-floor`, `mto-api-gateway-default-deny` | fixed |
| Hostname | `*.<tenant>.<base domain>`; an API's host under it or a granted host; APIs share a host by path (ADR-0005) | DNS limits: label ≤ 63, name ≤ 253 |

**Reserved names (ADR-0001).** Every object the extension renders outside its
own namespace `mto-api-gateways` has a name that starts with `mto-api-` or
`api.`, and carries the label `api-gateway.stakater.com/managed: "true"`.
Today's charts use neither form, and tenants can't create objects of these
kinds (ADR-0008). So a rendered name never matches a live object, and if one
does, the admission policy `mto-api-gateway-no-adoption` refuses the takeover
and the preflight names the object (§9).

The parent skips a tenant whose name is not a DNS label or is longer than 63
characters (a label value), and refuses a request whose name is not a DNS
label. Both are listed, with the reason, in the
skipped-tenants ConfigMap (`mto-extension-api-gateway-skipped-tenants`), keys
`<tenant>` and `request.<namespace>.<name>`.

## 7. Status, skips and conflicts

Every request renders its own status ConfigMap, `mto-api-gateway-status.<request>`, in its
namespace: `status: ok` with the tenant and the host names, or
`status: refused` with the reason (not a tenant namespace, an invalid name,
or "tenant team-a already has its API gateway, from TemplateInstance
team-a-dev/api-gateway").

Every `api` instance renders `api.<api>` in its namespace: `status: ok` with
the URL and the rule, or `status: refused` with the reason (an invalid
parameter, or no gateway in the tenant yet).

The tenant's child renders `mto-api-gateway-apis` in the gateway's namespace:

| Key | Lists |
|---|---|
| `apis` | each API: route, hosts, backend, the rule `api.<tenant>.<api>` |
| `not-apis` | routes attached to the tenant gateway without the annotation, written by an admin or before admission (they serve nothing) |
| `duplicates` | `api` instances that reuse an API name in the tenant: the oldest keeps the API, later ones are skipped |
| `path-conflicts` | APIs on one host whose paths overlap (one equals, or is a segment prefix of, the other), and a route that is not an API on an API's host and path: none of them serves (ADR-0005) |
| `invalid` | a backend that is not a `Service` in the route's namespace, an `ExternalName` that the extension didn't render (ADR-0014), or, for a tenant with STRICT mTLS, a Service with no selector (ADR-0007) |
| `outside-mesh` | a route whose namespace lacks the mesh's discovery label: Istio ignores it, so it serves nothing, lock or no lock (M5). With the lock on, also a namespace without the ambient label or whose `istio.io/use-waypoint` doesn't name `mto-api-gateway-waypoint` or its `existingWaypoints` entry: the route serves nothing (ADR-0007) |
| `lock-bypass` | a backend Service, or a pod it selects, that carries `istio.io/use-waypoint` or `istio.io/use-waypoint-namespace` (set before admission, or by an admin): its API serves nothing (ADR-0007, ADR-0008) |
| `idle-waypoints` | a waypoint kept because the namespace's label still names it, though no locked API is left there (ADR-0007) |
| `unlocked` | APIs whose team turned the backend lock off, and refused `"off"` settings with the reason (ADR-0007) |
| `external` | APIs whose backend is outside the cluster, with the host and the TLS mode (ADR-0014) |
| `unattached` | API routes the gateway didn't accept, with the reason from the route's status (G.6) |
| `settings` | the settings in effect, and each refused value with the reason (ADR-0012) |

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

A team sets these as optional parameters of its gateway request, in the same
style as an `api` request; the child validates each value and lists each
refused one, and the gateway keeps the default. A misspelt parameter name
fails the request in Template Operator (`ParameterResolutionFailed`): nothing
new is applied and nothing is deleted, so the running gateway keeps working
until the team fixes the name (T8). Per API, the team also sets
`rateLimit` and `backendLock` (`"on"` or `"off"`) on its `api` instance
(§3.4, ADR-0004, ADR-0007).

```yaml
spec:
  templateRef: { name: api-gateway, namespace: mto-api-gateways }
  parameters:
    - { name: claimHeaders,  value: "client_id=x-client" }
    - { name: correlationId, value: "on" }
    - { name: accessLog,     value: json-default }
    - { name: traceHeaders,  value: x-transaction-id }
```

| Parameter | Effect | Limits |
|---|---|---|
| `claimHeaders` | more claim headers for the backend, added to `x-sub` and `x-roles`; a claim missing from a token sets no header | ≤ 5; no name in `headers.refusedTargets` |
| `correlationId` | the platform's correlation header from `x-request-id`, when the caller sent none | `on` or `off` |
| `accessLog` | an access log provider for the gateway | from the platform's list |
| `traceHeaders` | request headers recorded on the gateway's traces | ≤ 5; only when the platform configures tracing |

## 9. Health and preflight

- **Preflight** (bootstrap chart), in three layers, so that it works the same
  under `helm install`, `helm upgrade` and Argo CD, which renders with
  `helm template` (H1–H3). The chart uses no `lookup`, which returns nothing
  there; a render check fails on one.
    1. **Values**, by `values.schema.json`, in every renderer: at least one
       issuer, every name in `auth.defaultIssuers` and `auth.tenantIssuers`
       defined, the Redis address set.
    1. **APIs**, by `.Capabilities.APIVersions.Has`, which Helm and Argo CD
       fill from the cluster (H2): the Gateway API; Istio's security,
       networking and telemetry APIs; Template Operator v2; OpenShift's
       `Route` when a tenant has a shared host or an internal host;
       `monitoring.coreos.com/v1` `PodMonitor` when monitoring is on;
       cert-manager when `gateway.tls.certManager` is set. A missing API
       fails the render, and the error names it. A plain `helm template`
       passes `--api-versions`, as the render tests do.
    1. **Live state**, by the hook `Job` `mto-api-gateway-preflight`
       (`pre-install,pre-upgrade`; Argo CD runs it as `PreSync` on every sync,
       H3), with read-only access: the GatewayClass `istio` exists and is
       accepted; Service Mesh, the Gateway API and Template Operator are at
       or above their floors in [`support-matrix.md`](support-matrix.md);
       istiod reloads keys every 3 minutes (M19); the Redis password Secret
       exists; `mto-api-gateways` has the mesh's discovery and ambient
       labels; the access log and tracing providers named in the values exist
       in the mesh configuration (istiod rejects a `Telemetry` that names a
       missing one); the mesh runs no newer minor than the support matrix's
       highest tested one; no object with a reserved name (`mto-api-…` or `api.…`, of a
       kind the extension renders) exists without the label
       `api-gateway.stakater.com/managed`. A failed check fails the `Job`,
       which stops the install or the sync; its log names each missing
       piece, and each object with a reserved name that the extension
       didn't render. `preflight.enabled` (default
       on) and `preflight.image` are platform values.

  The hook belongs to the bootstrap chart only. A Template never carries a
  Helm hook: Template Operator runs none (issue #6).
- **Outputs** (Template Operator status outputs, as in the Enterprise
  extension): per tenant, the gateway's `Programmed` condition and the child's
  apply status (G.6).

## 10. Install requirements

- OpenShift with Gateway API CRDs and OpenShift Service Mesh 3 in ambient mode
  (versions: M1 and [`support-matrix.md`](support-matrix.md)); the Istio root
  namespace known to the chart.
- Template Operator v2 at the version the Enterprise extension needs (T2), with
  RBAC on the kinds of §3 (Q6).
- The Multi-Tenant Operator; tenant namespaces with the mesh labels set
  through the `Tenant` (M5).
- One or more OIDC issuers (RHBK), each with tokens that carry the caller
  (`azp`), and the allowed-APIs claim with one role per API and tier
  (`api.<tenant>.<api>.<tier>`, or the API's old role name during
  migration), with the same claim names. An external Keycloak that an API brings must be reachable from
  Istio's control plane, which fetches its keys (ADR-0004).
- For an API with a backend outside the cluster: the cluster's network lets
  the gateway reach the host (ADR-0014).
- Istio's key reload interval set to **3 minutes** in the Service Mesh
  control plane (`PILOT_JWT_PUB_KEY_REFRESH_INTERVAL=3m`; Istio's default is
  20 minutes, M19). It is a mesh setting, not a value of this chart.
- A Redis for the rate limit counters; its address and password secret are
  bootstrap values. A Redis that allows only known callers must allow the
  rate limit service's principal (§3.1). Sentinel itself has no password (the
  service authenticates only to Redis, as today).
- The namespace `mto-api-gateways` in the mesh: the mesh's discovery label and
  `istio.io/dataplane-mode: ambient`. It is not a tenant namespace, so the
  `Tenant` doesn't label it; without the labels the gateways can't reach the
  rate limit service. The preflight checks it.
- Istio's control plane trusts the CA of every issuer's key address (today's
  trusted CA bundle on istiod), or it can't fetch the keys and every token is
  refused.
- Service Mesh upgrades pinned: a `Manual` install plan approval or a pinned
  version, so the mesh never moves past a version this extension was tested
  on (docs/support-matrix.md). A mesh upgrade one tenant at a time
  (`gateway.meshRevision`) needs the `Istio` resource's revision-based update
  strategy.
- Access log providers, when teams may choose one, defined in the mesh
  configuration; their names listed in the bootstrap values. A tracing
  provider in the mesh configuration when the platform turns tracing on.
- With `monitoring.podMonitor.enabled` (the default, as today): the
  `PodMonitor` API and a Prometheus that reads `PodMonitor`s in tenant
  namespaces (OpenShift's monitoring for user projects).
- For internal hosts: the cluster router's domain (`gateway.internalDomain`)
  and its wildcard certificate, as today.
- An entry point per tenant gateway, measured in G.0 and rendered in G.18:
    - the listener's hostname needs the caller's TLS server name (SNI). A
      reencrypt OpenShift `Route` is reported not to send it, and a
      passthrough `Route` does (ADR-0009);
    - options: a passthrough `Route` per host; one wildcard passthrough
      `Route` per tenant on a dedicated IngressController
      (`routeAdmission.wildcardPolicy: WildcardsAllowed`); or reencrypt
      `Route`s for every host, to the `entry` listener without hostname,
      which would replace ADR-0009's hostname-bound `tenant` listener (a new
      ADR).
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
keeps: one chart owned by the platform, no switch for the token check, the
API rule or the headers, a derived allowed-API rule, one upgrade for all. It differs in four places:

| First proposal | This design | Why |
|---|---|---|
| a `TemplateInstance` per API, with parameters, that renders a gateway | a `TemplateInstance` of `api` per API, with checked parameters, that renders only the route; one `TemplateInstance` per tenant for the gateway, with four validated, non-security parameters | the team asks for everything with a `TemplateInstance`; the API rule is derived from the rendered route; admission refuses `valueFrom` (ADR-0002, ADR-0005, ADR-0012) |
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
  a new parameter (ADR-0005). Today's charts allow header and query matches,
  a method on a prefix, an exact path for any method, and several prefixes
  for one API; no API uses them. A route that adds or removes a request
  header the team chooses is not in today's charts either; it can be a later
  parameter.
- **No API without a token check.** Today's chart can turn the token check
  off, and one test gateway runs so. Such an API stays on its old gateway; a
  platform exemption per API is a later option.
- **Gateway settings are per tenant.** Two APIs in one namespace that today
  use different claim headers or log formats share one set; they keep their
  old gateways until they agree, or get a second gateway (G.12).
- **Stakater owns three `EnvoyFilter`s,** a Developer Preview API in Service
  Mesh 3, and depends on Istio's outbound cluster name; the upgrade suite
  (G.10) runs on every Service Mesh minor before a release supports it.
- **Every issuer issues the same claims.** An issuer whose tokens lack the
  allowed-APIs claim or `azp`, such as an older gateway's own token server,
  is not supported (G.9).
- **Identity-provider roles are manual.** The platform creates
  `api.<tenant>.<api>.<tier>` roles in RHBK (G.11).
- **A realm change that makes new signing keys refuses tokens for a few
  minutes.** A Keycloak realm that is imported again gets new keys. New tokens
  fail until Istio reloads the keys (up to 3 minutes), and tokens signed with
  the old key fail after that until callers get new ones (up to the token
  life, 5 minutes today). A signing key that stays the same across realm
  changes removes this (G.27).
- **The gateway's pods run in the team's namespace** and count against the
  tenant's quota; admission keeps tenants from acting as the gateway
  (ADR-0008).
- **A shared gateway still shares pods.** One tenant's APIs share one gateway's
  capacity. More than one gateway per tenant is a later option, if a need
  arises (G.12).
- **One gateway per tenant, also across environments.** Two environments of
  one tenant on one cluster share its gateway, its settings and its issuers;
  keep them in separate tenants or clusters (ADR-0002), or use G.12 later.
- **The backend lock covers mesh callers that use the Service, as today.** A
  pod outside the mesh (calling the Service or a pod's IP) and a mesh pod
  calling a pod's IP reach the backend directly and can set their own headers
  (ADR-0007, observed on kind). The platform can close the gap from outside
  the mesh for a tenant with STRICT mTLS (`backendLock.strictMtlsTenants`),
  off by default: it also refuses a scraper outside the mesh on the
  backend's `/metrics`. A mesh pod on a pod's IP still passes. Other in-mesh
  callers of the API's paths are refused; allowing named internal callers is
  G.17.
- **A change of the rate limits restarts the rate limit service,** one pod at
  a time, as today, so the change applies at once (S1). The service exports
  no metrics, as today; observability is G.14.
- **An internal host is a platform grant per tenant** (ADR-0009). A moved API
  keeps its internal host only after the old gateway's `Route` for it is
  deleted (R5).
- **A team can turn its backend lock off** (`backendLock: "off"`), as today;
  the backend must then check the caller itself. The platform can stop this
  for a tenant (`backendLock.lockedTenants`).
- **No legacy issuer mode.** An issuer with fixed keys and access by a list of
  client IDs (today's mode for a retired issuer) is not supported; such an API
  moves after its callers use the identity provider's tokens (ADR-0004).
- **A backend outside the cluster has no lock and gets no token,** as today
  (ADR-0014): it gets the headers set from the token, so it must protect
  itself, for example by accepting only the gateway's client certificate
  (`MUTUAL`). A team can name any host; a platform list of allowed hosts is a
  later option.
- **`x-roles` carries a list claim base64-encoded**, as Istio sends it;
  backends decode it.
- **Unauthenticated floods are refused, not rate limited.** Rate limits count
  authenticated callers; the entry point limits the rest.
- **Behaviour on OpenShift** is read from docs and source until G.0 observes
  it. The first kind runs are in
  [`spikes/g19-kind-findings.md`](spikes/g19-kind-findings.md); G.19 repeats
  them in the lab.

## 13. Upgrades: each team chooses its version, with no downtime (ADR-0015)

The extension's templates have a semantic version, `MAJOR.MINOR.PATCH`: a
patch fixes bugs and security issues only; a minor adds features that break
nothing; a major breaks something that callers or teams see, and its release
notes list each change. Each release ships the templates of the versions in
Stakater's support window, named in its release notes; the platform chooses
which of them teams may use (`versions.allowed`, default: all of them).

Each team chooses its version with the required parameter `version` on its
gateway request. The tenant's gateway, its policy and all its APIs use that
version: the parent passes it to the `api` Template and to the tenant's child.

```yaml
spec:
  templateRef: { name: api-gateway, namespace: mto-api-gateways }
  parameters:
    - { name: version, value: "1.1.0" }   # required; one of versions.allowed
```

| Step | Who | Change | Effect |
|---|---|---|---|
| Release `1.1.0` | Stakater | a chart that ships, for example, `1.0.0`, `1.0.1` and `1.1.0` | tested first: the render tests, the live suite and the upgrade suite (G.10) |
| Install | platform | the chart, on the test and the production cluster | no tenant changes; the parts that are not per tenant update with a rolling restart |
| Try | team | `version: "1.1.0"` on the test cluster | only that tenant's objects re-render, from `1.1.0`; the team tests |
| Move | team | the same change on the production cluster | only that tenant's objects re-render |
| Roll back | team | the previous version back | that tenant's objects re-render from it |
| Next release | Stakater, then platform | a chart that drops `1.0.0` | the install is refused while a gateway request names `1.0.0`; the error names the tenant |
| Narrow | platform | remove a version from `versions.allowed` | refused while a gateway request names it; the error names the tenant |

Admission refuses a gateway request with no `version`, or with a version not in
`versions.allowed`, so a wrong version never reaches Template Operator and
never removes a gateway. The ConfigMap `mto-api-gateway-versions` in
`mto-api-gateways` lists each tenant and its version; a tenant's status
ConfigMap warns when its version is the oldest allowed one. For a
security fix, the platform tells the teams on the affected versions, with a
deadline. The platform never moves a team.

The parts that are not per tenant (the token floor and the default deny, the
rate limit service, the admission policies) change with the install, for
every tenant, and must work with every version the release ships; the render
tests and the live suite check each version.

No downtime: object names stay the same across versions (updated in place,
never deleted and created again); gateway and waypoint pods restart one at a
time with at least two pods, a disruption budget and connection draining; a
mesh upgrade stays a platform task and moves one tenant's gateway at a time
with the `istio.io/rev` label (`gateway.meshRevision`, M22); the rate limit
service restarts one pod at a time; and the design stays closed in any apply
order (§4). G.28 measures each move.
