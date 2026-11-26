# Concepts

A plain-language primer. One running example throughout: tenant **`team-a`**,
namespaces **`team-a-dev`** and **`team-a-test`**, API **`orders`** (Service
`orders` in `team-a-dev`, served at `/orders/v1`, published at `/orders/v2`),
caller **`shop`** (an RHBK client allowed to use `orders`, tier `silver`).

## The terms

| Term | Where it lives | What it is |
|---|---|---|
| **Tenant** | Multi-Tenant Operator | The unit of ownership: a team and its namespaces. Every tenant namespace carries the label `stakater.com/tenant=<tenant>`. |
| **Gateway request** | a `TemplateInstance` of the `api-gateway` Template, in a tenant namespace | How a team asks for its tenant's gateway: `api-gateway` in `team-a-dev`. It has no parameters. A tenant has one gateway: the oldest request wins, and every other request gets a status that says why. |
| **Tenant gateway** | Gateway API `Gateway`, in the request's namespace | The tenant's one Envoy gateway, always named `mto-api-gateway`, in the request's namespace (`team-a-dev`). Service Mesh deploys its pods there (`mto-api-gateway-istio`). Only routes from the tenant's own namespaces attach to it. The team can't edit or delete it. |
| **Platform namespace** | Kubernetes | `mto-api-gateways`: the bootstrap chart, its parent, and the `api-gateway` and `api` Templates that teams instantiate. Tenants have no access to it. |
| **Tenant hostnames** | the tenant gateway's listener | The host names the tenant gateway serves: `*.team-a.apis.example.com` by default, plus any extra names the platform grants, plus path prefixes the platform grants on a shared host such as `front.example.com` (ADR-0009). An API can use no other host or prefix. |
| **API** | a `TemplateInstance` of the `api` Template, in the backend's namespace | One published API: its host, path, optional rewrite or exact operations, and backend `Service` and port, or a host outside the cluster (ADR-0014). Created by the API team. It renders the API's `HTTPRoute` to the tenant gateway; the team never writes a route (ADR-0005). |
| **API name** | the `api` instance's name | A DNS label, unique in the tenant: `orders`. It names the API in the allowed-API rule and in every object the extension renders for it. |
| **Security baseline** | the token floor and default deny (once per cluster), and the tenant's `RequestAuthentication`, header filter and rate limit filter | The checks every request passes on the tenant gateway: a valid token from one of the API's issuers, caller headers replaced from the token, the rate limit tier. Set by the platform; a route can't weaken them (ADR-0004). |
| **Allowed-API rule** | Istio `AuthorizationPolicy` `ALLOW` per API, in the gateway's namespace | The caller's token must name this API in its allowed-APIs claim: `api.team-a.orders`. Checked on the API's host and path, so several APIs can share a host. Derived from the tenant and the API name, never typed by hand. |
| **Allowed-APIs claim** | the caller's token (RHBK) | A token claim that lists the APIs a caller may use, for example `allowed_apis: [api.team-a.orders]`. The platform names the claim. |
| **Tier** | a role in the caller's token, one per API; platform values | `bronze`, `silver`, `gold`: the caller's request rate on one API, from its role `api.team-a.orders.silver`. The platform sets the rates; the highest role wins; no role gives the lowest. |
| **Backend lock** | Istio `AuthorizationPolicy` on the backend Service, enforced by a waypoint in the API's namespace | "Only the tenant gateway may call this backend through its Service", except health and metrics paths, as today. On by default; the team can turn it off for its API (ADR-0007). |
| **Rate limit service** | the platform namespace | Counts calls per tenant, API, caller and tier for every tenant gateway, with Redis, so each API has its own limit. Deployed by the bootstrap chart; tiers are platform values. |
| **Template Operator** | Stakater | Renders the team's gateway request, each `api` instance, and one policy child per tenant. |
| **Bootstrap chart** | this repo | Installed once per cluster. Publishes the `api-gateway` and `api` Templates, renders the token floor, the default deny, the rate limit service and the admission policy, and fans out one policy child per tenant. |
| **Policy child** | a `TemplateInstance` per tenant, in the platform namespace | Renders the tenant gateway's `RequestAuthentication`, filters and telemetry, and, for every API's route, its allowed-API rule and backend lock (ADR-0013). Never created by hand. |
| **Team settings** | annotations on the gateway request | Claim headers, correlation ID, access log, trace headers; validated by the policy child (ADR-0012). |

