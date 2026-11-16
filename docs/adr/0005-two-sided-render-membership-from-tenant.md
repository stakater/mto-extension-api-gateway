# ADR-0005: Two-sided rendering; mesh and waypoint membership come from the `Tenant`

- **Status:** Proposed
- **Date:** 2026-11-16

## Context

A gateway writes to two namespaces: the gateway namespace (the `Gateway`,
routes, token checks) and the application namespace (`ReferenceGrant`,
`gw-only`, the waypoint). A team-authored `TemplateInstance` renders into its
own namespace (**T3**). The backend side is shared by every gateway whose
backend is in that application namespace, and mesh membership belongs in the
reviewed `Tenant`, not a gateway chart (**T2**, sm:§3). A waypoint is one per
namespace, shared.

## Decision

- **Gateway side:** the team's `TemplateInstance` of `api-gateway`, in the
  gateway namespace.
- **Backend side:** a platform `TemplateGroupInstance` of `api-backend` renders
  `ReferenceGrant`, `gw-only` (listing every gateway serving the namespace) and
  the waypoint into each application namespace, reconciled from the tenant's
  gateways (**Q2**, **Q3**).
- **Mesh and waypoint membership:** set by the platform in the `Tenant`'s
  `namespaces.metadata` labels (`istio.io/dataplane-mode`,
  `istio.io/use-waypoint`), reviewed in Git. The extension writes **no**
  namespace label.

## Consequences

- The waypoint and `gw-only` are owned once per application namespace and
  survive while any gateway uses them (design §11).
- Mesh membership stays in the reviewed `Tenant`, consistent with the
  service-mesh extension.
- Depends on `TemplateGroupInstance` targeting a tenant's application namespaces
  and cross-namespace rendering (**Q2**, **Q11**).

## Alternatives

- **One Template rendering both namespaces from the team's TemplateInstance.**
  Rejected: a team-authored object writing into the application namespace, and
  duplicate waypoints when two gateways share a backend namespace.
- **The gateway chart sets the namespace labels.** Rejected: namespaces are the
  Multi-Tenant Operator's, and the label must be reviewed in the `Tenant`
  (sm:§3).
