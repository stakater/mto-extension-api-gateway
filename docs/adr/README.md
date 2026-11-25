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
| [0001](0001-template-operator-renders-everything.md) | One bootstrap chart renders Template Operator v2 objects (parent, team Templates, per-tenant child) and the cluster-wide parts; no CRD, no controller | Proposed |
| [0002](0002-one-gateway-per-tenant-requested-by-the-team.md) | One autoscaled `Gateway` per tenant, requested by the team with a parameterless `TemplateInstance`, in the team's namespace; the listener takes only the tenant's namespaces | Proposed |
| [0003](0003-istio-native-policies-and-platform-owned-envoyfilters.md) | Token check and allowed-API rule are Istio `RequestAuthentication` and `AuthorizationPolicy`; header removal, rate limit and correlation ID are three platform-owned, tested `EnvoyFilter`s; the API rule checks the host and the path; Kuadrant is the alternative, revisited on stated conditions | Proposed |
| [0004](0004-security-baseline-is-a-gateway-override.md) | The token floor and default deny live once in the Istio root namespace; every other check is platform-rendered per gateway; tenants can't write gateway policy; a team can turn its API's rate limit (and its backend lock, ADR-0007) off unless the platform locks the tenant; the platform can exempt a tenant or one API from the rate limit | Proposed |
| [0005](0005-an-api-is-a-templateinstance-checked-by-host-and-path.md) | An API is a `TemplateInstance` of `api` with checked parameters; it renders the `HTTPRoute`; the API rule checks the host and the path, so APIs share a host; tenants write no routes | Proposed |
| [0006](0006-allowed-api-rule-is-derived-and-tenant-qualified.md) | The allowed-API rule is `api.<tenant>.<api>`, derived and closed; never a typed pattern | Proposed |
| [0007](0007-backends-are-locked-through-a-waypoint.md) | A backend accepts its API's paths only from its tenant gateway, through a waypoint and an L7 `DENY`, with health and metrics paths open, as today; the team can turn the lock off unless the platform locks the tenant | Proposed |
| [0008](0008-tenants-never-create-gateways-or-policies.md) | Tenants create only `TemplateInstance`s; RBAC, admission and the token floor keep it so; tenants can't act as the gateway | Proposed |
| [0009](0009-a-tenant-serves-only-the-hosts-and-paths-it-is-granted.md) | Each tenant gateway serves `*.<tenant>.<base domain>`, extra hostnames the platform grants, and path prefixes the platform grants on a shared host; the shared-host prefixes are reached through reencrypt OpenShift `Route`s | Proposed |
| [0010](0010-the-gateway-class-is-the-ambient-mesh-istio-class.md) | The gateway class is `istio`, from the ambient mesh's control plane; never `openshift-default` | Proposed |
| [0011](0011-connectivity-link-is-tested-upstream-kuadrant-is-allowed.md) | Connectivity Link as the tested Kuadrant controller, upstream Kuadrant allowed (rejected with ADR-0003's rewrite; kept as the record) | Rejected |
| [0012](0012-teams-tune-their-gateway-with-validated-annotations.md) | Teams tune claim headers, correlation ID, access logs and trace headers with validated annotations on their request; no parameters | Proposed |
| [0013](0013-gateway-policy-is-rendered-per-tenant.md) | One child `TemplateInstance` per tenant renders the gateway's policies, rules and locks; the team's request renders only the gateway | Proposed |
| [0014](0014-an-api-backend-can-be-outside-the-cluster.md) | An API's backend can be a host outside the cluster, as in today's chart: `ServiceEntry`, `DestinationRule` (TLS `SIMPLE`, `MUTUAL` or `DISABLE`) and an `ExternalName` Service; no lock, no token forwarding | Proposed |
| [0015](0015-staged-upgrades-with-two-template-generations.md) | Template changes ship as a new generation; a chart release holds at most two; the platform moves a canary API or tenant first, then everyone; rollback by values; no downtime | Proposed |

All are Proposed until stories G.19 (kind) and G.0 (OpenShift) confirm the
Istio, Service Mesh, Gateway API and Template Operator behaviour they rest on.