Three words that are easy to confuse:

- **Gateway** always means a Gateway API `Gateway` and the Envoy pods behind
  it. When this repo means Istio's older `networking.istio.io` `Gateway`, it
  says "Istio `Gateway` resource". The extension never renders one.
- **Route** means a Gateway API `HTTPRoute`. An OpenShift `Route` is always
  written "OpenShift `Route`".
- **Policy** means an Istio `RequestAuthentication` or `AuthorizationPolicy`.
  A platform `EnvoyFilter` is called a filter.

## The example, end to end

1. The platform installs the bootstrap chart once, in `mto-api-gateways`. It
   publishes the `api-gateway` and `api` Templates.
1. Team `team-a` asks for its gateway, once, in the namespace where it should
   run:

    ```yaml
    apiVersion: templates.v2.stakater.com/v2alpha1
    kind: TemplateInstance
    metadata:
      name: api-gateway
      namespace: team-a-dev
    spec:
      templateRef:
        name: api-gateway
        namespace: mto-api-gateways
    ```

   Template Operator renders, in `team-a-dev`: Gateway `mto-api-gateway` with the
   listener `*.team-a.apis.example.com` and the status ConfigMap
   `mto-api-gateway-status.api-gateway`; the tenant's policy child renders the token check and
   the platform's filters. Service Mesh deploys the
   gateway pods with an autoscaler.
1. The API team creates one `TemplateInstance` of `api` in `team-a-dev`, the
   backend's namespace:

    ```yaml
    apiVersion: templates.v2.stakater.com/v2alpha1
    kind: TemplateInstance
    metadata:
      name: orders                  # the API name
      namespace: team-a-dev
    spec:
      templateRef:
        name: api
        namespace: mto-api-gateways
      parameters:
        - { name: host,    value: orders.team-a.apis.example.com }
        - { name: path,    value: /orders/v2 }
        - { name: rewrite, value: /orders/v1 }
        - { name: service, value: orders }
        - { name: port,    value: "80" }
    ```

   Template Operator renders, in `team-a-dev`, the `HTTPRoute` `api.orders`
   to the tenant gateway and the status ConfigMap `api.orders`.
1. The policy child renders, in `team-a-dev`: the allowed-API rule
   `api.team-a.orders` for the host `orders.team-a.apis.example.com` and the
   path `/orders/v2`, and the backend lock on Service `orders`. A second API
   can use the same host with another path, for example `/payments/v1`.
1. `shop` gets a token from RHBK with `allowed_apis:
   [api.team-a.orders.silver]` (access to `orders`, tier silver), and calls
   `https://orders.team-a.apis.example.com/orders/v2`.
1. The gateway checks the token, checks the allowed-API rule, replaces any
   `x-sub` and `x-roles` the caller sent with values from the token, counts the
   call against `silver`, rewrites the path to `/orders/v1`, and calls
   `orders` over mesh mTLS. `orders` accepts the call because it comes from the
   tenant gateway's identity.
1. Without a token: `403`; with an invalid token: `401`. With a token for
   another API: `403`. Too fast: `429`.
   From another pod straight to `orders`: refused by the mesh. The request
   never reaches the application.

## Before and after

| | A gateway per API (today) | This extension |
|---|---|---|
| Who owns the gateway | each API team, in its own chart copy | the platform defines it; the team asks for it with one `TemplateInstance` |
| How many gateways | one per API per environment | one per tenant that asked |
| Replicas | fixed | autoscaled |
| Token check, header handling | Istio policies + hand-written `EnvoyFilter`s per team | Istio policies + platform-owned, tested filters, no Lua |
| Rate limit | `EnvoyFilter` with Lua + a rate limit service per platform | a platform-owned filter + the rate limit service from the bootstrap chart |
| Allowed-API rule | free text in values | derived from tenant and API name |
| What the team writes | a full values file and an Argo CD app | one parameterless `TemplateInstance` per tenant; one `TemplateInstance` of `api` per API |
| Security switches | in the values file | none for the token check, the API rule or the headers; the rate limit and the backend lock per API, which the platform can lock per tenant |
| Upgrade | each team, by hand | the platform, once |
