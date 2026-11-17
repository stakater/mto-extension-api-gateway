# ADR-0005: An API is a standard HTTPRoute with one annotation

- **Status:** Proposed
- **Date:** 2026-11-16

## Context

An API team needs to say: this host and path, rewritten to that path, go to
that Service. Gateway API's `HTTPRoute` says exactly that, with standard
filters for path rewrite and headers (A4), and attaches to a `Gateway` in
another namespace when the listener allows it (A1). Multi-Tenant Operator's
other extensions take their input as annotations on standard objects (for
example `vault.stakater.com/*` on a ServiceAccount) and render the rest.

## Decision

- **The API team writes a standard `HTTPRoute`** in a tenant namespace, with
  `parentRefs` to its tenant gateway, a host in the tenant's hostnames
  (ADR-0009), and **one annotation**:
  `api-gateway.stakater.com/api: <api name>`.
- The API name is a DNS label, unique within the tenant. Two routes with the
  same API name in one tenant are both skipped and reported (design §7).
- The per-tenant chart finds every annotated `HTTPRoute` in the tenant's
  namespaces and renders, in the route's namespace: the route-level
  allowed-API rule (an Istio `AuthorizationPolicy` `ALLOW` rule scoped to the
  route's hosts and paths, ADR-0006) and the backend lock
  (ADR-0007).
- The backend `Service` is in the route's own namespace. No `ReferenceGrant`
  is rendered or needed (A2).

## Consequences

- Teams learn the Kubernetes standard, not a Stakater format, and keep every
  `HTTPRoute` feature (matches, rewrites, header filters, several rules).
- A route without the annotation attaches but serves nothing: the gateway's
  default denies it (ADR-0004). The extension lists it as "not an API" in the
  tenant's status ConfigMap, so the team sees why.
- Moving between environments changes the namespace and the host only.
- Teams that keep their routes in Git sync them as today (Argo CD or similar).

## Alternatives

- **A `TemplateInstance` per API with a few parameters (the first
  proposal).** Rejected as the contract (ADR-0001): non-standard, and its
  parameters re-create a smaller values file. Its derived values (allowed-API
  rule, backend namespace) are kept, derived from the route instead.
- **Annotations on the backend `Service`, the route rendered for the team.**
  Rejected: hides routing features teams already use (several matches,
  rewrites, headers) behind an annotation language.
- **A CRD `Api`.** Rejected (ADR-0001).
