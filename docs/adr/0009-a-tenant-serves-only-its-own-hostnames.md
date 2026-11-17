# ADR-0009: A tenant serves only its own hostnames

- **Status:** Proposed
- **Date:** 2026-11-16

## Context

Two tenants must never serve the same host, and a tenant must not take over a
host that belongs to another tenant or to the platform. A Gateway API listener
with a `hostname` only accepts routes whose hostnames intersect it (A3).

## Decision

- **Each tenant gateway's listener has the hostname
  `*.<tenant>.<base domain>`**, with the base domain a platform value
  (`apis.example.com`).
- The platform may grant a tenant extra hostnames (bootstrap value, per
  tenant). Each extra hostname gets its own listener on that tenant's gateway.
  The gateway's default deny covers every listener (ADR-0004). The parent
  refuses an extra hostname that overlaps the base domain (reserved for
  tenant names, including tenants created later) or overlaps another
  tenant's extra hostname (a wildcard intersection, not an equality), and
  lists the refusal (design §7).
- Tenants can't claim a host under the base domain at the entry point either:
  the base domain has its own entry point, and admission refuses a tenant's
  OpenShift `Route` under it (ADR-0008, design §9).
- TLS: one certificate per listener, from a platform-named issuer (Q10).

## Consequences

- A route for another tenant's host doesn't attach: the listener ignores it.
- Host names show who owns an API.
- A tenant that today serves a host outside the pattern needs an extra
  hostname from the platform, or a DNS change.

## Alternatives

- **Free hostnames, checked at admission.** Rejected: a listener hostname is
  the gateway's own rule; admission is a second check, not the first.
- **One shared host with path prefixes per tenant.** Rejected for this
  extension: the shared entry point is the Service Mesh extension's platform
  ingress.
