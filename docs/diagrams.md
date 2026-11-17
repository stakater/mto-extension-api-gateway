# Diagrams

Mermaid diagrams of the design in `design.md`. Running example: tenant
`team-a`, API `orders` in `team-a-dev`, caller `shop`.

## C4 — Context

```mermaid
flowchart LR
  caller([External caller<br/>e.g. shop])
  idp[RHBK<br/>issues tokens with<br/>allowed_apis and tier]
  platform([Platform team])
  team([API team])
  subgraph cluster[OpenShift cluster]
    ext[API Gateway extension<br/>charts rendered by<br/>Template Operator]
    gw[Tenant gateways<br/>Service Mesh + Connectivity Link]
    apps[Tenant applications]
  end
  caller -->|1. get token| idp
  caller -->|2. HTTPS + token| gw
  gw -->|3. mTLS, checked request| apps
  platform -->|installs once, sets baseline| ext
  team -->|writes HTTPRoute + annotation| ext
  ext -->|renders gateways and policies| gw
```

## C4 — Container

```mermaid
flowchart TB
  subgraph platformns[mto-api-gateways — platform only]
    parent[parent TemplateInstance<br/>reads Tenants, Namespaces, requests]
    tpl[Template api-gateway<br/>tenantOf, owner, settings: all disableOverride<br/>sync strict]
    parent -->|publishes| tpl
  end
  subgraph tenantns[team-a-dev — a tenant namespace]
    req[TemplateInstance api-gateway<br/>the team's request, no parameters]
    gwA[Gateway api-gateway<br/>listener *.team-a.apis.example.com<br/>routes from stakater.com/tenant=team-a]
    podsA[api-gateway-istio pods<br/>autoscaled]
    baseA[AuthPolicy api-gateway-baseline<br/>overrides: JWT, tenant floor, headers]
    denyA[AuthPolicy api-gateway-deny-tenant<br/>defaults: refuse, one per listener]
    floorA[RequestAuthentication + DENY<br/>api-gateway-jwt-floor: no token, no entry]
    rlA[RateLimitPolicy api-gateway-tiers<br/>overrides: tiers per caller]
    route[HTTPRoute orders<br/>annotation api: orders]
    apA[AuthPolicy api.orders<br/>allowed-API rule api.team-a.orders]
    lock[AuthorizationPolicy api.orders.orders<br/>DENY all but api-gateway-istio on the API port]
    svc[Service orders]
    req -.->|instance of| tpl
    req -->|renders, strict| gwA
    gwA --> podsA
    baseA -.->|targets| gwA
    denyA -.->|targets| gwA
    rlA -.->|targets| gwA
    floorA -.->|targets| gwA
    route -->|parentRef| gwA
    route -->|backendRef| svc
    apA -.->|targets| route
    lock -.->|guards pods of| svc
  end
  subgraph shared[Cluster-wide, prerequisites]
    mesh[Service Mesh 3<br/>istiod, ztunnel]
    cl[Connectivity Link<br/>Authorino, Limitador]
    top[Template Operator v2]
  end
  top -->|renders| platformns
  top -->|renders| tenantns
  podsA -->|mTLS via ztunnel| svc
  podsA -->|auth and rate-limit calls| cl
```

## Request flow

```mermaid
sequenceDiagram
  autonumber
  participant C as Caller (shop)
  participant K as RHBK
  participant E as Entry point (OpenShift Route)
  participant G as Gateway api-gateway in team-a-dev (Envoy)
  participant A as Authorino (AuthPolicy)
  participant L as Limitador (RateLimitPolicy)
  participant Z as ztunnel
  participant B as Backend orders
  C->>K: client credentials
  K-->>C: JWT (azp=shop, allowed_apis=[api.team-a.orders], tier=silver)
  C->>E: GET dev.team-a.apis.example.com/orders/v2 + token
  E->>G: re-encrypt
  Note over G: Istio token floor: no valid token from the issuer, refused
  G->>A: check request
  A-->>G: 401 if token missing or invalid
  A-->>G: 403 if no api.team-a.* value (tenant floor)
  A-->>G: 403 if no api.team-a.orders (route rule)
  A-->>G: OK + set x-sub=shop, x-roles=api.team-a.orders
  G->>L: count shop against silver
  L-->>G: 429 if over the limit
  G->>Z: /orders/v1 with x-sub, x-roles
  Z->>B: mTLS from api-gateway-istio identity
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
  T->>T: parent publishes Template api-gateway
  P->>M: create Tenant team-a (namespaces, mesh labels)
  M->>M: label namespaces stakater.com/tenant=team-a
  T->>T: parent adds team-a's namespaces to tenantOf
  D->>D: create TemplateInstance api-gateway in team-a-dev (no parameters)
  T->>T: parent sees the request: owner of team-a = team-a-dev/api-gateway
  T->>D: Gateway api-gateway + settings + baseline policies + status ok (strict)
  S->>S: deploy api-gateway-istio with autoscaler
  D->>D: a second request in team-a-test gets status refused, naming the owner
  D->>D: write HTTPRoute orders + annotation api: orders
  T->>T: per-tenant chart sees the annotated route (G.3)
  T->>D: AuthPolicy + backend lock (only if every backend can be locked)
  Note over D: shop gets 200, others 401, 403 or 429
```

## Offboard

```mermaid
sequenceDiagram
  autonumber
  participant D as API team
  participant P as Platform
  participant T as Template Operator
  D->>D: delete HTTPRoute orders
  T->>T: child no longer lists orders
  T->>D: delete AuthPolicy api.orders and backend lock api.orders.orders
  D->>D: delete TemplateInstance api-gateway (or the platform deletes Tenant team-a)
  T->>D: delete Gateway api-gateway, its policies and its settings
  Note over T: with the tenant gone, tenantOf drops its namespaces, so no request of it renders a gateway
  Note over T: objects of other tenants are never touched (ownership by provenance, T4)
```

## The gaps this design closes

```mermaid
flowchart LR
  subgraph before[A gateway per API, values per team]
    v1[values: auth.enabled=false] --> open1[API served without a token]
    v2[allowedApis: api-*] --> open2[any caller of any API gets in]
    ef[EnvoyFilter strip] -->|Istio upgrade changes config| open3[caller headers reach the app, no error]
    pod[pod in the cluster] --> open4[backend called directly]
  end
  subgraph after[This extension]
    a1[no switch: baseline is an override] --> c1[401]
    a2[rule derived: api.tenant.api, closed] --> c2[403]
    a3[AuthPolicy sets headers from the token] --> c3[app sees token values only]
    a4[backend lock on the mesh identity] --> c4[refused]
  end
```
