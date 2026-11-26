# Feature parity: the per-API gateway charts and this extension

Every feature of the per-API gateway charts we replace (the gateway chart,
the shared rate limit chart, the realm chart, the end-to-end runner and the
mesh charts), and what this extension does instead. Use it to check that an
API can move without losing a feature (docs/migration.md).

**Status:** ✅ the same · ➕ the same, and safer or simpler · 🔄 changed (see
the note) · ⏳ not yet, a later story · ❌ not supported, by decision · ➖ not
part of the extension: it stays with the platform, unchanged.

## 1. Gateway and listeners

| Feature today | This extension | Status |
|---|---|---|
| One gateway per API, created by the API's own chart release | one gateway per tenant, requested with a `TemplateInstance` (ADR-0002) | 🔄 |
| Reuse an existing gateway (`gateway.create: false`) | all APIs of a tenant share its gateway | ✅ |
| Istio deploys the gateway's Deployment, Service and ServiceAccount | the same (M3) | ✅ |
| Gateway Service type `NodePort` (open on every node) | `ClusterIP`; the annotation must be on the `Gateway` itself (observed on kind, M13) | ➕ |
| One HTTPS listener with no hostname (any SNI), because the router's reencrypted connection has no SNI | the `entry` listener with no hostname for router traffic (ADR-0009); the `tenant` listener with a hostname needs SNI (R4, G.0) | 🔄 |
| Routes only from the gateway's own namespace | routes only from the tenant's namespaces (A1) | 🔄 |
| Gateway in any namespace the team names | in the namespace of the team's request | ✅ |
| Object names from `gateway.name` and the release | names from the request and the API (design §6) | ✅ |
| Standard labels on every object | Template Operator's ownership labels | ✅ |
| Gateway pod settings not configurable | scaling and labels through `spec.infrastructure` (platform values) | ➕ |

## 2. Hosts, paths and routing

| Feature today | This extension | Status |
|---|---|---|
| An internal host per API on the cluster's router domain, with its own OpenShift Route | the platform grants internal hosts to the tenant; the `api` instance's `internalHost` picks one; one reencrypt `Route` per host to the `entry` listener (ADR-0009, G.18); a moved API keeps its old name | 🔄 |
| A shared front-door host, split by path, with one OpenShift Route per gateway | the platform grants each tenant path prefixes; one reencrypt Route per prefix (ADR-0009) | ✅ |
| The route binds only to its hosts | the `api` instance's `host` | ✅ |
| Public path prefix | `path` | ✅ |
| Operation allow list: exact path and method | `operations` | ✅ |
| Route matches on headers or query parameters | not supported; no API uses them today | ❌ |
| Path prefix rewrite | `rewrite` | ✅ |
| `Host` rewrite for an external backend | the same (ADR-0014) | ✅ |
| Backend Service in another namespace, with a `ReferenceGrant` | the `api` instance lives in the backend's namespace; no `ReferenceGrant` | 🔄 |
| No timeouts, retries, redirects, CORS, header filters or mirroring | the same: none | ✅ |
| The front doors themselves (DNS, router certificates) | outside the extension | ➖ |

## 3. TLS and certificates

| Feature today | This extension | Status |
|---|---|---|
| Listener TLS mode `Terminate` | the same | ✅ |
| Gateway serving certificate from OpenShift's service CA, rotated automatically | the same for the `entry` listener (R3); certificates from a platform issuer for the `tenant` listener (Q10) | ✅ |
| Router reencrypts with no destination CA | the same (R3) | ✅ |
| Gateway to backend over mesh mTLS | the same | ✅ |
| TLS origination to an external host (`SIMPLE`, `MUTUAL`, `DISABLE`) | `tls`, `tlsSni`, `tlsSecret` (ADR-0014) | ✅ |
| istiod trusts the internal CA when it fetches keys | mesh setting, unchanged | ➖ |

## 4. Authentication

