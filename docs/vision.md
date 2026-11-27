# Vision

## The problem

Platform teams on OpenShift publish many internal APIs to callers outside the
cluster. A common setup puts an **Envoy gateway in front of every API**: the
gateway checks the caller's token, checks that the caller may use this API,
limits the request rate, and forwards the request through the service mesh to
the application. Red Hat OpenShift Service Mesh 3 and the Kubernetes Gateway
API make each part of that possible.

The trouble starts when many teams do it. The pattern we see in practice:

| Today | What goes wrong |
|---|---|
| **A gateway chart copied into every team's repo** | A fix in the base chart is copied by hand. Versions drift between teams. |
| **Every team edits the full values file** | Token check, "only the gateway may call the backend" and rate limit are plain switches. One wrong value turns a security part off, and nothing checks it. |
| **The allowed-API rule is free text** | Nothing stops `api-*` or `*`. |
| **Header handling and rate limits are `EnvoyFilter` patches** | An `EnvoyFilter` patches the Envoy configuration that Istio generates. An Istio upgrade can break it without an error. Red Hat does not support it as a production feature. |
| **One gateway per API, per environment, at a fixed replica count** | A team with two APIs and three environments runs six gateways. Each runs its replicas all the time, also when nobody calls the API. |
| **Mesh labels, identity-provider roles and gateway values have three owners** | A gateway deploys fine while a namespace label is missing, and nobody owns the whole request. |

The Multi-Tenant Operator already knows which team owns which namespaces. The
gateway layer doesn't use that knowledge.

## The vision

> **One tenant definition, carried into the API gateway.** Every tenant can
> ask for its own gateway, with the platform's security baseline built in. The
> token check, the API rule and the header handling can't be switched off;
> only an API's own rate limit and backend lock can, and the platform can stop
> that. The team asks once, with one
> `TemplateInstance`, and publishes each API with one more `TemplateInstance`
> that names its host, path and backend. Token check and allowed-API check come from supported Istio
> policies; header handling and rate limits from a few platform-owned, tested
> filters, never from a team's own patches.

The product abstraction is **Tenant → API gateway**. Underneath, it is plain
Gateway API on OpenShift Service Mesh, with Istio policies and a few
platform-owned filters, rendered per tenant by Template Operator.

## Who it is for

| Persona | Job to be done | What they get |
|---|---|---|
| **Platform team** | run API gateways safely for many teams, and upgrade them without a project per team | one chart for all tenants; one install brings each new version, and each team moves when it is ready; a token check, API rule and header handling that no tenant can switch off |
| **API team** | publish an API without learning the gateway design | one `TemplateInstance` per API, with checked parameters; first-line troubleshooting with the familiar `401`, `403`, `429` |
| **Security and audit** | prove that every API checks the token and the caller's rights | the checks live in platform-owned policies that a route can't weaken; render checks fail on any wildcard or missing check |
| **Red Hat platform owners** | stay on supported products through upgrades | Gateway API and Service Mesh 3 as designed; only three platform-owned `EnvoyFilter`s, tested on every Service Mesh upgrade, and the support caveat stated up front |

## Value proposition

- **Secure by construction.** The token check, the header handling and the rate
  limit are set on the tenant's gateway by the platform. A team can't remove
  the token check, the API rule or the header handling; it can turn off only
  its own API's rate limit and backend lock, and the platform can stop that.
- **Self-service with one kind of object.** An API team creates a
  `TemplateInstance` for its gateway and one per API; the platform renders a
  standard Gateway API `HTTPRoute` from it. No chart copy, no values file, no
  gateway knowledge.
- **Tested through upgrades.** The auth path uses supported Istio APIs. The
  few filters left are the platform's, with no custom code, and the
  acceptance suite runs on every Service Mesh minor upgrade.
- **Fewer idle pods.** One gateway per tenant, scaled by load, instead of one
  per API at a fixed size.
- **One upgrade path for all.** The platform installs one chart; each team
  moves its tenant with one line, test cluster first.

## Principles

1. The platform owns the gateway and its security baseline. Tenants own their
   `api` instances.
1. Security settings are never parameters. A tenant can't turn the token
   check, the API rule or the header handling off, because there is no
   switch. As today, a team can turn its API's rate limit and backend lock
   off; the platform can stop that per tenant.
1. Use the supported product APIs (Gateway API, Istio policies). Where a
   filter is unavoidable, the platform owns and tests it; teams never write
   one.
1. One tenant, one gateway. A tenant's routes never attach to
   another tenant's gateway.
1. When the platform can't do something per tenant, say so. Don't fake it.

## Non-goals

- Running the identity provider. Red Hat build of Keycloak (RHBK) realms,
  clients and roles stay with the platform team (automation is a later story).
- Installing OpenShift Service Mesh, Redis or the Gateway API CRDs.
  They are prerequisites.
- Mesh membership, east-west traffic between tenants, and mesh telemetry. They
  belong to the Multi-Tenant Operator's Service Mesh extension (in design).
- A platform gateway in front of the tenant gateways, such as the Service
  Mesh extension's ingress (ADR-0009 rejected it for v1). Tenants do share a
  front-door host, by path prefixes the platform grants (ADR-0009).
- API management features: developer portal, API keys sold as products,
  monetisation, request transformation beyond Gateway API filters.

## How we'll know it works

- No `EnvoyFilter` but the platform's three, and no Lua, in any rendered
  output, for any fixture (render check).
- A call without a token, with an invalid token, or with a token for another
  API never reaches the application, in the acceptance suite
  (`docs/acceptance.md`); each denial is paired with a matching allow.
- A route in one tenant can't attach to another tenant's gateway, and a host
  outside the tenant's hostnames is never served.
- A caller-sent `x-sub` or `x-roles` header never reaches the application.
- After a Service Mesh minor upgrade, the acceptance suite is green with no
  change to the chart.
- A tenant with three APIs runs one gateway, and its pod count follows the load.
