# Parameters

Every setting of today's per-API gateway chart (the pattern in
[vision.md](vision.md)), and where it goes in this extension. A setting goes
to one of four places:

| Place | Who sets it | How |
|---|---|---|
| **Platform value** | the platform team | a value of the bootstrap chart, once per cluster; some are per tenant |
| **Team input** | the API team | the standard fields of an `HTTPRoute`, and one annotation. The gateway request (`TemplateInstance` of `api-gateway`) has **no parameters**: the team chooses its namespace and name, and may set a few validated annotations (§3, ADR-0012) |
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
| `backend.external.host`, `.port`, `.pathPrefix` | the `api` instance's `externalHost`, `port`, `rewrite`; the `ExternalName` Service and the `Host` rewrite are rendered (ADR-0014) | team input | G.16 |
| `backend.external.tls.mode`, `.sni`, `.credentialName` | the `api` instance's `tls`, `tlsSni`, `tlsSecret` (a Secret in the gateway's namespace); the `ServiceEntry` and `DestinationRule` are rendered (ADR-0014) | team input | G.16 |
| `auth.jwt.allowedApis` (free text) | the rule `api.<tenant>.<api>`, closed; the team gives only the API name, as the name of its `api` instance (ADR-0005) | derived | G.3 |
| `hosts.internalDomain` (a second, internal host) | open: a second base domain on its own listener, or a decision of the entry point (Q10) | platform value | G.18 |

### Security switches today: removed

| Today | In this extension | Place | Story |
|---|---|---|---|
| `auth.enabled` | the token floor, the default deny and the allowed-API rules are always rendered (ADR-0004) | fixed | G.2 |
| `rateLimit.enabled` | the platform-owned rate limit filter is always rendered (ADR-0003) | fixed | G.5 |
| `security.allowGatewayAccessOnly`, `security.allowDirectBackendAccess` | the `api` instance's `backendLock: "on"` (default) or `"off"`; the platform can lock a tenant (ADR-0007) | team, within platform bounds | G.4 |
| `security.waypoint.create`, `security.waypoint.name`, `.autoscaling` | the child renders one waypoint `api-gateway-waypoint` per namespace with a locked API, autoscaled with platform values (ADR-0007) | platform value | G.4 |
| `security.publicPaths` | `backendLock.publicPaths`, a platform list of exact paths | platform value | G.4 |

### Security values the team sets today: now the platform's

| Today | In this extension | Place | Story |
|---|---|---|---|
| `auth.jwt.realm` | `auth.issuers`, with `defaultIssuers` and `tenantIssuers`: one issuer, several, or one per tenant (ADR-0004) | platform value | G.2 |
| `auth.jwt.audiences` | `auth.audience` | platform value | G.2 |
| `auth.jwt.forwardClaims` (`azp` → `x-sub`, `allowed_apis` → `x-roles`) | `auth.headers`; the gateway replaces any value the caller sent | platform value | G.2 |

### What the chart or the platform sets today

| Today | In this extension | Place | Story |
|---|---|---|---|
| gateway replicas, fixed at 3 | `gateway.autoscaling` (minimum, maximum, CPU target) and `gateway.podDisruptionBudget` | platform value | G.1 ✅ |
| gateway class `istio` | `gateway.className`, only `istio` | platform value | G.1 ✅ |
| TLS terminate, the certificate | `gateway.tls.certManager.issuerRef`, or a Secret the platform provides | platform value | G.1 ✅ |
| rate limit tiers, in the platform's rate limit chart | `rateLimit.tiers`; the caller's tier from its role for the API (ADR-0003) | platform value | G.5 |
| rate limit service and its store | a rate limit service that speaks Envoy's rate limit API, with Redis | platform | G.5 |
| `EnvoyFilter` that strips caller headers | a platform-owned header filter, rendered with every tenant gateway (ADR-0003) | fixed | G.2 |
| `EnvoyFilter` for the rate limit (with Lua) | a platform-owned rate limit filter with no Lua; tier and caller read as plain claims (ADR-0003) | fixed | G.5 |
| `EnvoyFilter` for a correlation ID (some APIs) | open: Envoy's own `x-request-id` may be enough (Q11) | platform value, if any | G.0 |
| `Telemetry`: log format, tracing | per-tenant observability | platform value | G.14 |
| a log format for one team | per-tenant observability | platform value | G.14 |
| `RequestAuthentication` (issuer, keys, audience) | the same kind, with the Istio token floor, from platform values | fixed, from platform values | G.2 |
| `ReferenceGrant` | not rendered | — | — |
| the chart version, one copy per team | the bootstrap chart's version; one upgrade for all | platform | — |

### Outside the chart today, and still outside

