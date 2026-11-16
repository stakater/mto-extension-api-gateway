# Concepts

A plain-language primer. One running example throughout: one OpenShift 4.20
cluster with Red Hat OpenShift Service Mesh 3.4 in ambient mode, a shared
Envoy rate-limit service in `api-gateway-system`, and Red Hat build of Keycloak
as the identity provider (realm `apis`). Tenant **`team-a`** owns the API
`orders` in two environments. Its `Tenant` lives in a Git repo,
`platform-tenants`, applied by Argo CD. For the `test` environment it has a
gateway namespace **`orders-gateway-test`** and an application namespace
**`team-a-test`**, where the service **`orders-api`** listens on port 80.

## The terms

| Term | Where it lives | What it is |
|---|---|---|
| **Tenant** | Multi-Tenant Operator | The unit of ownership: a team and its namespaces. Here it also bounds the gateway's hostname and consumer scope. |
| **API gateway** | a gateway namespace | One Envoy proxy (a Gateway API `Gateway`, class `istio`) for **one API in one environment**. It validates the token, authorizes the caller, rate-limits, strips caller identity headers, and forwards to the backend over mTLS. |
| **Gateway namespace** | the Tenant | `<api>-gateway-<env>`, e.g. `orders-gateway-test`. Holds the gateway and its routing and security objects. |
| **Application namespace** | the Tenant | `<team>-<env>`, e.g. `team-a-test`. Holds the backend service, a `gw-only` rule, a `ReferenceGrant`, and the waypoint. |
| **Consumer** | the identity provider | A machine client (client-credentials) that calls an API. Its access token carries a claim (`allowed_apis`) listing the APIs it may use. Not a human, not a tenant member. |
| **Consumer scope** | the gateway's policy | The value the token's claim must match to use this gateway, **derived** from the API name: `api-<apiName>-consumer-*`. Never free text. |
| **Tier** | the shared rate-limit service | A request-rate class (e.g. low/medium/high) applied to callers of the gateway. |
| **Template** | Stakater Template Operator v2 | `api-gateway`: the platform-owned package the team instantiates. Holds the gateway chart; exposes only API-shaped parameters; keeps security inside. |
| **TemplateInstance** | the team's Git repo | The team's request for a gateway: `template: api-gateway` plus a few parameters. Synced by the team's Argo CD app into the gateway namespace. |
| **TemplateGroupInstance** | the platform | Renders the backend-side objects (`ReferenceGrant`, `gw-only`, waypoint) into a tenant's application namespaces. |
| **Waypoint** | the application namespace | An ambient L7 proxy (a `Gateway`, class `istio-waypoint`) for the namespace; the gateway reaches the backend through it over mTLS. One per application namespace. |
| **gw-only** | the application namespace | An `AuthorizationPolicy` admitting only the gateway's identity to the backend; every other caller is refused. |

Two words that are easy to confuse:

- **Gateway** here is always the **north-south ingress** gateway or the
  waypoint (Gateway API). The service-mesh extension's **tenant boundary** is
  east-west; the Multi-Tenant Operator's telemetry **gateways** (Loki, Mimir)
  are something else again — this repo says "telemetry gateway" for those.
- **Consumer** here is a **machine client of an API**, never a tenant member or
  a human. Human access (who may edit the `TemplateInstance`) is ordinary
  Tenant RBAC through the group contract (`tenant-<tenant>-<tier>s`).

## The example, end to end

1. The platform installs OpenShift Service Mesh 3.4 (ambient), the shared
   rate-limit service in `api-gateway-system`, the identity provider realm
   `apis`, and the Multi-Tenant Operator with Template Operator v2. Then it
   installs this extension: the `api-gateway` Template and the backend-side
   Template are published once (ADR-0001).
