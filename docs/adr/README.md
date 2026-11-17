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
| [0002](0002-one-gateway-per-tenant-requested-by-the-team.md) | One autoscaled `Gateway` per tenant, requested by the team with a parameterless `TemplateInstance`, in the team's namespace; the listener takes only the tenant's namespaces | Proposed |
| [0003](0003-istio-native-policies-and-platform-owned-envoyfilters.md) | Token check and allowed-API rule are Istio `RequestAuthentication` and `AuthorizationPolicy`; header removal and rate limit are two platform-owned, tested `EnvoyFilter`s; Kuadrant is the alternative, revisited on stated conditions | Proposed |
| [0004](0004-security-baseline-is-a-gateway-override.md) | The security baseline is platform-rendered gateway policy (token floor, default deny, closed allowed-API rule per API, claim headers, rate limit); tenants can't write gateway policy; no security setting is a tenant value | Proposed |
| [0005](0005-an-api-is-an-httproute-with-one-annotation.md) | An API is a standard `HTTPRoute` in a tenant namespace with one annotation | Proposed |
| [0006](0006-allowed-api-rule-is-derived-and-tenant-qualified.md) | The allowed-API rule is `api.<tenant>.<api>`, derived and closed; never a typed pattern | Proposed |
| [0007](0007-every-backend-is-locked-to-its-tenant-gateway.md) | Every API backend refuses all but its tenant gateway, by an L4 `DENY` rule; a backend that can't be locked serves nothing | Proposed |
| [0008](0008-tenants-never-create-gateways-or-policies.md) | Tenants create `HTTPRoute`s only; RBAC, admission and overrides keep it so | Proposed |
| [0009](0009-a-tenant-serves-only-its-own-hostnames.md) | Each tenant gateway serves `*.<tenant>.<base domain>` plus hostnames the platform grants | Proposed |
| [0010](0010-the-gateway-class-is-the-ambient-mesh-istio-class.md) | The gateway class is `istio`, from the ambient mesh's control plane; never `openshift-default` | Proposed |
| [0011](0011-connectivity-link-is-tested-upstream-kuadrant-is-allowed.md) | Connectivity Link as the tested Kuadrant controller, upstream Kuadrant allowed (rejected with ADR-0003's rewrite; kept as the record) | Rejected |

All are Proposed until story G.0 confirms the Service Mesh, Gateway API,
Connectivity Link and Template Operator behaviour they rest on.
