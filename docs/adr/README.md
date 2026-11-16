# Architecture Decision Records

Each ADR records one decision: its context, what we decided, the consequences
(including costs), and the alternatives we rejected and why.

**Convention:** ADRs are immutable once accepted. Write a new ADR that
**supersedes** an old one rather than editing it.

Format: Title · Status · Date · Context · Decision · Consequences · Alternatives.
Facts are cited to `../api-gateway-baseline.md` by row.

## Index

| # | Decision | Status |
|---|---|---|
| [0001](0001-template-library-no-component.md) | The gateway is a platform-owned Template a team instantiates; the extension runs no component | Proposed |
| [0002](0002-security-baked-not-parameters.md) | Security configuration is baked into the Template, never a parameter | Proposed |
| [0003](0003-consumer-scope-derived.md) | Consumer authorization scope is derived from the API name, never free text | Proposed |
| [0004](0004-one-gateway-per-api-per-env.md) | One gateway per API per environment; a `TemplateInstance` per gateway | Proposed |
| [0005](0005-two-sided-render-membership-from-tenant.md) | Two-sided rendering; mesh and waypoint membership come from the `Tenant` | Proposed |
| [0006](0006-compose-with-service-mesh-extension.md) | Compose with the service-mesh extension; platform-rendered gateways are the sanctioned exception | Proposed |
| [0007](0007-rate-limit-shared-service-always-on.md) | Rate limiting through the shared service, always enforced; the tier is the only knob | Proposed |
| [0008](0008-ambient-first-sidecar-later.md) | Ambient mode first; sidecar mode later | Proposed |
| [0009](0009-consumer-provisioning-out-of-scope.md) | Identity-provider consumer provisioning is a prerequisite in v1, a Keycloak-extension seam later | Proposed |
| [0010](0010-telemetry-one-path.md) | Telemetry through the platform collector; no second path | Proposed |

Every ADR is **Proposed**. They record the design's position of 2026-11-16 and
wait for two things: Rasheed Amir's decisions (the open decisions in
`../roadmap.md`), and story M.0 confirming the gateway behaviour they rest on —
chiefly **Q1** (rate limiting without `EnvoyFilter`), on which ADR-0007 turns.
A finding against one is a new, superseding ADR.