| Feature today | This extension | Status |
|---|---|---|
| Validate the token against one issuer, set per gateway by the team | the platform registers issuers; an API uses its tenant's or names its own (ADR-0004) | 🔄 |
| Issuer from Keycloak host and realm; `jwksUri` override | `auth.issuers.<name>.url` and `.jwksUri` | ✅ |
| Audience check | per issuer (`audiences`) | ✅ |
| istiod fetches the keys | the same; reload every 3 minutes (M19) | ✅ |
| `realmRevision` restarts the gateway pods after a realm import | replaced by the 3-minute reload; a stable signing key is G.27 | 🔄 |
| No token or wrong API: `403`; bad token: `401` | the same; a token of an issuer the gateway doesn't trust: `401` (observed) | ✅ |
| Token also accepted in the `access_token` query parameter | refused: `Authorization` header only (M15); checked before a move | 🔄 |
| The token is not forwarded to the backend | the same | ✅ |
| Authentication can be turned off entirely | not possible (ADR-0004) | ❌ |
| Legacy mode: an issuer with keys written in, access by a list of client IDs | not supported; the issuer is being retired (ADR-0004) | ❌ |

## 5. Authorization and headers

| Feature today | This extension | Status |
|---|---|---|
| Allow only tokens whose `allowed_apis` matches a typed pattern | a derived, closed rule `api.<tenant>.<api>`, plus today's role names as exact values during migration (ADR-0006) | ➕ |
| Authorization bound to the API's hosts | bound to host **and** path (ADR-0005); path tricks refused (observed) | ➕ |
| `x-sub` from `azp`, `x-roles` from `allowed_apis` | the same, always | ✅ |
| A team's own claim headers | `claim-headers` knob (ADR-0012) | ✅ |
| Caller copies of claim headers removed before the token check | the same: the platform's header filter (ADR-0003) | ✅ |
| Other caller headers pass through to the backend | the same | ✅ |

## 6. Correlation ID, logs and traces

| Feature today | This extension | Status |
|---|---|---|
| Add the correlation header from `x-request-id` when absent | `correlation-id` knob; the header name is a platform value | ✅ |
| Per-gateway access log provider | `access-log` knob, from the platform's list | ✅ |
| Extra trace tags from headers | `trace-headers` knob | ✅ |
| 100 % trace sampling on each gateway | `telemetry.tracing.samplingPercentage`, default 100, in each gateway's `Telemetry` (ADR-0012) | ✅ |
| Access log formats and the tracing provider in the mesh configuration | unchanged | ➖ |

## 7. Rate limiting

| Feature today | This extension | Status |
|---|---|---|
| Rate limit on or off per API, by the team | `rateLimit: "off"`; the platform can lock a tenant (ADR-0004) | ✅ |
| Tier from the caller's role, Lua code, highest tier wins, default bronze | the same rules, by exact text with no Lua (CEL expression, observed on kind, M20) | ➕ |
| Hyphenated API names put every caller on bronze (bug) | fixed: callers get their real tier (checked before a move) | 🔄 |
| Counter per tier, API and caller | the same (per tenant, API, tier and `azp`) (observed) | ✅ |
| Rate limiter down: requests pass (fail open), 0.25 s timeout | a platform value; fail open observed | ✅ |
| `429` without `X-RateLimit-*` headers | the same | ✅ |
| Shared rate limit service (`envoyproxy/ratelimit`), tiers and rates | deployed by the bootstrap chart from platform values | ✅ |
| Its scaling, disruption budget, spread, resources and Redis health probes | the same defaults, as platform values `rateLimit.service.*` (design §3.1) | ✅ |
| Its pods restart when the limits change | the same: a limit change creates a new `ConfigMap` and rolls the pods (S1) | ✅ |
| Redis with Sentinel, persistence, password, access only from the limiter | Redis provided by the platform: one server or Sentinel (`rateLimit.redis.type`), address and password Secret | ➖ |

## 8. Backends

| Feature today | This extension | Status |
|---|---|---|
| In-cluster backend Service | `service`, `port` | ✅ |
| External backend: `ServiceEntry`, `DestinationRule`, `ExternalName` Service | the same (ADR-0014) | ✅ |
| Exactly one backend kind | exactly one of `service` and `externalHost` | ✅ |

## 9. Backend lock

