# ADR-0002: One gateway per tenant, in a platform namespace

- **Status:** Proposed
- **Date:** 2026-11-16

## Context

Today the common grain is one gateway per API, per environment, each at a
fixed replica count. A team with two APIs and three environments runs six
gateways, and every pod runs whether or not anybody calls the API. Istio
deploys one Deployment per Gateway API `Gateway` and accepts an autoscaler and
a disruption budget for it (M3). A listener can accept routes only from
namespaces that match a label selector (A1), and Multi-Tenant Operator labels
every tenant namespace with its tenant (T1).

The Service Mesh extension (in design) refuses tenant-created `Gateway`s and
plans platform-owned gateways in a platform namespace, with
`allowedRoutes.namespaces.from: Selector` on the tenant label.

## Decision

- **One `Gateway` per tenant**, named after the tenant, in one platform
  namespace (`mto-api-gateways` by default). The platform owns the namespace;
  tenants have no access to it.
- **The listener accepts routes only from the tenant's namespaces:**
  `allowedRoutes.namespaces.from: Selector` with
  `stakater.com/tenant: <tenant>`, kinds `HTTPRoute` only.
- **The gateway scales with load:** a `HorizontalPodAutoscaler` and a
  `PodDisruptionBudget` through `spec.infrastructure.parametersRef` (M3), with
  platform-set minimum and maximum.
- More than one gateway per tenant (for example, one per environment) is a
  later, opt-in story (G.12), not the default.

## Consequences

- Gateways per cluster = tenants with at least one API, not APIs ×
  environments.
- The APIs of one tenant share gateway pods: a load peak on one API reaches the
  others of the same tenant. Autoscaling and the per-caller rate limit reduce
  this; G.12 gives an API its own gateway when it needs one.
- The gateway pods run in a platform namespace, so their cost is not in the
  tenant's namespace quota. The pods carry the tenant label for chargeback.
- One place for a platform team to see and operate every gateway.
- Every tenant namespace that hosts a route must be visible to the mesh (M5).
  The extension reports a namespace that isn't (design §8).

## Alternatives

- **One gateway per API (today).** Rejected as the default: many idle pods, and
  per-API gateways don't make the security baseline easier to enforce. Kept as
  an opt-in (G.12).
- **The gateway in a tenant namespace.** Rejected: tenant editors could change
  the `Gateway`, its listeners or its infrastructure parameters, and the
  Service Mesh extension refuses tenant `Gateway` writes.
- **One shared gateway for all tenants.** Rejected for this extension: one
  tenant's load or misconfiguration reaches every tenant, and the security
  baseline can't differ per tenant. The Service Mesh extension's platform
  ingress covers the shared case.
