# ADR-0011: Connectivity Link is the tested policy controller; upstream Kuadrant is allowed

- **Status:** Rejected
- **Date:** 2026-11-17

**Rejected on 2026-11-17**, with the rewrite of ADR-0003: the extension uses
no Kuadrant API for now, so which product runs it is not a decision to take.
It is kept as the record of the comparison, for when ADR-0003's revisit
conditions are met.

## Context

Raised in the review of PR #1 (2026-11-16).

The first version of ADR-0003 chose the Kuadrant policy API (`kuadrant.io/v1` `AuthPolicy` and
`RateLimitPolicy`). Two products implement it:

| | Upstream Kuadrant | Red Hat Connectivity Link |
|---|---|---|
| What it is | the open source project (Apache-2.0) | Red Hat's supported build of Kuadrant; 1.4.x is built from kuadrant-operator v1.6.0 |
| Objects the extension renders | the same | the same |
| Support | community | Red Hat, on OpenShift 4.19–4.22 with Service Mesh 3.4 (K1) |
| Its own `EnvoyFilter`s on the gateway (K7) | maintained by the project; Red Hat's Service Mesh support documents no exception for them (Q14) | part of a supported product |
| Version against Service Mesh | the platform team owns the matrix | Red Hat's tested matrix |
| Subscription | none | a separate software subscription; we found no source that says another subscription includes it (K9) |

The extension renders the same objects for both. Which product runs them is a
choice of the cluster, like the choice of identity provider. Regulated
customers often require vendor support for every component in the
authentication path.

## Decision

- **The extension depends on the Kuadrant API, not on one product.** It
  renders only `kuadrant.io` objects; the preflight checks for the CRDs and a
  ready `Kuadrant` instance, not for a product name.
- **Connectivity Link, 1.4.1 or later, is the tested controller.** The
  acceptance suite runs on it, and the docs name it as the recommended
  prerequisite.
- **Upstream Kuadrant is allowed, at the version that matches the tested
  Connectivity Link build** (kuadrant-operator v1.6.0 for 1.4.x). The docs say
  plainly: the extension renders the same objects, but our acceptance suite
  does not run on that stack, and neither Red Hat nor Stakater supports it.
- The extension costs the same either way. The customer chooses.

## Consequences

- A customer without a Connectivity Link subscription can run the extension.
- We claim only what is tested. Upstream Kuadrant becomes a tested option
  only when the acceptance suite runs on it (story G.10), and only at the
  versions it ran on.
- A customer on upstream Kuadrant owns the version match with Service Mesh,
  and its upgrades.
- If upstream changes a field we use (the `merge` strategy, the fixed `when`,
  `response.success.filters`, `sectionName` targets), the two paths split.
  Q15 checks parity for each new version.

## Alternatives

- **Connectivity Link only.** Rejected: the objects are the same, and a
  customer that can't buy the subscription would lose the extension for a
  reason that is not technical.
- **Both equal, "either works".** Rejected for now: untested and unsupported
  in the authentication path; we would claim more than we tested.
- **The extension installs Kuadrant itself.** Rejected: installing
  prerequisites is a non-goal (vision), and it would make Stakater the support
  path for the authentication path.
