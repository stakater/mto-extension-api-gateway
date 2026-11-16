# ADR-0002: Security configuration is baked into the Template, never a parameter

- **Status:** Proposed
- **Date:** 2026-11-16

## Context

In the copy-the-chart model, the security-critical settings are plain switches
in a values file a team edits: `auth.enabled`, `allowGatewayAccessOnly`,
`rateLimit.enabled`, and a free-text allowed-consumer string. One wrong value
silently ships an open API; in the reference cluster a gateway runs today with
its token check off and nothing flags it. A `RequestAuthentication` without a
matching, token-requiring `AuthorizationPolicy` is itself an open API (**A1**).

## Decision

The `api-gateway` Template renders, **always and with no parameter to disable**:
a `RequestAuthentication` **and** a token-requiring consumer `AuthorizationPolicy`
(§4, §5); the strip of caller `x-sub`/`x-roles` before the gateway sets its own
(**A4**); the `gw-only` `AuthorizationPolicy` in the backend namespace (**M2**);
mTLS to the backend through the waypoint (**M1**); and the rate-limit hook (§8).
The values schema exposes **only** the API-shaped parameters in design §5; a
`TemplateInstance` that sets `auth*`, `allowedApis`, `allowGatewayAccessOnly` or
`rateLimit*` is rejected.

## Consequences

- A team cannot ship an unauthenticated or open-backend API, by construction.
  This is the extension's primary value (`vision.md`).
- Security is uniform across every gateway: one configuration to audit, no
  per-gateway exceptions.
- Changing the security posture means changing the Template (a platform act,
  reviewed), not a team's values — slower, deliberately.
- The issuer, audiences and rate-limit service are install-time values (§10),
  the same for every gateway on a cluster.

## Alternatives

- **Secure defaults, overridable.** Rejected: an override is exactly the switch
  that is flipped today.
- **A policy that audits gateways after the fact.** Rejected: detection after an
  open API is live is worse than prevention; and it's a second mechanism.
- **Admission that validates team-written gateways.** Rejected as the primary
  mechanism: it re-implements the chart as policy; the Template already is the
  gate. (Admission still backs ADR-0006 against hand-written gateways.)
