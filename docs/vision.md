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

> **One tenant definition, carried into the API gateway.** Every tenant gets
> its own gateway, with the platform's security baseline built in and not
> switchable. A team publishes an API with a standard `HTTPRoute` and one
> annotation. Token check, allowed-API check, header handling and rate limits
> come from supported Red Hat Connectivity Link policies, not from patches.

The product abstraction is **Tenant → API gateway**. Underneath, it is plain
Gateway API on OpenShift Service Mesh, with Connectivity Link policies,
rendered per tenant by Template Operator.

## Who it is for

| Persona | Job to be done | What they get |
|---|---|---|
| **Platform team** | run API gateways safely for many teams, and upgrade them without a project per team | one chart for all tenants; one version bump upgrades every gateway; a security baseline that no tenant can switch off |
| **API team** | publish an API without learning the gateway design | a standard `HTTPRoute` and one annotation; first-line troubleshooting with the familiar `401`, `403`, `429` |
| **Security and audit** | prove that every API checks the token and the caller's rights | the checks live in platform-owned policies that a route can't weaken; render checks fail on any wildcard or missing check |
| **Red Hat platform owners** | stay on supported products through upgrades | Gateway API, Service Mesh 3 and Connectivity Link as designed, with no `EnvoyFilter` in the rendered output |

## Value proposition

- **Secure by construction.** The token check, the header handling and the rate
  limit are set on the tenant's gateway by the platform. A route can add a
  rule; it can't remove one.
- **Self-service in the standard API.** An API team writes an `HTTPRoute`, the
  Kubernetes Gateway API object every OpenShift guide teaches. No chart copy,
  no values file, no gateway knowledge.
- **Supported through upgrades.** Connectivity Link policies replace the
  `EnvoyFilter` patches. Red Hat tests them against each Service Mesh release.
- **Fewer idle pods.** One gateway per tenant, scaled by load, instead of one
  per API at a fixed size.
- **One upgrade for all.** The platform bumps one chart; Template Operator
  renders every tenant again.

## Principles

1. The platform owns the gateway and its security baseline. Tenants own their
   routes.
1. Security settings are never parameters. A tenant can't turn a check off,
   because there is no switch.
1. Use the supported product APIs (Gateway API, Connectivity Link). No
   `EnvoyFilter`.
1. One tenant, one gateway, by default. A tenant's routes never attach to
   another tenant's gateway.
1. When the platform can't do something per tenant, say so. Don't fake it.

## Non-goals

- Running the identity provider. Red Hat build of Keycloak (RHBK) realms,
  clients and roles stay with the platform team (automation is a later story).
- Installing OpenShift Service Mesh, Connectivity Link or the Gateway API CRDs.
  They are prerequisites.
- Mesh membership, east-west traffic between tenants, and mesh telemetry. They
  belong to the Multi-Tenant Operator's Service Mesh extension (in design).
- A shared, multi-tenant entry point where several tenants share one host. The
  Service Mesh extension's platform ingress covers that case.
- API management features: developer portal, API keys sold as products,
  monetisation, request transformation beyond Gateway API filters.

## How we'll know it works

- No `EnvoyFilter` in any rendered output, for any fixture (render check).
- A call without a token, with an invalid token, or with a token for another
  API never reaches the application, in the acceptance suite
  (`docs/acceptance.md`); each denial is paired with a matching allow.
- A route in one tenant can't attach to another tenant's gateway, and a host
  outside the tenant's hostnames is never served.
- A caller-sent `x-sub` or `x-roles` header never reaches the application.
- After a Service Mesh minor upgrade, the acceptance suite is green with no
  change to the chart.
- A tenant with three APIs runs one gateway, and its pod count follows the load.
