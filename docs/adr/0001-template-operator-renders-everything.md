# ADR-0001: Template Operator renders everything; no new operator

- **Status:** Proposed
- **Date:** 2026-11-16

## Context

Every object this extension needs already has a supported API: the Gateway API
`Gateway` and `HTTPRoute`, Service Mesh's gateway deployment (M3), Istio's
`RequestAuthentication` and `AuthorizationPolicy` (M6), and the few
platform-owned `EnvoyFilter`s of ADR-0003. None of them needs a controller of ours to
reconcile it. The other Multi-Tenant Operator extensions
(`mto-extension-vault-enterprise`, `mto-extension-openbao`) use one pattern
for this: a bootstrap chart, installed once, renders a parent
`TemplateInstance` that fans out one render of a per-tenant chart per `Tenant`
(T2).

The first proposal for this extension was a Template Operator `Template` that
an API team instantiates once per API.

## Decision

- **One Helm chart, rendering Template Operator v2 objects**, in the shape of
  the other extensions: `mto-extension-api-gateway-bootstrap`, installed once
  per cluster by Helm. It renders:
    - the parent `Template` and `TemplateInstance`; the parent publishes the
      team-facing `api-gateway` and `api` Templates and emits one child
      `TemplateInstance` per tenant that has a gateway (ADR-0013);
    - the child Template `api-gateway-policy`, which renders the tenant's
      gateway policy, one rule per API and the backend locks;
    - the cluster-wide parts: the token floor and default deny in the Istio
      root namespace (ADR-0004), the rate limit service, and the admission
      policy (ADR-0008).

  A team's `TemplateInstance` of `api-gateway`, with no parameters, renders
  the tenant's `Gateway`, its scaling config and its certificates in the
  team's namespace (ADR-0002). A team's `TemplateInstance` of `api` renders
  one API's `HTTPRoute` in its namespace (ADR-0005).
- **No custom resource and no controller.** The developer contract is one
  `TemplateInstance` per tenant for the gateway (ADR-0002) and one
  `TemplateInstance` of `api` per API (ADR-0005).
- **Templates never use sync mode `off`**, so a promoted template generation
  or a tenant change reaches every tenant it should (T3, ADR-0015). The parent uses `revert`; `api-gateway`,
  `api` and `api-gateway-policy` use `strict`, so a team can't edit or delete what
  it got.

## Consequences

- Nothing new to run, upgrade or secure besides Template Operator, which the
  other extensions already need.
- An upgrade is one chart version bump; Template Operator renders every tenant
  again.
- What Template Operator can't do, this extension can't do: a decision that
  needs a loop over live traffic, or an external system (RHBK), needs another
  tool (story G.11).
- Template Operator's service account needs RBAC on Gateway API, Istio and
  `EnvoyFilter` kinds. The chart lists exactly those (Q6).

## Alternatives

- **A `Template` that the API team instantiates per API, with parameters
  (the first proposal).** Rejected as the API contract: its parameters
  re-create a values file, and an instance renders with the operator's rights
  and can read through `valueFrom`. Kept in a safer form for the gateway
  itself: one `TemplateInstance` per tenant, with no parameters (ADR-0002).
  Its goals (one chart, no security switches, a derived allowed-API rule, one
  upgrade) are kept — see ADR-0004..0006.
- **A new operator with an `ApiGateway` CRD.** Rejected: one more component to
  build and run, for objects that already have standard APIs.
- **A chart per team (today).** Rejected: copies drift, and every team owns the
  security switches.
- **A second, per-tenant Helm chart pulled by Template Operator** (the Vault
  Enterprise shape, the first version of this ADR). Rejected for now: it
  needs a published chart and pull credentials (ADR-0013).