1. **The Tenant.** The `team-a` `Tenant` in `platform-tenants` lists its
   namespaces — `orders-gateway-test` and `team-a-test` — and, in
   `namespaces.metadata`, sets the mesh labels: `istio.io/dataplane-mode:
   ambient` on both, and `istio.io/use-waypoint` on `team-a-test`. Its
   `accessControl` names only the contract groups. The Multi-Tenant Operator
   creates the namespaces and stamps the labels (ADR-0005).
1. **The consumer.** The platform creates a client `orders-consumer` in the
   `apis` realm with the role that puts `api-orders-consumer-read` in the
   token's `allowed_apis` claim (a prerequisite; v1 doesn't do this, ADR-0009).
1. **The gateway request.** The `team-a` developer commits one
   `TemplateInstance` in the team repo:

   ```yaml
   apiVersion: templates.v2.stakater.com/v1alpha1
   kind: TemplateInstance
   metadata:
     name: orders-gateway
     namespace: orders-gateway-test
   spec:
     template: api-gateway
     parameters:
       apiName: orders            # derives the consumer scope api-orders-consumer-*
       backendNamespace: team-a-test
       backendService: orders-api
       backendPort: "80"
       backendPath: /v1
       exposedPath: /v2
       externalHost: api-team-a-test.apps.example.com
       tier: medium
   ```

   There is no `auth.enabled`, no `allowedApis`, no `allowGatewayAccessOnly`:
   those are not parameters (ADR-0002, ADR-0003).
1. **The render.** Template Operator renders the gateway side into
   `orders-gateway-test`: the `Gateway`, the `Route` and `HTTPRoute`, a
   `RequestAuthentication` (issuer `apis`, the realm's JWKS, the audience), an
   `AuthorizationPolicy` requiring a valid token whose `allowed_apis` matches
   `api-orders-consumer-*` and whose host is `api-team-a-test.apps.example.com`,
   the header-strip and rate-limit hooks, and telemetry. The backend-side
   `TemplateGroupInstance` renders into `team-a-test`: a `ReferenceGrant`, the
   `gw-only` `AuthorizationPolicy`, and the waypoint.
1. **A good call.** `orders-consumer` gets a token, calls
   `https://api-team-a-test.apps.example.com/v2/orders/42`. The gateway
   validates the token, checks the claim, strips any `x-sub`/`x-roles` the
   caller set, sets its own from the token, rewrites `/v2` → `/v1`, rate-limits,
   and forwards to `orders-api` over mTLS. The backend's `gw-only` rule lets the
   gateway in. `200`.
1. **Bad calls.** No token → `403`. A token whose claim is for another API →
   `403`. An invalid token → `401`. A flood → `429` after the `medium` tier's
   limit. A pod elsewhere in the cluster calling `orders-api` directly →
   refused by `gw-only`.
1. **A team tries to cut a corner.** The `team-a` developer hand-writes a raw
   `Gateway` with no token check in `orders-gateway-test`. Admission refuses it:
   only the platform identity renders gateways; the Template is the only way
   (ADR-0006).
1. **An upgrade.** The platform bumps the `api-gateway` Template to a new chart
   version. At the next render, `team-a`'s gateway — and every other gateway in
   the cluster — is on it. The team does nothing.

## What the platform does, and what the extension does

| The platform / mesh does | The extension does |
|---|---|
| runs the mesh, gives each pod an identity, enforces mTLS | renders the gateway, its token check and its `gw-only` backend rule from a `TemplateInstance` |
| runs the shared rate-limit service and the identity provider | wires each gateway to the rate-limit service and the issuer; derives the consumer scope from the API name |
| labels tenant namespaces for the mesh and the waypoint (from the `Tenant`) | renders the backend-side `ReferenceGrant`, `gw-only` and waypoint into the application namespace |
| aggregates `admin`/`edit` for tenants | keeps security out of the team's hands (it's in the Template) and refuses a hand-written gateway (ADR-0006) |
| upgrades nothing by itself | puts every gateway on one Template version at the next render |