| Today | In this extension | Who | Story |
|---|---|---|---|
| mesh labels on the namespaces | stay in the `Tenant`; the extension reports a namespace outside the mesh | platform, in the Multi-Tenant Operator | G.6 |
| the waypoint label on the backend namespace | stays: `istio.io/use-waypoint`, set through the `Tenant`; the extension reports a namespace without it | platform, in the Multi-Tenant Operator | G.4 |
| the identity provider's client and role per API | manual; the role is `api.<tenant>.<api>` | platform, in RHBK | G.11 |

## 2. The platform's values (bootstrap chart)

### Built (G.1)

| Value | Default | Meaning |
|---|---|---|
| `gateway.baseDomain` | `""`, required | each tenant's listener serves `*.<tenant>.<baseDomain>` |
| `gateway.className` | `istio` | the only accepted value |
| `gateway.port` | `443` | listener port |
| `gateway.extraHostnames` | `{}` | **per tenant**: extra host names, each on its own listener |
| `gateway.sharedHosts` | `[]` | hosts that several tenants share, each with the path prefixes granted **per tenant**; each prefix gets a reencrypt OpenShift `Route` to the tenant's gateway (ADR-0009) |
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
| `auth.issuers.<name>.url` | none, at least one issuer required | a token issuer the platform trusts; the token floor accepts the principals of every issuer | G.2 |
| `auth.issuers.<name>.audiences` | none, required | the audiences a token of this issuer must carry | G.2 |
| `auth.issuers.<name>.jwksUri` | empty | the key set's URL (`RequestAuthentication` `jwksUri`), when the issuer's host is not reachable from the cluster; the issuer still pins `iss` | G.2 |
| `auth.issuers.<name>.tenant` | empty | the tenant that runs this issuer; it may then be used only by that tenant | G.2 |
| `auth.defaultIssuers` | none, required unless every tenant has a list | the issuers of every tenant without its own list: one or many | G.2 |
| `auth.tenantIssuers` | `{}` | **per tenant**: its default issuers, instead of `defaultIssuers`; an API may also name issuers registered with `tenant: <its tenant>` (ADR-0004) | G.13 |
| `rateLimit.failureModeAllow` | to decide in G.5 | whether calls pass when the rate limit service is down; documented as a limit (ADR-0003) | G.5 |
| `rateLimit.redis.address`, `rateLimit.redis.passwordSecret` | none, required with the rate limit | the platform's Redis for the counters | G.5 |
| `rateLimit.unlimitedTenants` | `[]` | tenants the platform exempts from the rate limit; their filter stays (ADR-0004) | G.5 |
| `rateLimit.unlimitedApis` | `[]` | single APIs the platform exempts, as `<tenant>.<api>`; the tenant's other APIs keep their limits (ADR-0004) | G.5 |
| `rateLimit.lockedTenants` | `[]` | tenants whose teams may not turn an API's limit off; their `rateLimit: "off"` is refused (ADR-0004) | G.5 |
| `backendLock.publicPaths` | `/metrics`, `/health`, `/health/live`, `/health/ready`, `/healthz` | paths on a locked backend that anyone may call; exact paths, never a pattern (ADR-0007) | G.4 |
| `backendLock.waypoint.autoscaling.minReplicas`, `.maxReplicas` | `3`, `5` | each backend namespace's waypoint, as today | G.4 |
| `backendLock.lockedTenants` | `[]` | tenants whose teams may not turn a backend lock off (ADR-0007) | G.4 |
| `rollout.default` | `g1` | the template generation every tenant and API uses (ADR-0015) | G.28 |
| `rollout.canary.tenants`, `rollout.canary.apis` | `[]` | tenants, and APIs as `<tenant>.<api>`, on the next generation; the schema allows only the generations the release contains | G.28 |
| `gateway.meshRevision.default`, `gateway.meshRevision.tenants` | empty (the mesh's default revision) | the Istio revision each tenant's gateway uses, rendered as the label `istio.io/rev`, for a mesh upgrade one tenant at a time (ADR-0015, M22) | G.28 |
| `istio.rootNamespace` | `istio-system` | where the token floor and default deny live | G.2 |
| `istio.trustDomain` | `cluster.local` | the trust domain in the gateway's principal for the backend lock | G.4 |
| `headers.reserved` | the platform's list | header names a team can't map a claim to, always removed from callers | G.2, G.25 |
| `correlationId.header` | `x-correlation-id` | the header the correlation-ID knob sets | G.25 |
| `telemetry.accessLogProviders`, `telemetry.tracing` | `[]`, off | the access log providers a team may choose; whether trace headers may be set | G.25 |
| `auth.claims.allowedApis` | `allowed_apis` | the list claim with the caller's APIs | G.2, G.3 |
| `auth.claims.caller` | `azp` | the caller's identity: the `x-sub` header and the rate limit counter | G.2, G.5 |
| `auth.headers.caller`, `auth.headers.roles` | `x-sub`, `x-roles` | the headers the gateway sets from the token | G.2 |
| `api.rulePrefix` | `api` | the first segment of `api.<tenant>.<api>` | G.24 |
| `migration.legacyRoles` | `{}` | **per API**, `<tenant>.<api>: <old role name>`: the API also accepts `<old>-<tier>` roles, so callers' tokens don't change when it moves (ADR-0006) | G.9 |
| `migration.oldGateways` | `{}` | **per API**, `<tenant>.<api>: <old gateway's service account principal>`: the API's lock also lets the old gateway pass while both run (ADR-0007, docs/migration.md) | G.9 |
| `rateLimit.tiers` | `gold` 1000/s, `silver` 50/s, `bronze` 10/s | the tiers and their rates | G.5 |
| `rateLimit.defaultTier` | `bronze` | the catch-all for a missing or unknown tier; never "no limit" | G.5 |

No platform value is a switch for the token check or the header replacement.
The backend lock can be turned off by the team for its API (`backendLock:
"off"`, unless the tenant is in `backendLock.lockedTenants`, ADR-0007). The
rate limit can be turned off: by the team for its API
(the `api` instance's `rateLimit: "off"`, unless the tenant is in
`rateLimit.lockedTenants`), or by the platform (`rateLimit.unlimitedTenants`,
`rateLimit.unlimitedApis`). No team annotation names a security setting
(AC-R-3).

## 3. The team's inputs

| Input | Where | Example |
|---|---|---|
| the gateway request | a `TemplateInstance` of `api-gateway`: its namespace and name, no parameters | `api-gateway` in `team-a-dev` |
| team settings | annotations `api-gateway.stakater.com/*` on the request: `claim-headers`, `correlation-id`, `access-log`, `trace-headers`; validated, refused keys listed (ADR-0012) | `claim-headers: client_id=x-client` |
| the API | a `TemplateInstance` of `api` in the backend's namespace; its name is the API name, a DNS label unique in the tenant (ADR-0005) | `orders` in `team-a-dev` |
| host, path, rewrite, backend, operations | the `api` instance's parameters `host` (default `<api>.<tenant>.<base domain>`), `path`, `rewrite`, `service` or `externalHost` (with `tls`, `tlsSni`, `tlsSecret`, ADR-0014), `port`, `operations`, `issuers`, `rateLimit`, `backendLock`; checked by the template; APIs share a host by path (ADR-0005) | `orders.team-a.apis.example.com`, `/orders/v2` → `/orders/v1`, Service `orders` port 80 |

The first proposal's six parameters map like this:

| First proposal | This extension (`api` instance, ADR-0005) |
|---|---|
| `apiName` | the instance's name |
| `backendNamespace` | the instance's namespace |
| `backendService` | `service` and `port` |
| `backendPath` | `rewrite` |
| `exposedPath` | `path`, or exact `operations` |
| `externalHost` | `host` |

Between environments, a route changes only its namespace and its host name
(`orders.team-a…`, `orders-test.team-a…`). The gateway request is made once
per tenant.

## 4. Derived: nobody types these

| What | From |
|---|---|
| the tenant | the request's or the route's namespace, through `tenantOf` (the namespace label) |
| the gateway's name and every gateway-level object name | the request's name |
| the listener host name `*.<tenant>.<base domain>` | the tenant and `gateway.baseDomain` |
| the allowed-API rule `api.<tenant>.<api>` and the tenant floor `api.<tenant>.` | the prefix, the tenant, the annotation |
| the backend lock's principal `cluster.local/ns/<namespace>/sa/<request>-istio` | the gateway's namespace and name |
| the backend lock's target | the backend `Service` (the policy's `targetRefs`), enforced by the namespace's waypoint |
| which request owns the tenant's gateway | the oldest valid request (`owner`) |

## 5. Fixed: never a parameter

The token floor and the issuer pin; the default deny; the closed allowed-API
rule per API; the header replacement; HTTPS
with TLS terminated at the gateway; `allowedRoutes` from the tenant's
namespaces only, `HTTPRoute` only; sync mode `strict` for the team-facing
Template; no `EnvoyFilter` but the two allowlisted platform filters, and no
Lua (ADR-0003, ADR-0004).

## 6. Open

- **Per-tenant platform values.** `gateway.extraHostnames`, the prefixes in
  `gateway.sharedHosts`, `auth.tenantIssuers`, `rateLimit.unlimitedTenants` and
  `rateLimit.unlimitedApis` are per tenant. A per-tenant autoscaling range
  or tier set is not designed. Add it when a tenant needs it, as a platform
  value, never as a team input.
- **The internal host name.** Today an API has a second, internal host. G.18
  decides whether that is a second listener or an entry-point matter (Q10).
