# ADR-0003: Consumer authorization scope is derived from the API name, never free text

- **Status:** Proposed
- **Date:** 2026-11-16

## Context

A gateway authorizes a caller by requiring a claim in the token to match the
APIs the caller may use (**A2**). In the copy-the-chart model this match value
is a hand-typed string in the values file; nothing stops `*`, a typo, or a
scope that overlaps another API. A wrong string either opens the gateway to any
caller or breaks it.

## Decision

The consumer `AuthorizationPolicy` requires the token's consumer claim (the
install-time `consumerClaim`, e.g. `allowed_apis`) to match
`api-<apiName>-consumer-*`, **derived from the `apiName` parameter**. There is
no parameter for the match value. `apiName` is constrained to
`^[a-z][a-z0-9-]*$`, so the derived scope is well-formed and namespaced to the
API.

## Consequences

- A gateway can authorize callers only for its **own** API; `*` is not
  expressible.
- The consumer role name the identity provider must grant is predictable
  (`api-<apiName>-consumer-*`), which the later Keycloak-extension seam
  (ADR-0009) can derive too — a new API becomes one coherent object end to end.
- The claim name is a cluster-wide install value, not a per-gateway choice, so
  every gateway authorizes on the same claim.

## Alternatives

- **A free-text `allowedApis` parameter (status quo).** Rejected: it's the
  footgun.
- **A list of allowed scopes per gateway.** Rejected for v1: more than one
  scope per gateway is not needed when the unit is one gateway per API
  (ADR-0004); revisit if a real case appears.
