# Diagrams

Mermaid diagrams of the design in `design.md`. Running example: tenant
`team-a`, API `orders` in `team-a-dev` on `orders.team-a.apis.example.com`,
caller `shop`.

## C4 — Context

```mermaid
flowchart LR
  caller([External caller<br/>e.g. shop])
  idp[RHBK<br/>issues tokens with<br/>azp, allowed_apis and tier]
  platform([Platform team])
  team([API team])
  subgraph cluster[OpenShift cluster]
    ext[API Gateway extension<br/>one chart, rendered by<br/>Template Operator]
    gw[Tenant gateways<br/>Service Mesh, Istio policies,<br/>platform filters]
    rl[Rate limit service<br/>+ Redis]
    apps[Tenant applications]
  end
  caller -->|1. get token| idp
  caller -->|2. HTTPS + token| gw
  gw -->|3. count the call| rl
  gw -->|4. mTLS, checked request| apps
  platform -->|installs once, sets baseline| ext
  team -->|requests a gateway, one TemplateInstance per API| ext
  ext -->|renders gateways and policies| gw
```

## C4 — Container

```mermaid
flowchart TB
  subgraph root[istio-system — Istio root namespace]
    floor[AuthorizationPolicy token-floor<br/>DENY without a valid platform token]
    deny[AuthorizationPolicy default-deny<br/>ALLOW with no rules]
  end
  subgraph platformns[mto-api-gateways — platform only]
    parent[parent TemplateInstance<br/>reads Tenants, Namespaces, requests]
    tpl[Template api-gateway<br/>tenantOf, owner, settings: all disableOverride]
    apitpl[Template api<br/>the same platform values, plus hostnames]
    child[child TemplateInstance per tenant<br/>api-gateway-policy-team-a]
    rl[ratelimit + tier config]
    parent -->|publishes| tpl
    parent -->|publishes| apitpl
    parent -->|emits| child
  end
  subgraph tenantns[team-a-dev — a tenant namespace]
    req[TemplateInstance api-gateway<br/>the team's request, knob annotations]
    gwA[Gateway api-gateway<br/>*.team-a.apis.example.com, ClusterIP<br/>routes from stakater.com/tenant=team-a]
    podsA[api-gateway-istio pods<br/>autoscaled, gateway label]
    ra[RequestAuthentication api-gateway-jwt<br/>issuer, audience, claim headers]
    ef[EnvoyFilters: strip-headers,<br/>ratelimit, correlation-id]
    allow[AuthorizationPolicy api.orders<br/>ALLOW host orders.team-a…, path /orders/v2, api.team-a.orders]
    apiti[TemplateInstance orders<br/>of api: host, path, backend]
    route[HTTPRoute api.orders<br/>annotation api: orders]
    lock[AuthorizationPolicy api.orders.orders<br/>DENY all but api-gateway-istio on the API port]
    svc[Service orders]
    req -.->|instance of| tpl
    req -->|renders, strict| gwA
    gwA --> podsA
    child -->|renders, strict| ra
    child --> ef
    child --> allow
    child --> lock
    apiti -.->|instance of| apitpl
    apiti -->|renders, strict| route
    route -->|parentRef| gwA
    route -->|backendRef| svc
    lock -.->|guards pods of| svc
  end
  floor -.->|selects the gateway label| podsA
  deny -.->|selects the gateway label| podsA
  podsA -->|mTLS via ztunnel| svc
  podsA -->|gRPC| rl
```

## Request flow

```mermaid
sequenceDiagram
  autonumber
  participant C as Caller (shop)
  participant K as RHBK
  participant E as Entry point
  participant G as Gateway api-gateway (Envoy)
  participant R as Rate limit service
  participant Z as ztunnel
  participant B as Backend orders
  C->>K: client credentials
  K-->>C: JWT (azp=shop, allowed_apis=[api.team-a.orders.silver])
  C->>E: GET orders.team-a.apis.example.com/orders/v2 + token
  E->>G: TLS to the tenant gateway
  Note over G: remove the caller's x-sub, x-roles and team headers
  Note over G: token check: invalid → 401
  Note over G: token floor (root namespace): no valid token → 403
  Note over G: API rule: host orders.team-a…, api.team-a.orders, azp present, else 403
  Note over G: set x-sub=shop, x-roles from the token
  G->>R: count team-a / silver / shop
  R-->>G: 429 if over the limit
  G->>Z: /orders/v1 with x-sub, x-roles
  Z->>B: mTLS from the api-gateway-istio identity
  Note over Z,B: backend lock (DENY): any other identity, or none, is refused
  B-->>C: 200
```

## Request a gateway, publish an API

```mermaid
sequenceDiagram
  autonumber
  participant P as Platform
  participant M as Multi-Tenant Operator
  participant T as Template Operator
  participant S as Service Mesh
  participant D as Team team-a
  P->>T: install the bootstrap chart once (mto-api-gateways)
  T->>T: root-namespace floor and default deny; parent publishes api-gateway
  P->>M: create Tenant team-a (namespaces, mesh labels)
  M->>M: label namespaces stakater.com/tenant=team-a
  T->>T: parent adds team-a's namespaces to tenantOf
  D->>D: create TemplateInstance api-gateway in team-a-dev (no parameters)
  T->>T: parent: owner of team-a = team-a-dev/api-gateway; emits team-a's child
  T->>D: Gateway api-gateway + settings + status ok (strict)
  T->>D: child: RequestAuthentication, platform filters
  S->>S: deploy api-gateway-istio with autoscaler
  D->>D: a second request in team-a-test gets status refused, naming the owner
  D->>D: create TemplateInstance orders of api: host orders.team-a…, path /orders/v2, Service orders
  T->>D: HTTPRoute api.orders + status api.orders (strict)
  T->>D: child: ALLOW api.orders on host + path, and backend lock (only if no other API's path overlaps and every backend can be locked)
  Note over D: shop gets 200, others 401, 403 or 429
```

## Offboard

```mermaid
sequenceDiagram
  autonumber
  participant D as API team
  participant P as Platform
  participant T as Template Operator
  D->>D: delete TemplateInstance orders
  T->>D: delete HTTPRoute api.orders; the child no longer lists orders
  T->>D: delete ALLOW api.orders and backend lock api.orders.orders
  D->>D: delete TemplateInstance api-gateway (or the platform deletes Tenant team-a)
  T->>D: delete Gateway api-gateway and its settings; the parent removes team-a's child and its policies
  Note over T: with the tenant gone, tenantOf drops its namespaces, so no request of it renders a gateway
  Note over T: only objects with the ownership labels are deleted; a taken name must stop the render first (T4, issue #11)
```

## The gaps this design closes

```mermaid
flowchart LR
  subgraph before[A gateway per API, values per team]
    v1[values: auth.enabled=false] --> open1[API served without a token]
    v2[allowedApis: api-*] --> open2[any caller of any API gets in]
    ef[hand-written Lua tier lookup] -->|a name with a hyphen| open3[every caller on the lowest tier, no error]
    pod[pod in the cluster] --> open4[backend called directly]
  end
  subgraph after[This extension]
    a1[no switch: token floor in the root namespace] --> c1[403]
    a2[rule derived: api.tenant.api, closed] --> c2[403]
    a3[platform filter, no Lua, tested per upgrade] --> c3[tier from a plain claim]
    a4[backend lock on the mesh identity] --> c4[refused]
  end
```
