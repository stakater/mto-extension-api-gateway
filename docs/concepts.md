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
| **Tenant gateway** | Gateway API `Gateway`, in the request's namespace | The tenant's one Envoy gateway, named like its request: `api-gateway` in `team-a-dev`. Service Mesh deploys its pods there (`api-gateway-istio`). Only routes from the tenant's own namespaces attach to it. The team can't edit or delete it. |
| **Platform namespace** | Kubernetes | `mto-api-gateways`: the bootstrap chart, its parent, and the `api-gateway` Template that teams instantiate. Tenants have no access to it. |
| **Tenant hostnames** | the tenant gateway's listener | The host names the tenant gateway serves: `*.team-a.apis.example.com` by default, plus any extra names the platform grants. A route for any other host doesn't attach. |
| **API** | `HTTPRoute` in a tenant namespace | One published API: an `HTTPRoute` with `parentRef` to the tenant gateway and the annotation `api-gateway.stakater.com/api: orders`. Written by the API team. |
| **API name** | the annotation | A DNS label, unique in the tenant: `orders`. It names the API in the allowed-API rule and in every object the extension renders for the route. |
| **Security baseline** | gateway-level `AuthPolicy` and `RateLimitPolicy`, as **overrides** | The checks every request passes on the tenant gateway: a valid token from the platform's issuer, caller headers replaced from the token, the rate limit tier. Set by the platform; a route can't weaken them. |
| **Allowed-API rule** | route-level `AuthPolicy` | The caller's token must name this API in its allowed-APIs claim: `api.team-a.orders`. Derived from the tenant and the API name, never typed by hand. |
| **Allowed-APIs claim** | the caller's token (RHBK) | A token claim that lists the APIs a caller may use, for example `allowed_apis: [api.team-a.orders]`. The platform names the claim. |
| **Tier** | a token claim, platform values | `bronze`, `silver`, `gold`: the caller's request rate on every API. The platform sets the rates. |
| **Backend lock** | Istio `AuthorizationPolicy` in the API's namespace | "Only the tenant gateway may call this backend." Rendered for every API. Another pod in the cluster is refused. |
| **Connectivity Link** | Red Hat product (upstream: Kuadrant) | Adds `AuthPolicy`, `RateLimitPolicy` and other policies to Gateway API. Runs Authorino (token checks) and Limitador (rate limits) for the cluster. |
| **Template Operator** | Stakater | Renders the per-tenant chart once per tenant. |
| **Bootstrap chart** | this repo | Installed once per cluster. Watches tenants and renders each tenant's gateway, its listener and its gateway-level policies. |
| **Per-tenant chart** | this repo | Pulled and rendered by Template Operator per tenant: the route-level policies and the backend lock for every annotated `HTTPRoute`. Never installed by hand. |

Three words that are easy to confuse:

- **Gateway** always means a Gateway API `Gateway` and the Envoy pods behind
  it. When this repo means Istio's older `networking.istio.io` `Gateway`, it
  says "Istio `Gateway` resource". The extension never renders one.
- **Route** means a Gateway API `HTTPRoute`. An OpenShift `Route` is always
  written "OpenShift `Route`".
- **Policy** means a Connectivity Link policy (`AuthPolicy`,
  `RateLimitPolicy`) unless it says Istio `AuthorizationPolicy`.

## The example, end to end

1. The platform installs the bootstrap chart once, in `mto-api-gateways`. It
   publishes the `api-gateway` Template.
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

   Template Operator renders, in `team-a-dev`: Gateway `api-gateway` with the
   listener `*.team-a.apis.example.com`, the gateway-level security baseline,
   and the status ConfigMap `api-gateway-status`. Service Mesh deploys the
   gateway pods with an autoscaler.
1. The API team writes one `HTTPRoute` in `team-a-dev`:

    ```yaml
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: orders
      namespace: team-a-dev
      annotations:
        api-gateway.stakater.com/api: orders
    spec:
      parentRefs:
        - name: api-gateway         # add namespace: when the route is elsewhere in the tenant
      hostnames: [dev.team-a.apis.example.com]
      rules:
        - matches:
            - path: { type: PathPrefix, value: /orders/v2 }
          filters:
            - type: URLRewrite
              urlRewrite:
                path: { type: ReplacePrefixMatch, replacePrefixMatch: /orders/v1 }
          backendRefs:
            - name: orders
              port: 80
    ```

1. Template Operator renders, in `team-a-dev`: the route-level `AuthPolicy`
   with the allowed-API rule `api.team-a.orders`, and the backend lock on
   Service `orders`.
1. `shop` gets a token from RHBK with `allowed_apis: [api.team-a.orders]` and
   `tier: silver`, and calls `https://dev.team-a.apis.example.com/orders/v2`.
1. The gateway checks the token, checks the allowed-API rule, replaces any
   `x-sub` and `x-roles` the caller sent with values from the token, counts the
   call against `silver`, rewrites the path to `/orders/v1`, and calls
   `orders` over mesh mTLS. `orders` accepts the call because it comes from the
   tenant gateway's identity.
1. Without a token: `401`. With a token for another API: `403`. Too fast: `429`.
   From another pod straight to `orders`: refused by the mesh. The request
   never reaches the application.

## Before and after

| | A gateway per API (today) | This extension |
|---|---|---|
| Who owns the gateway | each API team, in its own chart copy | the platform defines it; the team asks for it with one `TemplateInstance` |
| How many gateways | one per API per environment | one per tenant that asked |
| Replicas | fixed | autoscaled |
| Token check, header handling | Istio `RequestAuthentication` + `AuthorizationPolicy` + `EnvoyFilter` | Connectivity Link `AuthPolicy` |
| Rate limit | `EnvoyFilter` + an Envoy rate limit service | Connectivity Link `RateLimitPolicy` |
| Allowed-API rule | free text in values | derived from tenant and API name |
| What the team writes | a full values file and an Argo CD app | one parameterless `TemplateInstance` per tenant; one `HTTPRoute` with one annotation per API |
| Security switches | in the values file | none |
| Upgrade | each team, by hand | the platform, once |
