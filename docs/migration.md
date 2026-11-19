# Migration runbook: from per-API gateways to tenant gateways

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
| Backend namespace | joins the mesh, if it isn't in it yet (step 2.a) |
| Per-API gateway release | removed at the end (step 3.g) |
| Dashboards and alerts on the old gateway names | follow the new gateway's names |

## 1. Once per cluster (platform team)

1. **Install the bootstrap chart.** Template Operator v2 must be running.
1. **Set its values to match today's behaviour:**
    - `auth.issuers`: the identity provider that issues today's tokens, with
      `jwksUri` when its host is not reachable from the cluster;
      `defaultIssuers` names it (ADR-0004).
    - `rateLimit.tiers`: the same rates as today's shared rate limit
      configuration (for example gold 100, silver 50, bronze 10 per second);
      the failure mode as today (fail open, if that is today's choice).
    - `rateLimit.redis.*`: the platform's Redis.
    - `gateway.sharedHosts`: the shared front host, with each tenant's path
      prefixes (ADR-0009). Grant a prefix that is **shorter** than the paths of
      today's per-API routes, for example `/orders` for `/orders-v2/v1` (see
      step 3.e).
    - `migration.legacyRoles`: for each API that moves, its old role name,
      for example `team-a.orders: api-orders-consumer` (ADR-0006).
1. **Check the mesh and the router** (already so where gateways share a host
   today):
    - Istio's key reload interval is 3 minutes (design §10).
    - The router that serves the shared host has
      `routeAdmission.namespaceOwnership: InterNamespaceAllowed` (R2).

## 2. Once per tenant (the team, with the platform)

1. **Backend namespaces in the mesh.** The tenant's backend namespaces carry
   the ambient mesh label, set through the Multi-Tenant Operator `Tenant`
   (M5). The backend lock needs it (ADR-0007); a waypoint label from the old
   pattern is not needed. A backend that can't join the mesh can't move yet
   (G.17).
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

1. **Check its status:** `api-gateway-status` says `ok`, and the settings are
   listed as accepted in `api-gateway-apis`.

## 3. For each API

### 3.a Create the `api` instance from today's values

| Today's per-API values | `api` instance parameter |
|---|---|
| `gateway.hosts.external` (the shared host) | `host` |
| `gateway.pathPrefix` | `path` |
| `backend.internal.pathPrefix`, when different | `rewrite` |
| `backend.internal.service`, `.port` | `service`, `port` |
| `gateway.matches` (exact path and method) | `operations` |
| `rateLimit.enabled: false` | `rateLimit: "off"` |
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

Check `api.orders` says `ok`, and `api-gateway-apis` lists the API with no
conflict.

### 3.b Check the caller-facing details

| Check | How | If found |
|---|---|---|
| Tokens sent in the URL (`?access_token=`) | the old gateway's access log | the tenant gateway refuses them (M15): ask those callers to use the `Authorization` header first |
| Callers on the old internal host (`<gateway>-<namespace>.<router domain>`) | the router's access log | keep the API on its old gateway until G.18 gives the internal host |
| Headers the backend reads | ask the API team | AC-MIG-3 compares them through both gateways |

### 3.c Check the tiers

Today's tier lookup put every caller on the lowest tier when the API name
has a hyphen (M11). The tenant gateway reads the tier by exact text, so those
callers get the tier their role names. **Before such an API moves, its owner
confirms the backend can take the higher rates.** If it can't, the API
waits.

### 3.d Test through the new gateway

Before the switch, call the API through the tenant gateway with real tokens,
one per tier, and compare with the old gateway: status codes, the tier limit,
and the headers at the backend (AC-MIG-2, AC-MIG-3).

### 3.e Switch: one change

Remove the old gateway's OpenShift `Route` for the API's path (in the old
release: no external host, or the route turned off). The tenant's `Route` for
the shorter prefix now takes the path.

Why this is one change: while the old `Route` exists, the router prefers its
longer path (R1), so the old gateway keeps the traffic. **G.0 confirms that
the router prefers the longest path before any production move.**

### 3.f Measure, and move back if needed

For the agreed period, compare the error rate, the p95 latency, and the
count of `401`, `403` and `429` on the path with the period before the
switch (AC-MIG-4). To move back, put the old `Route` back: its longer path
takes the traffic again at once (AC-MIG-1).

### 3.g Clean up

After the agreed period, uninstall the per-API gateway release: its Lua
filter, its policies, its pods and its `Route`s. Move dashboards and alerts
to the tenant gateway's names.

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
| The tier expression never fails, with odd tokens | G.19 |
