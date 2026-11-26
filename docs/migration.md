# Migration runbook: from per-API gateways to tenant gateways

What each feature of today's charts becomes: [`parity.md`](parity.md).

How an API moves from its own gateway (one Helm release per API, the pattern
we replace) to its tenant's gateway, **with no change for its callers**. The
per-API gateways serve production, so every step can be undone and every API
moves on its own. Story G.9 rehearses this runbook on a lab; acceptance
scenarios AC-MIG-1 to AC-MIG-4 prove it.

Running example: tenant `team-a`, API `orders`, today on its own gateway with
the public path `/orders-v2/v1` on the shared front host `front.example.com`,
backend path `/orders/v1`, Service `orders` port 80, and caller roles named
`api-orders-consumer-<tier>`.

## The rules

1. **Callers change nothing:** the same address, path, token and answers.
1. **One API at a time, on the test cluster first,** then production.
1. **Old and new run side by side.** One change moves the API's path to the
   tenant gateway; one change moves it back.
1. **Nothing changes in the identity provider.** Today's tokens work on the
   tenant gateway through the platform's old-role mapping (ADR-0006).
1. **Measure before and after,** and move back when the numbers say so.

## What changes, and what doesn't

| Part | Changes? |
|---|---|
| Identity provider, realm chart, roles, callers' tokens | no |
| Callers: address, path, token | no |
| Callers' limits | no, except where today's tier lookup was wrong (step 3.c) |
| Backend code | no: it gets the same `x-sub` and `x-roles` values |
| Backend namespace | joins the mesh, if it isn't in it yet (section 2); its waypoint label moves to the new waypoint at clean-up (step 3.h) |
| Per-API gateway release | its backend lock turned off before the test (step 3.d); removed at the end (step 3.h) |
| Dashboards and alerts on the old gateway names | follow the new gateway's names |

## 1. Once per cluster (platform team)

1. **Install the bootstrap chart.** Template Operator v2 must be running.
1. **Set its values to match today's behaviour:**
    - `auth.issuers`: the identity provider that issues today's tokens, with
      `jwksUri` when its host is not reachable from the cluster;
      `auth.defaultIssuers` names it (ADR-0004).
    - `rateLimit.tiers`: the same rates as today's shared rate limit
      configuration (for example gold 100, silver 50, bronze 10 per second);
      the failure mode as today (fail open, if that is today's choice).
    - `rateLimit.redis.*`: the platform's Redis.
    - `gateway.sharedHosts`: the shared front host, with each tenant's path
      prefixes (ADR-0009). Grant a prefix that is **shorter** than the paths of
      today's per-API routes, and that the API's path is under segment by
      segment (ADR-0005), for example `/orders-v2` for `/orders-v2/v1`, not
      `/orders` (see step 3.f).
    - `migration.legacyRoles`: for each API that moves, its old role name,
      for example `team-a.orders: api-orders-consumer` (ADR-0006).
    - `migration.oldGateways`: for each API that moves, its old gateway's
      service account principal, so the new lock lets both gateways pass while
      they run side by side (ADR-0007).
    - `backendLock.publicPaths`: the same open paths as today's
      `security.publicPaths` (default `/metrics`, `/health`, `/health/live`,
      `/health/ready`, `/healthz`).
    - `gateway.internalDomain` and `gateway.internalHosts`: the router's
      domain, and for each tenant the internal hosts of its APIs that callers
      use today (`<gateway>-<namespace>.<router domain>`) (ADR-0009).
    - `rateLimit.service.*`, `monitoring.podMonitor.*` and
      `telemetry.tracing.samplingPercentage`: the defaults are today's
      values; change them only where today's differ.
1. **Check the mesh and the router** (already so where gateways share a host
   today):
    - Istio's key reload interval is 3 minutes (design §10).
    - The router that serves the shared host has
      `routeAdmission.namespaceOwnership: InterNamespaceAllowed` (R2).

## 2. Once per tenant (the team, with the platform)

1. **Backend namespaces in the mesh, with a waypoint.** The tenant's backend
   namespaces carry the ambient mesh label and `istio.io/use-waypoint`, set
   through the Multi-Tenant Operator `Tenant` (M5, ADR-0007). Keep today's
   value (for example `api-waypoint`) during the move: the new lock is
   enforced by whichever waypoint the namespace uses. A backend in a shared
   namespace or outside the mesh moves with `backendLock: "off"`, as today's
   `allowDirectBackendAccess`.
1. **Request the tenant gateway:** one `TemplateInstance` of `api-gateway`,
   with annotations that repeat today's gateway settings (ADR-0012):

```yaml
apiVersion: templates.v2.stakater.com/v2alpha1
kind: TemplateInstance
metadata:
  name: api-gateway
  namespace: team-a-dev
  annotations:
    api-gateway.stakater.com/claim-headers: "client_id=x-client"   # today's extra claim headers
    api-gateway.stakater.com/correlation-id: "on"                  # if today's gateway adds it
    api-gateway.stakater.com/access-log: "json-default"            # today's log provider, from the platform list
spec:
  templateRef: { name: api-gateway, namespace: mto-api-gateways }
```

1. **Check its status:** `mto-api-gateway-status.api-gateway` says `ok`, and the settings are
   listed as accepted in `mto-api-gateway-apis`.

## 3. For each API

An API that still accepts tokens from a retired issuer (today's legacy mode:
fixed keys and a list of client IDs) can't move: the tenant gateway doesn't
support that mode (ADR-0004). It moves after its callers use the identity
provider's tokens.

### 3.a Create the `api` instance from today's values

| Today's per-API values | `api` instance parameter |
|---|---|
| `gateway.hosts.external` (the shared host) | `host` |
| the internal host, when callers use it | `internalHost`: the old name, granted to the tenant |
| `gateway.pathPrefix` | `path` |
| `backend.internal.pathPrefix`, when different | `rewrite` |
| `backend.internal.service`, `.port` | `service`, `port` |
| `backend.external.host`, `.port`, `.pathPrefix` | `externalHost`, `port`, `rewrite` (ADR-0014) |
| `backend.external.tls.mode`, `.sni`, `.credentialName` | `tls`, `tlsSni`, `tlsSecret`; copy the Secret into the tenant gateway's namespace |
| `gateway.matches` (exact path and method) | `operations` |
| `rateLimit.enabled: false` | `rateLimit: "off"` |
| `security.allowGatewayAccessOnly: true` | `backendLock: "on"` (the default) |
| `security.allowDirectBackendAccess: true` | `backendLock: "off"` |
| `auth.jwt.host` and `realm`, when not the default issuer | `issuers` (the platform registers it first) |

```yaml
apiVersion: templates.v2.stakater.com/v2alpha1
kind: TemplateInstance
metadata: { name: orders, namespace: team-a-dev }    # the backend's namespace
spec:
  templateRef: { name: api, namespace: mto-api-gateways }
  parameters:
    - { name: host,    value: front.example.com }
    - { name: path,    value: /orders-v2/v1 }
    - { name: rewrite, value: /orders/v1 }
    - { name: service, value: orders }
    - { name: port,    value: "80" }
```

**One API on two public paths today** (two per-API gateways for one backend):
create one `api` instance per path, with two names, and map both to the same
old role name in `migration.legacyRoles`.

Check `api.orders` says `ok`, and `mto-api-gateway-apis` lists the API with no
conflict.

### 3.b Check the caller-facing details

| Check | How | If found |
|---|---|---|
| Tokens sent in the URL (`?access_token=`) | the old gateway's access log | the tenant gateway refuses them (M15): ask those callers to use the `Authorization` header first |
| Callers on the old internal host (`<gateway>-<namespace>.<router domain>`) | the router's access log | grant the old name to the tenant and set `internalHost`; it moves in step 3.f |
| Headers the backend reads | ask the API team | AC-MIG-3 compares them through both gateways |

### 3.c Check the tiers

Today's tier lookup put every caller on the lowest tier when the API name
has a hyphen (M11). The tenant gateway reads the tier by exact text, so those
callers get the tier their role names. **Before such an API moves, its owner
confirms the backend can take the higher rates.** If it can't, the API
waits.

### 3.d Hand over the backend lock

Today's lock is an `ALLOW` that lets only the old gateway through. While it
exists, Istio refuses every request that no `ALLOW` matches, so it would also
refuse the new gateway. So:

1. Check that the new lock exists (`api.orders.orders`) and lets both gateways
   pass (`migration.oldGateways`).
1. Turn off the old release's lock (`security.allowGatewayAccessOnly: false`,
   `security.allowDirectBackendAccess: true`), but keep its waypoint: the
   namespace still uses it.

