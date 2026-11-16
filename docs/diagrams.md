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
  subgraph platformns[Gateway namespace mto-api-gateways — platform only]
    gwA[Gateway team-a<br/>listener *.team-a.apis.example.com<br/>routes from stakater.com/tenant=team-a]
    podsA[team-a-istio pods<br/>autoscaled]
    baseA[AuthPolicy team-a-baseline<br/>overrides: JWT, tenant floor, headers]
    denyA[AuthPolicy team-a-deny-tenant<br/>defaults: refuse, one per listener]
    floorA[RequestAuthentication + DENY<br/>team-a-jwt-floor: no token, no entry]
    rlA[RateLimitPolicy team-a-tiers<br/>overrides: tiers per caller]
    gwA --> podsA
    baseA -.->|targets| gwA
    denyA -.->|targets| gwA
    rlA -.->|targets| gwA
    floorA -.->|targets| gwA
  end
  subgraph tenantns[Tenant namespace team-a-dev]
    route[HTTPRoute orders<br/>annotation api: orders]
    apA[AuthPolicy api-gateway-orders<br/>allowed-API rule api.team-a.orders]
    lock[AuthorizationPolicy api-gateway-orders-orders<br/>DENY all but team-a-istio on the API port]
    svc[Service orders]
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
  top -->|renders| apA
  top -->|renders| lock
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
  participant G as Gateway team-a (Envoy)
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
  Z->>B: mTLS from team-a-istio identity
  Note over Z,B: backend lock (DENY): any other identity, or none, is refused
  B-->>C: 200
```

## Onboard a tenant, publish an API

```mermaid
sequenceDiagram
  autonumber
  participant P as Platform
  participant M as Multi-Tenant Operator
  participant T as Template Operator
  participant S as Service Mesh
  participant D as API team
  P->>M: create Tenant team-a (namespaces, mesh labels)
  M->>M: label namespaces stakater.com/tenant=team-a
  T->>T: parent sees Tenant team-a
  T->>S: Gateway team-a + ConfigMap + baseline policies
  S->>S: deploy team-a-istio with autoscaler
  D->>D: write HTTPRoute orders + annotation api: orders
  T->>T: child sees annotated route in team-a-dev
  T->>D: AuthPolicy + backend lock (only if every backend can be locked) + status
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
  T->>D: delete AuthPolicy and backend lock api-gateway-orders
  P->>P: delete Tenant team-a
  T->>T: parent no longer lists team-a
  T->>P: delete Gateway team-a and its policies
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