| Feature today | This extension | Status |
|---|---|---|
| Waypoint per backend namespace and an L7 policy: only the gateway, except open paths | the same, written as a `DENY` (ADR-0007); observed on kind | ➕ |
| Open paths for probes and scrapers | platform list `backendLock.publicPaths` | ✅ |
| Lock off, with an explicit acknowledgement | `backendLock: "off"`; the platform can lock a tenant | ✅ |
| The chart refuses auth without a lock choice | the lock is on unless the team turns it off | ✅ |
| STRICT mTLS on backend pods (optional, unused) | per tenant, by the platform (`backendLock.strictMtlsTenants`), off by default: callers outside the mesh refused, kubelet probes pass, scrapers outside the mesh refused (observed, ADR-0007) | 🔄 |
| Calls to a pod's IP, and from outside the mesh, bypass the waypoint | the same (observed: M21, Q21); STRICT closes the path from outside the mesh for a tenant | ✅ |
| Waypoint autoscaling and disruption budget | platform values (ADR-0007) | ✅ |
| A waypoint shared from another namespace | one waypoint per backend namespace | 🔄 |

## 10. Scaling and monitoring

| Feature today | This extension | Status |
|---|---|---|
| Gateway autoscaler and disruption budget | the same, platform values (ADR-0002) | ✅ |
| `PodMonitor`s for the gateway and the waypoint (metrics for Kiali and Grafana) | the same, `monitoring.podMonitor.*`, default on, 30 s; the port `metrics`, `/stats/prometheus` (observed, M23) | ✅ |

## 11. Namespaces and prerequisites

| Feature today | This extension | Status |
|---|---|---|
| Mesh labels on gateway and backend namespaces, set in the `Tenant` | the same (M5) | ✅ |
| The waypoint label on backend namespaces | the same (ADR-0007) | ✅ |
| A missing label fails silently | reported in the status (`outside-mesh`) | ➕ |
| OVN-Kubernetes `routingViaHost` for ambient | cluster prerequisite, unchanged | ➖ |

## 12. Realm, consumers and tooling

| Feature today | This extension | Status |
|---|---|---|
| Realm import, the role matrix API × tier, consumer clients and secrets, the audience and `allowed_apis` mappers, token lifetimes, issuer pinned with `frontendUrl` | unchanged: the gateway reads today's roles (ADR-0003, ADR-0006) | ➖ |
| A signing key pinned across realm imports (optional, off) | later: G.27 | ⏳ |
| Consumer scripts (create, rotate, seal, export) | unchanged | ➖ |

## 13. End-to-end checks

| Feature today | This extension | Status |
|---|---|---|
| A runner per API: real token, `403` anonymous, `200` authenticated, `429` under load | unchanged; it must target the new gateway after a move (docs/migration.md) | ➖ |
| Checks for the lock, header stripping, tiers and correlation ID | the extension's acceptance suite (docs/acceptance.md) | ➕ |

## 14. Mesh installation

| Feature today | This extension | Status |
|---|---|---|
| Service Mesh and Kiali operators, Istio in ambient mode, CNI, ztunnel, discovery selector, resources, tracing, access log formats, monitors, Kiali | unchanged, the platform's (docs/support-matrix.md) | ➖ |
| No key reload setting for istiod | the 3-minute reload is an install requirement | 🔄 |

## 15. Across the charts

| Feature today | This extension | Status |
|---|---|---|
| Renders with `helm template` (Argo CD), so no `lookup` | no `lookup`; the preflight checks values by schema, APIs by `.Capabilities`, and the live state in a hook `Job` that Argo CD runs as `PreSync` (design §9) | ✅ |
| One release writes into two namespaces | Template Operator renders into the tenant's namespaces | ✅ |
| Each team keeps its own copy of the chart, and versions drift | one platform chart, one upgrade (ADR-0015) | ➕ |
| Names must agree across realm, gateway and limiter | the same roles; tier names are platform values | ✅ |
| Unsafe combinations fail at render | the templates check every value; refusals in the status | ✅ |
| Helm refuses to take over an object that another release or a person created | reserved names, an admission policy that refuses a takeover, and a preflight check (ADR-0001) | ✅ |
