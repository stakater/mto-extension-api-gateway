# ADR-0013: Gateway policy is rendered by a per-tenant child, not by the team's request

- **Status:** Proposed
- **Date:** 2026-11-17

## Context

The team's request (ADR-0002) renders the tenant's `Gateway`. The gateway's
policies need more than the request can see: the tenant's annotated
`HTTPRoute`s, their backend `Service`s, and the team's knobs (ADR-0012). The
parent already reads every `TemplateInstance`, but if it validated knobs
itself, one malformed request could fail the parent's render for every
tenant, and every knob change would rewrite the `api-gateway` Template and
re-render every tenant's gateway.

Template Operator can list objects of a kind across all namespaces that match
a label selector, re-resolving the list when namespaces change (T7). The
Vault Enterprise extension uses one child `TemplateInstance` per tenant in the
same way.

## Decision

- **The parent emits one child `TemplateInstance` per tenant that has a
  gateway owner,** in the platform namespace, of the child Template
  `api-gateway-policy` (a gotemplate Template rendered by the bootstrap chart;
  no Helm chart to publish or pull).
- **The child's parameters:** the tenant; the owner request (namespace and
  name); the platform's values; and, through `objectFieldRef` with a
  `namespaceSelector` on the tenant label, the tenant's `HTTPRoute`s,
  `Service`s and `TemplateInstance`s.
- **The child renders all of the tenant's gateway policy:** the
  `RequestAuthentication`, the three `EnvoyFilter`s, `Telemetry`, one `ALLOW`
  per API (in the gateway's namespace), one backend lock per backend (in the
  route's namespace), and the tenant's status ConfigMap `<request>-apis` in
  the gateway's namespace (APIs, routes that are not APIs, duplicates, host
  conflicts, refused knobs).
- **The team's request keeps** the `Gateway`, its scaling ConfigMap, its
  certificates and its own status ConfigMap.
- The child syncs `strict`, like the team's Template.

## Consequences

- One tenant's bad input fails only that tenant's child; other tenants keep
  rendering.
- A route or knob change re-renders one tenant's child, not every gateway.
- The floor and the default deny don't depend on the child (ADR-0004): while a
  child is missing or failing, its gateway refuses everything.
- One more `TemplateInstance` per tenant with a gateway, in the platform
  namespace.
- The child must render correctly with an empty route list and with objects
  that have no annotations. The harness tests both (T6, T7).

## Alternatives

- **All policy in the team's request render.** Rejected: the request can't
  see the tenant's routes, and every new platform input becomes a parameter of
  `api-gateway`, which re-renders every tenant.
- **The parent validates knobs and routes.** Rejected: one bad object fails
  every tenant.
- **A per-tenant Helm chart pulled from a chart repository** (the Vault
  Enterprise shape). Rejected for now: it needs a published chart and pull
  credentials; a gotemplate keeps the whole extension in one chart.
