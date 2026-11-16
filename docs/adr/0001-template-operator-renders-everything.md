# ADR-0001: Template Operator renders everything; no new operator

- **Status:** Proposed
- **Date:** 2026-11-16

## Context

Every object this extension needs already has a supported API: the Gateway API
`Gateway` and `HTTPRoute`, Service Mesh's gateway deployment (M3), Istio's
`AuthorizationPolicy`, and Connectivity Link's `AuthPolicy` and
`RateLimitPolicy` (K2–K6). None of them needs a controller of ours to
reconcile it. The other Multi-Tenant Operator extensions
(`mto-extension-vault-enterprise`, `mto-extension-openbao`) use one pattern
for this: a bootstrap chart, installed once, renders a parent
`TemplateInstance` that fans out one render of a per-tenant chart per `Tenant`
(T2).

The first proposal for this extension was a Template Operator `Template` that
an API team instantiates once per API.

## Decision

- **Two Helm charts, rendered by Template Operator v2**, in the shape of the
  other extensions:
    - `mto-extension-api-gateway-bootstrap`: installed once per cluster by
      Helm; renders the gateway namespace's objects and, per `Tenant`, the
      tenant gateway, its gateway-level policies and its autoscaling config.
    - `mto-extension-api-gateway`: never installed by hand; pulled per tenant;
      renders the route-level policy and the backend lock for every annotated
      `HTTPRoute` in the tenant's namespaces.
- **No custom resource and no controller.** The developer contract is the
  Gateway API `HTTPRoute` plus one annotation (ADR-0005).
- **Templates use sync mode `revert`**, so a chart upgrade or a tenant change
  reaches every tenant, and a hand edit to a rendered object is reverted (T3).

## Consequences

- Nothing new to run, upgrade or secure besides Template Operator, which the
  other extensions already need.
- An upgrade is one chart version bump; Template Operator renders every tenant
  again.
- What Template Operator can't do, this extension can't do: a decision that
  needs a loop over live traffic, or an external system (RHBK), needs another
  tool (story G.11).
- Template Operator's service account needs RBAC on Gateway API, Istio and
  Connectivity Link kinds. The chart lists exactly those (Q6).

## Alternatives

- **A `Template` that the API team instantiates per API (the first
  proposal).** Rejected as the contract: a tenant-created `TemplateInstance`
  is a new, non-standard API for each team to learn, and it renders with the
  operator's rights, not the team's. Its goals (one chart, no security
  switches, a derived allowed-API rule, one upgrade) are kept — see
  ADR-0004..0006.
- **A new operator with an `ApiGateway` CRD.** Rejected: one more component to
  build and run, for objects that already have standard APIs.
- **A chart per team (today).** Rejected: copies drift, and every team owns the
  security switches.
