# Architecture Decision Records

Each ADR records one decision: its context, what we decided, the consequences
(including costs), and the alternatives we rejected and why.

**Convention:** ADRs are immutable once accepted. Don't edit a decided ADR to
reflect a changed mind — write a new ADR that **supersedes** it, and update the
old one's status. This keeps the evolution of decisions legible.

Format: Title · Status · Date · Context · Decision · Consequences · Alternatives.
Facts are cited to `../gateway-baseline.md` by row.

## Index

| # | Decision | Status |
|---|---|---|
| [0001](0001-template-operator-renders-everything.md) | A bootstrap chart and a per-tenant chart, rendered by Template Operator v2; no CRD, no controller | Proposed |
| [0002](0002-one-gateway-per-tenant-in-a-platform-namespace.md) | One autoscaled `Gateway` per tenant, in one platform namespace; the listener takes only the tenant's namespaces | Proposed |
| [0003](0003-connectivity-link-policies-not-envoyfilters.md) | Token, allowed-API rule, headers and rate limits are Connectivity Link policies; no `EnvoyFilter` | Proposed |
| [0004](0004-security-baseline-is-a-gateway-override.md) | The security baseline is a gateway-level override with a default deny; no security setting is a tenant value | Proposed |
| [0005](0005-an-api-is-an-httproute-with-one-annotation.md) | An API is a standard `HTTPRoute` in a tenant namespace with one annotation | Proposed |
| [0006](0006-allowed-api-rule-is-derived-and-tenant-qualified.md) | The allowed-API rule is `api.<tenant>.<api>`, derived and closed; never a typed pattern | Proposed |
| [0007](0007-every-backend-is-locked-to-its-tenant-gateway.md) | Every API backend accepts only its tenant gateway, by an L4 mesh rule; no waypoint needed | Proposed |
| [0008](0008-tenants-never-create-gateways-or-policies.md) | Tenants create `HTTPRoute`s only; RBAC, admission and overrides keep it so | Proposed |
| [0009](0009-a-tenant-serves-only-its-own-hostnames.md) | Each tenant gateway serves `*.<tenant>.<base domain>` plus hostnames the platform grants | Proposed |

All are Proposed until story G.0 confirms the Service Mesh, Gateway API,
Connectivity Link and Template Operator behaviour they rest on.