From then on the new lock guards the backend for both gateways, with the same
open paths; there is no moment without a lock.

### 3.e Test through the new gateway

Before the switch, call the API through the tenant gateway with real tokens,
one per tier, and compare with the old gateway: status codes, the tier limit,
and the headers at the backend (AC-MIG-2, AC-MIG-3).

### 3.f Switch: one change

Remove the old gateway's OpenShift `Route` for the API's path (in the old
release: no external host, or the route turned off). The tenant's `Route` for
the shorter prefix now takes the path.

An API with an internal host also removes the old gateway's internal `Route`
(`<gateway>-internal`) in the same change. The tenant's `Route` for that host
waits behind it, because the router gives a host to the oldest `Route`; the
router admits it when the old one is gone (R5). To move back, the platform
removes the grant, and the old release renders its internal `Route` again.
**G.0 measures how long the host has no backend in that switch.**

Why this is one change: while the old `Route` exists, the router prefers its
longer path (R1), so the old gateway keeps the traffic. **G.0 confirms that
the router prefers the longest path before any production move.**

### 3.g Measure, and move back if needed

For the agreed period, compare the error rate, the p95 latency, and the
count of `401`, `403` and `429` on the path with the period before the
switch (AC-MIG-4). To move back, put the old `Route` back: its longer path
takes the traffic again at once (AC-MIG-1).

### 3.h Clean up

After the agreed period:

1. Move the namespace's `istio.io/use-waypoint` label to
   `mto-api-gateway-waypoint` (through the `Tenant`), and check the lock still
   refuses `intruder`.
1. Uninstall the per-API gateway release: its Lua filter, its policies, its
   waypoint, its pods and its `Route`s. The label must move first, or the
   namespace would point to a waypoint that no longer exists.
1. Remove the API's entry from `migration.oldGateways`.
1. Move dashboards and alerts to the tenant gateway's names.

## 4. After all APIs of a tenant moved

- The old role names can stay; the mapping keeps them working.
- Renaming the roles to `api.<tenant>.<api>.<tier>` is a later, separate
  change: it changes every caller's token, and a realm import gives new
  signing keys (design §12, G.27). When it is done, remove the API's entry
  from `migration.legacyRoles`.

## Open before the first production move

| Item | Where |
|---|---|
| Service Mesh 3's proxy includes the expression rate limit descriptor (M20) | G.0 |
| The router prefers the longest path on a shared host (R1) | G.0 |
| A reencrypted connection reaches the `entry` listener (R4, Q17) | G.0 |
| The router admits the tenant's internal `Route` when the old one is deleted, and how long the host has no backend (R5) | G.0 |
| The tier expression never fails, with odd tokens | G.19 |
