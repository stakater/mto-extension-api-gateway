# ADR-0002: One gateway per tenant, requested by the team, in the team's namespace

- **Status:** Proposed
- **Date:** 2026-11-16 (the gateway's fixed name decided on 2026-11-26)

## Context

Today the common grain is one gateway per API, per environment, each at a
fixed replica count. A team with two APIs and three environments runs six
gateways, and every pod runs whether or not anybody calls the API. Istio
deploys one Deployment per Gateway API `Gateway` and accepts an autoscaler and
a disruption budget for it (M3). A listener can accept routes only from
namespaces that match a label selector (A1), and the Multi-Tenant Operator
labels every tenant namespace with its tenant (T1).

Not every team needs a gateway, and the platform team wants a team to ask for
one, not to get one by default. Template Operator lets a team's
`TemplateInstance` render into its own namespace; a `Template` parameter with
`disableOverride` can't be changed by the instance; and sync mode `strict`
makes Template Operator's admission webhook refuse edits and deletes of what
an instance rendered (T2, T3). Anyone who can create a `TemplateInstance` can
otherwise make the operator read what its service account can read, through
`valueFrom` parameters.

The Service Mesh extension (in design) refuses tenant-created `Gateway`s.

## Decision

- **A team asks for its tenant's gateway** with one `TemplateInstance` of the
  platform's `api-gateway` Template, in the tenant namespace where the gateway
  should run. The instance has **no parameters**: every parameter of
  `api-gateway` is a `disableOverride` default. A team tunes a few
  non-security settings with validated annotations on the request (ADR-0012).
- **The request renders the gateway, not its policy:** the `Gateway`, its
  scaling ConfigMap, its certificates and a status ConfigMap. The tenant's
  child `TemplateInstance` renders the gateway's policies (ADR-0013).
- **One gateway per tenant.** The oldest valid request in a tenant's
  namespaces owns it; every other request renders only a status ConfigMap that
  names the owner.
- **The gateway runs in the request's namespace, always named
  `mto-api-gateway`**: its pods `mto-api-gateway-istio`. The request's own
  name is free. A fixed, reserved name never matches a gateway that runs
  today, so Template Operator never takes one over (ADR-0001). Its pods count
  against the tenant's quota.
- **The tenant is never the team's input.** The bootstrap chart's parent
  publishes `api-gateway` with `tenantOf` (namespace → tenant, from the tenant
  label) and `owner` (tenant → request) as `disableOverride` defaults, and
  keeps them current. The team render reads its tenant from `tenantOf` by its
  own namespace.
- **The team can't change what it got.** `api-gateway` syncs `strict`; only
  tenant namespaces may instantiate it.
- **The listener accepts routes only from the tenant's namespaces:**
  `allowedRoutes.namespaces.from: Selector` with
  `stakater.com/tenant: <tenant>`, kinds `HTTPRoute` only.
- **The gateway's pods carry the platform label** that the token floor and
  default deny select (ADR-0004), and its Service is `ClusterIP`: callers come
  in through the entry point (G.18), never through a load balancer per tenant.
- **The gateway scales with load:** a `HorizontalPodAutoscaler` and a
  `PodDisruptionBudget` through `spec.infrastructure.parametersRef` (M3), with
  platform-set minimum and maximum.

## Consequences

- Gateways per cluster = tenants that asked, not APIs × environments. An idle
  tenant runs nothing.
- The team chooses where its gateway runs and sees its pods; the platform
  still decides everything about how it runs.
- The APIs of one tenant share gateway pods: a load peak on one API reaches the
  others of the same tenant. Autoscaling and the per-caller rate limit reduce
  this; G.12 records how a tenant could get a second gateway later, if a need
  arises.
- Two environments of one tenant on one cluster share its gateway: its load,
  its settings and its issuers. A tenant per environment, or a cluster per
  environment, keeps them apart. A gateway per tenant and environment was
  considered on 2026-11-19 and left out of v1: it was seen only on a test
  cluster.
- The gateway's pods count against the tenant's quota; a quota below the
  autoscaler's minimum keeps the gateway from starting.
- Template Operator needs write access to `Gateway`s, ConfigMaps,
  certificates and the gateway-level policies in tenant namespaces
  (cluster-wide, as tenant namespaces come and go).
- The gateway's service account lives in a tenant namespace. A tenant editor
  could run a pod as that service account, the identity the backend lock
  trusts, so admission refuses it (ADR-0008, G.8, built before any API is
  served).
- The Service Mesh extension's refusal of tenant `Gateway`s must let Template
  Operator's own writes through; a tenant still can't create a `Gateway`
  directly (ADR-0008).
- Every tenant namespace that hosts a route or the gateway must be in the mesh
  (M5). The extension reports a namespace that isn't (design §7).

## Alternatives

- **A gateway for every tenant, automatically, in a platform namespace (the
  first version of this ADR).** Rejected: the platform wants teams to ask, and
  an automatic gateway runs pods for tenants that never publish an API.
- **The gateway in the platform namespace, on request.** Rejected by the code
  owner on 2026-11-16 in favour of the team's namespace: the team sees and
  pays for its own gateway pods.
- **A `TemplateInstance` with parameters (hosts, replicas, security
  switches).** Rejected: a parameter can be set wrongly or read from a source
  the team shouldn't reach; with none, nothing in the request can be wrong.
- **The gateway named after the request (the first version).** Rejected on
  2026-11-26: a team that named its request after today's gateway, in the same
  namespace, would make Template Operator take over a production gateway
  (issue #11). One tenant has one gateway, so a fixed name loses nothing.
- **One gateway per namespace or per API.** Rejected as the default: more pods
  for the same separation the tenant boundary gives. More than one gateway
  per tenant stays a later option, only if a need arises (G.12).
