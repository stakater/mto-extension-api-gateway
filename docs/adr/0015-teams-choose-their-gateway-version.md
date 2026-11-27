# ADR-0015: Teams choose their gateway version, with semantic versions and no downtime

- **Status:** Proposed
- **Date:** 2026-11-25 (changed on 2026-11-27: each team chooses its version;
  the platform no longer moves tenants)

## Context

The extension renders every tenant's gateway and policy from Templates in one
bootstrap chart (ADR-0001). With one version of each Template, a chart upgrade
reaches every tenant and every API at the same moment, because Template
Operator re-renders everything that uses a changed Template (T3). A bug in a
new version then hits everyone. Template Operator has no staged rollout of its
own (issue #8).

The gateways serve production, so an upgrade must cause no downtime. The
teams also asked for control: they want to test a new version before it
reaches their gateway, and to choose when that happens. Some teams have little
time to test, so they must not be moved by someone else on a version they
never tried.

## Decision

- **Semantic versions.** The extension's templates have a version
  `MAJOR.MINOR.PATCH`, as Helm charts and Kubernetes use:
    - **patch** (`1.0.0` → `1.0.1`): bug fixes and security fixes only;
      nothing that callers or teams see changes;
    - **minor** (`1.0.1` → `1.1.0`): new features that break nothing, for
      example a new optional parameter;
    - **major** (`1.1.0` → `2.0.0`): a change that callers or teams must
      adapt to, for example a status code or a removed parameter; the release
      notes list each one.
- **The team chooses the version** with the required parameter `version` on
  its gateway request (ADR-0002):

```yaml
spec:
  templateRef: { name: api-gateway, namespace: mto-api-gateways }
  parameters:
    - { name: version, value: "1.1.0" }   # required
```

- **One version per tenant.** The tenant's gateway, its policy and all its
  APIs use the version of the owner request. The parent passes it to the
  `api` Template and to the tenant's child as a `disableOverride` parameter.
  An `api` request has no version of its own.
- **A team moves with one line,** on the test cluster first and then in
  production, and moves back the same way. Each cluster has its own requests,
  so the test cluster is the team's trial run. Two environments of one team
  on one cluster need two tenants for this.
- **The platform never moves a team.** Installing a release changes no
  tenant. Every change of version, also a patch, is the team's own change.
- **How many versions stay is configurable.** Each release ships the
  templates of the versions in Stakater's support window, which its release
  notes name; the design fixes no number. The platform chooses which of them
  teams may use, with the value `versions.allowed` (default: every version
  the release ships). It can allow fewer, for example to stop a version with a
  security issue. A release always ships the newest version of the release
  before it, so a team can always move to a newer version that is already
  installed.
- **Guards:**
    1. Admission refuses a gateway request with no `version`, or with a
       version not in `versions.allowed`, so a wrong version never reaches
       Template Operator and never removes a gateway.
    1. The live preflight refuses an install, or a change of
       `versions.allowed`, that removes a version a gateway request still
       names, and the error names the tenant.
    1. The parent renders the ConfigMap `mto-api-gateway-versions` in
       `mto-api-gateways`: each tenant and its version. A tenant's status
       ConfigMap warns when its version is the oldest allowed one.
- **Security fixes** come as a patch release. The platform tells the teams on
  the affected versions, with a deadline that the platform sets.
- **What changes with the install, for every tenant:** the parts that are not
  per tenant (the token floor and the default deny, the rate limit service,
  the admission policies). They must work with every version the release
  ships; the render tests and the live suite check each version.
- **No downtime:**
    1. Object names stay the same across versions, so a move updates objects
       in place; nothing is deleted and created again. A renamed object takes
       two versions: the first adds the new name, the next removes the old.
    1. Gateway and waypoint pods restart one at a time: at least two pods, a
       disruption budget, and Envoy drains open connections before a pod
       stops.
    1. A mesh (Istio) upgrade stays a platform task. It uses Istio revisions:
       the platform moves one tenant's gateway to the new revision first, with
       the `istio.io/rev` label rendered from a platform value
       (`gateway.meshRevision`; the `Istio` resource needs its revision-based
       update strategy), and moves it back the same way (M22).
    1. The rate limit service restarts one pod at a time (one extra pod
       first, none unavailable). A change of the limits creates a new
       `ConfigMap`, whose name carries a hash of its content, and so rolls
       the pods, as today's chart does, so the change applies at once,
       not when the kubelet next syncs the file (S1). If the service is ever
       unavailable, traffic keeps flowing when the platform chose fail open
       (`rateLimit.failureModeAllow`, default `true`, as today).
    1. The design stays closed in any apply order (ADR-0004), so a move
       never opens a gap.

## Consequences

- Teams decide when their gateway changes, and try each version on the test
  cluster first. An install alone changes no tenant.
- Every upgrade, also a patch, is a one-line change by the team, per tenant
  and per cluster.
- A team that doesn't move blocks the release that drops its version; the
  platform must ask it to move. A team on a version with a known security
  issue stays exposed until it moves; the deadline limits this.
- All APIs of a tenant move and roll back together, and one API that is not
  ready holds back its tenant. Such an API can move to its own tenant, or wait
  for a second gateway per tenant (G.12).
- The chart carries the templates of every version in the support window,
  and the render tests run each one. A longer window gives teams more time
  and Stakater more code to maintain and test; Stakater sets it per release,
  and the platform can narrow it.
- G.28 measures zero dropped requests for each move.

## Alternatives

- **The platform moves tenants with `rollout.default` and canary lists** (the
  first form of this decision, 2026-11-25). Rejected on 2026-11-27: a tenant
  would move without its own test.
- **An optional version, with a platform default.** Rejected: a team that
  doesn't set it would move untested when the default changes.
- **Patches applied automatically inside a minor version.** Rejected: teams
  want to test every change; a patch is a one-line move.
- **A version per API.** Rejected: every API version would have to work with
  every gateway version. The team's canary is its test cluster.
- **A Template per version, chosen with `templateRef`.** Rejected: every `api`
  request would have to change with each move.
- **Template Operator's sync mode `off` to freeze tenants.** Rejected: frozen
  tenants never get fixes, and freezing is all or nothing.
- **A fixed number of versions in the design.** Rejected: the right number
  depends on how fast the teams move. Stakater sets the support window per
  release, and the platform narrows it with `versions.allowed`.
