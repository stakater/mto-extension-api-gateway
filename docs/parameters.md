# Parameters

Every setting of today's per-API gateway chart (the pattern in
[vision.md](vision.md)), and where it goes in this extension. A setting goes
to one of four places:

| Place | Who sets it | How |
|---|---|---|
| **Platform value** | the platform team | a value of the bootstrap chart, once per cluster; some are per tenant |
| **Team input** | the API team | the standard fields of an `HTTPRoute`, and one annotation. The gateway request (`TemplateInstance` of `api-gateway`) has **no parameters**: the team chooses only its namespace and name |
| **Derived** | nobody | the chart computes it from the tenant, the request and the route |
| **Fixed** | nobody | always on, in the chart; no value turns it off (vision principle 2) |

Names of planned values are proposals. Each story fixes the names it builds.

## 1. Today's settings, one by one

### What the team sets today, per API

| Today | In this extension | Place | Story |
|---|---|---|---|
| `gateway.name` | the request's name: `Gateway` `<request>` | team input (the name only) | G.1 ✅ |
| `gateway.namespace` | the request's namespace | team input | G.1 ✅ |
| `hosts.external` | `HTTPRoute` `spec.hostnames`. It attaches only under `*.<tenant>.<base domain>` or a host name the platform granted to the tenant | team input, bounded by platform values | G.1 ✅, G.3 |
| `gateway.pathPrefix` (the published path) | `HTTPRoute` `rules[].matches[].path` | team input | G.3 |
| `backend.internal.service`, `backend.internal.port` | `HTTPRoute` `rules[].backendRefs[]` `name`, `port` | team input | G.3 |
| `backend.internal.pathPrefix` (the backend's path) | `HTTPRoute` `URLRewrite` filter, `ReplacePrefixMatch` | team input | G.3 |
| `backend.internal.namespace` | none. The backend is in the route's namespace, so no `ReferenceGrant` is needed | — | G.3 |
| `auth.jwt.allowedApis` (free text) | the rule `api.<tenant>.<api>`, closed; the team gives only the API name, in the annotation `api-gateway.stakater.com/api` | derived | G.3 |
| `hosts.internalDomain` (a second, internal host) | open: a second base domain on its own listener, or a decision of the entry point (Q10) | platform value | G.18 |

### Security switches today: removed

| Today | In this extension | Place | Story |
|---|---|---|---|
| `auth.enabled` | the baseline `AuthPolicy` is always rendered, as an override | fixed | G.2 |
| `rateLimit.enabled` | the tier `RateLimitPolicy` is always rendered, as an override | fixed | G.5 |
| `security.allowGatewayAccessOnly` | the backend lock is always rendered; a route whose backend can't be locked serves nothing | fixed | G.4 |
| `security.waypoint.create`, `security.waypoint.name` | no waypoint. ztunnel enforces the backend lock on the mesh identity (L4) | fixed | G.4 |

### Security values the team sets today: now the platform's

| Today | In this extension | Place | Story |
|---|---|---|---|
| `auth.jwt.realm` | `auth.issuerUrl`, one issuer per cluster | platform value | G.2 |
| `auth.jwt.audiences` | `auth.audience` | platform value | G.2 |
| `auth.jwt.forwardClaims` (`azp` → `x-sub`, `allowed_apis` → `x-roles`) | `auth.headers`; the gateway replaces any value the caller sent | platform value | G.2 |

### What the chart or the platform sets today

| Today | In this extension | Place | Story |
|---|---|---|---|
| gateway replicas, fixed at 3 | `gateway.autoscaling` (minimum, maximum, CPU target) and `gateway.podDisruptionBudget` | platform value | G.1 ✅ |
| gateway class `istio` | `gateway.className`, only `istio` | platform value | G.1 ✅ |
| TLS terminate, the certificate | `gateway.tls.certManager.issuerRef`, or a Secret the platform provides | platform value | G.1 ✅ |
| rate limit tiers, in the platform's rate limit chart | `rateLimit.tiers` and `rateLimit.tierClaim` | platform value | G.5 |
| rate limit service and its store | Limitador, from Connectivity Link | prerequisite | — |
| `EnvoyFilter` that strips caller headers | the baseline `AuthPolicy` sets `x-sub` and `x-roles` from the token | fixed | G.2 |
| `EnvoyFilter` for the rate limit | the tier `RateLimitPolicy` | fixed | G.5 |
| `EnvoyFilter` for a correlation ID (some APIs) | open: Envoy's own `x-request-id` may be enough (Q11) | platform value, if any | G.0 |
| `Telemetry`: log format, tracing | per-tenant observability | platform value | G.14 |
| a log format for one team | per-tenant observability | platform value | G.14 |
| `RequestAuthentication` (issuer, keys, audience) | the baseline `AuthPolicy`, and the Istio token floor from the same values | fixed, from platform values | G.2 |
| `ReferenceGrant` | not rendered | — | — |
| the chart version, one copy per team | the bootstrap chart's version; one upgrade for all | platform | — |

### Outside the chart today, and still outside

| Today | In this extension | Who | Story |
|---|---|---|---|
| mesh labels on the namespaces | stay in the `Tenant`; the extension reports a namespace outside the mesh | platform, in the Multi-Tenant Operator | G.6 |
| the waypoint label on the backend namespace | not needed: no waypoint | — | G.4 |
| the identity provider's client and role per API | manual; the role is `api.<tenant>.<api>` | platform, in RHBK | G.11 |

## 2. The platform's values (bootstrap chart)

### Built (G.1)

| Value | Default | Meaning |
|---|---|---|
| `gateway.baseDomain` | `""`, required | each tenant's listener serves `*.<tenant>.<baseDomain>` |
| `gateway.className` | `istio` | the only accepted value |
| `gateway.port` | `443` | listener port |
| `gateway.extraHostnames` | `{}` | **per tenant**: extra host names, each on its own listener |
| `gateway.autoscaling.minReplicas`, `.maxReplicas`, `.targetCPUUtilizationPercentage` | `2`, `5`, `80` | the gateway's autoscaler; the minimum is at least 2 |
| `gateway.podDisruptionBudget.minAvailable` | `1` | below the minimum replicas, so a node drain can evict a pod |
| `gateway.tls.certManager.issuerRef` | `ClusterIssuer`, no name | with a name, one `Certificate` per listener |
| `tenants.mode`, `tenants.list` | `all`, `[]` | which tenants may request a gateway |
| `tenantLabelKey` | `stakater.com/tenant` | the Multi-Tenant Operator's namespace label |
| `templateOperator.serviceAccountName`, `.namespace` | Template Operator's defaults | who gets the chart's RBAC |
| `templateSync.mode` | `revert` | the parent's sync mode; the team-facing Template is always `strict` |

### Planned

| Value | Proposed default | Meaning | Story |
|---|---|---|---|
| `auth.issuerUrl` | none, required | the one token issuer per cluster; also pinned by an `iss` rule | G.2 |
| `auth.audience` | none, required | the audience a token must carry | G.2 |
| `auth.jwksUrl` | empty | the key set's URL, when the issuer's host is not reachable from the cluster; the issuer pin still checks `iss` (K2) | G.2 |
| `auth.claims.allowedApis` | `allowed_apis` | the list claim with the caller's APIs | G.2, G.3 |
| `auth.claims.caller` | `azp` | the caller's identity: the `x-sub` header and the rate limit counter | G.2, G.5 |
| `auth.headers.caller`, `auth.headers.roles` | `x-sub`, `x-roles` | the headers the gateway sets from the token | G.2 |
| `api.rulePrefix` | `api` | the first segment of `api.<tenant>.<api>` | G.3 |
| `rateLimit.tierClaim` | `tier` | the claim with the caller's tier | G.5 |
| `rateLimit.tiers` | `gold` 1000/s, `silver` 50/s, `bronze` 10/s | the tiers and their rates | G.5 |
| `rateLimit.defaultTier` | `bronze` | the catch-all for a missing or unknown tier; never "no limit" | G.5 |

No platform value is a switch for the token check, the header replacement,
the rate limit or the backend lock. The per-tenant chart has no key for any
security value, and a `tenantValues` entry for one fails the render (AC-R-3).

## 3. The team's inputs

| Input | Where | Example |
|---|---|---|
| the gateway request | a `TemplateInstance` of `api-gateway`: its namespace and name, no parameters | `api-gateway` in `team-a-dev` |
| the API name | the annotation `api-gateway.stakater.com/api` on the `HTTPRoute`; a DNS label, unique in the tenant | `orders` |
| host, path, rewrite, backend | the standard fields of the `HTTPRoute` | `dev.team-a.apis.example.com`, `/orders/v2` → `/orders/v1`, Service `orders` port 80 |

The first proposal's six parameters map like this:

| First proposal | This extension |
|---|---|
| `apiName` | the annotation |
| `backendNamespace` | the route's namespace |
| `backendService` | `backendRefs[].name` |
| `backendPath` | the `URLRewrite` filter |
| `exposedPath` | the path match |
| `externalHost` | `spec.hostnames` |

Between environments, a route changes only its namespace and its host name
(`dev.team-a…`, `test.team-a…`). The gateway request is made once per tenant.

## 4. Derived: nobody types these

| What | From |
|---|---|
| the tenant | the request's or the route's namespace, through `tenantOf` (the namespace label) |
| the gateway's name and every gateway-level object name | the request's name |
| the listener host name `*.<tenant>.<base domain>` | the tenant and `gateway.baseDomain` |
| the allowed-API rule `api.<tenant>.<api>` and the tenant floor `api.<tenant>.` | the prefix, the tenant, the annotation |
| the backend lock's principal `cluster.local/ns/<namespace>/sa/<request>-istio` | the gateway's namespace and name |
| the backend lock's pod selector and ports | the backend `Service`'s selector and target ports |
| which request owns the tenant's gateway | the oldest valid request (`owner`) |

## 5. Fixed: never a parameter

The token check, the issuer pin and the tenant floor; the header replacement;
the rate limit; the default deny per listener; the backend lock; HTTPS with
TLS terminated at the gateway; `allowedRoutes` from the tenant's namespaces
only, `HTTPRoute` only; the baseline as `overrides` with `strategy: merge`;
sync mode `strict` for the team-facing Template; no `EnvoyFilter`.

## 6. Open

- **Per-tenant platform values.** Only `gateway.extraHostnames` is per tenant
  today. A per-tenant autoscaling range or tier set is not designed. Add it
  when a tenant needs it, as a platform value, never as a team input.
- **The internal host name.** Today an API has a second, internal host. G.18
  decides whether that is a second listener or an entry-point matter (Q10).
- **The correlation ID.** Q11: Envoy's `x-request-id`, or another header.
- **Log format and tracing.** G.14.
