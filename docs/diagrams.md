# Diagrams

C4 views (context → container) and the main flows. Mermaid.

## C4 — Context

```mermaid
flowchart TB
  PT([Platform / API-platform team<br/>owns the Template, the mesh,<br/>the rate-limit service, the IdP])
  DEV([API team member<br/>commits one TemplateInstance])
  CON([API consumer<br/>a machine client with a token])
  AUD([Security and audit<br/>does every API check tokens?])
  GITT[(Team Git repo<br/>TemplateInstance)]
  GITP[(platform-tenants Git repo<br/>Tenant: namespaces, mesh labels)]
  subgraph SYS[API gateway extension for the Multi-Tenant Operator]
    EXT[Publishes the api-gateway Template;<br/>renders the backend side;<br/>keeps security un-switchable]
  end
  MTO[Multi-Tenant Operator<br/>Tenant: namespaces, mesh/waypoint labels]
  OSSM[OpenShift Service Mesh 3<br/>Gateway API, RequestAuth, AuthZ, mTLS]
  IDP[Identity provider<br/>issues consumer tokens]
  RL[Shared rate-limit service]
  DEV -->|TemplateInstance| GITT
  PT -->|Tenant + mesh labels| GITP
  GITT -->|GitOps| OSSM
  GITP -->|GitOps| MTO
  PT -->|publishes the Template| EXT
  MTO -->|Tenant, namespaces| EXT
  EXT -->|Gateway, policies, backend side| OSSM
  CON -->|token + request| OSSM
  OSSM -->|per request| RL
  OSSM -->|validate token| IDP
  AUD -->|one Template, no per-gateway exceptions| EXT
```

The extension renders objects; it runs no gateway, rate-limit service or
identity provider of its own (ADR-0001). Security configuration lives in the
Template, not in the team's `TemplateInstance` (ADR-0002).

## C4 — Container

```mermaid
flowchart LR
  GITT[(Team Git repo<br/>TemplateInstance)]
  GITP[(platform-tenants<br/>Tenant)]
  subgraph Cluster[OpenShift cluster]
    GO[GitOps<br/>Argo CD]
    MTO[Multi-Tenant Operator]
    subgraph TOP[Template Operator v2]
      TMPL[[api-gateway Template<br/>+ api-backend Template<br/>published by bootstrap]]
      TI[TemplateInstance<br/>team-authored, per gateway]
      TGI[TemplateGroupInstance<br/>platform, per app namespace]
    end
    BOOT[[api-gateway-mto-bootstrap<br/>Helm, installed once:<br/>Templates, guardrail, parent TI]]
    subgraph GNS[gateway namespace: orders-gateway-test]
      GW[Gateway class istio<br/>+ Deployment/Service]
      RA[RequestAuthentication]
      AP[AuthorizationPolicy consumer]
      HR[HTTPRoute + Route]
      EF[rate-limit + strip hook]
    end
    subgraph ANS[app namespace: team-a-test]
      RG[ReferenceGrant]
      GO2[AuthorizationPolicy gw-only]
      WP[Gateway class istio-waypoint]
      BE[orders-api backend]
    end
    IDP[Identity provider]
    RL[Rate-limit service]
  end
  GITT --> GO --> TI
  GITP --> GO --> MTO --> ANS
  BOOT --> TMPL & TGI
  TI -->|renders| GNS
  TGI -->|renders| RG & GO2 & WP
  GW -.->|validate| IDP
  GW -.->|per request| RL
  GW -->|mTLS via waypoint| WP --> BE
```

## Sequence — a request through the gateway

```mermaid
sequenceDiagram
  autonumber
  participant C as Consumer (machine client)
  participant IDP as Identity provider
  participant R as OpenShift Route
  participant GW as Gateway (Envoy)
  participant RL as Rate-limit service
  participant WP as Waypoint (team-a-test)
  participant BE as orders-api
  C->>IDP: client-credentials grant
  IDP-->>C: access token (claim allowed_apis)
  C->>R: HTTPS GET /v2/orders/42 + token
  R->>GW: re-encrypt to the gateway
  GW->>GW: validate token (issuer, JWKS, audience)
  GW->>GW: require claim allowed_apis matches api-orders-consumer-*
  GW->>GW: strip caller x-sub/x-roles; set its own from the token
  GW->>RL: under the medium tier limit?
  RL-->>GW: yes
  GW->>GW: rewrite /v2 -> /v1
  GW->>WP: forward over mTLS (HBONE)
  WP->>BE: gw-only allows the gateway identity
  BE-->>C: 200
  Note over GW: no token -> 403; wrong-API token -> 403; invalid -> 401; flood -> 429
```

## Sequence — a team requests a gateway

```mermaid
sequenceDiagram
  autonumber
  participant D as API team member (ola)
  participant G as Team Git repo
  participant GO as GitOps
  participant T as Template Operator v2
  participant API as Kubernetes API + admission
  D->>G: commit TemplateInstance (apiName, backend, host, tier)
  G->>GO: sync
  GO->>T: apply TemplateInstance in orders-gateway-test
  T->>API: render Gateway, RequestAuth, AuthZ, routes, hooks (as the platform identity)
  API-->>T: admitted (platform identity; a team-written Gateway would be refused)
  Note over T: security is in the Template; ola set only API-shaped parameters
  Note over T: the backend side (gw-only, waypoint) comes from the platform TemplateGroupInstance
```

## Sequence — a team tries to route around the Template

```mermaid
sequenceDiagram
  autonumber
  participant O as ola (team-a owner)
  participant API as Kubernetes API + admission
  participant T as Template Operator v2
  O->>API: create a raw Gateway with no token check in orders-gateway-test
  API-->>O: refused — only the platform identity may create a Gateway (ADR-0006)
  O->>API: edit the rendered AuthorizationPolicy to drop the token requirement
  API-->>O: the edit is reverted (sync.mode: revert); and admission refuses the edit
  Note over O,T: the Template is the only way to an ingress gateway
```
