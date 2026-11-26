# ADR-0006: The allowed-API rule is derived, tenant-qualified and closed

- **Status:** Proposed
- **Date:** 2026-11-16 (on 2026-11-19, old role names accepted during
  migration by a platform mapping)

## Context

Today a caller may use an API if its token's allowed-APIs claim contains a
value matching a free-text pattern in the team's values, such as
`api-<team>-<api>-consumer-*`. Nothing stops `api-*` or `*`. And with `-`
joining DNS labels, names collide across tenants: tenant `team` with API
`a-orders` and tenant `team-a` with API `orders` both give
`api-team-a-orders`. An Istio `AuthorizationPolicy` condition on a token
claim matches any value of a list claim, exactly or by prefix (M10).

## Decision

- **The rule is derived:** the caller's allowed-APIs claim must contain a value
  that is exactly `api.<tenant>.<api>`, or starts with `api.<tenant>.<api>.`
  (for finer roles such as `api.team-a.orders.read`). The segment after the
  API name is closed by `.`, so `api.team-a.orders` never matches
  `api.team-a.orders2`. In Istio's condition: the values
  `api.team-a.orders` (exact) and `api.team-a.orders.*` (prefix that ends in
  the dot).
- **`.` joins the parts.** Tenant and API names are DNS labels and contain no
  dot, so a value names exactly one tenant and one API.
- The platform may change the prefix (`api`) and the claim name, install-wide.
  It can't make the rule a wildcard: a render check fails on any pattern that
  doesn't contain both the tenant and the API name, closed.
- **Old role names during migration.** So that callers' tokens don't change
  when an API moves (G.9), the platform maps the API to its old role name
  (`migration.legacyRoles`, for example `team-a.orders: api-orders-consumer`).
  The API's rule then also accepts `<old>-<tier>` for each tier the platform
  defines, as exact values, never a wildcard. The parent refuses an old name
  mapped to APIs of two tenants, or one that is the start of another mapped
  old name. A team can't set it. Renaming the roles in the identity provider
  later removes the mapping.

## Consequences

- No hand-written pattern exists, so none can be too wide.
- A caller's role names the tenant: a role for `team-b`'s `orders` never opens
  `team-a`'s `orders`.
- RHBK roles must follow the format. Creating them stays with the platform team
  for now (non-goal; G.11 automates it).

## Alternatives

- **The pattern as a parameter.** Rejected: the failure it causes (a pattern
  one character too wide) is the one we want to rule out.
- **`-` as separator, matching today's role names.** Rejected: names collide
  across tenants. Old names are accepted only through the platform's
  migration mapping, as exact values.
- **Rename every role in the identity provider before the move.** Rejected for
  the move: every caller's token would change, and a realm import gives new
  signing keys (design §12). It can follow later.
- **One role per tenant.** Rejected: every caller of one API could call all of
  the tenant's APIs.
