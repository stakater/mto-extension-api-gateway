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
  The parent refuses to render a hostname granted to two tenants and lists the
  conflict (design §7).
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
