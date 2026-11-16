# ADR-0004: One gateway per API per environment; a `TemplateInstance` per gateway

- **Status:** Proposed
- **Date:** 2026-11-16

## Context

Each API has its own external host, backend, consumer scope and rate-limit tier.
A gateway could be scoped per tenant (one gateway for all of a team's APIs), per
API per environment, or one cluster-wide gateway for everyone. The reference
architecture runs one per API per environment: a team with two APIs and three
environments has six gateways.

## Decision

The unit is **one gateway per API per environment**, each its own
`TemplateInstance` in the API's gateway namespace (`<api>-gateway-<env>`).

## Consequences

- Each gateway's security and routing are about one API, so there is no
  per-route security configuration — the thing teams get wrong.
- Blast radius is one API: a bad route or a redeploy affects only it.
- It matches how teams already name and reason about gateways.
- **Cost:** each gateway is its own Deployment+Service (**J1**), plus one
  waypoint per application namespace (**J2**). Dozens of gateways per cluster is
  a real resource and istiod-push cost; scale is **Q10**.

## Alternatives

- **One gateway per tenant.** Rejected: forces per-API config onto one proxy's
  routes, reintroducing the footgun, and widens blast radius.
- **One shared cluster gateway.** Rejected: a single entry point for every
  tenant's APIs; cross-tenant blast radius; per-route security at scale.
