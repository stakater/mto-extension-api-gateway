# ADR-0015: Staged upgrades with two template generations, and no downtime

- **Status:** Proposed
- **Date:** 2026-11-25

## Context

The extension renders every tenant's gateway and policy from Templates in one
bootstrap chart (ADR-0001). With one version of each Template, a chart upgrade
reaches every tenant and every API at the same moment, because Template
Operator re-renders everything that uses a changed Template (T3). A bug in a
new version then hits everyone. Template Operator has no staged rollout of its
own (issue #8).

A tenant's own change already stays inside that tenant: each tenant has its
own child (ADR-0013). The gateways serve production, so an upgrade must also
cause no downtime.

## Decision

- **Template generations.** Every Template the chart publishes belongs to a
  generation: `g1`, `g2`, `g3` and so on. Any change to a Template goes into
  the next generation; a published generation never changes in place.
- **At most two generations in a chart release:** the current one and the next
  one. The first release has `g1` only. A release that adds a generation drops
  the oldest one:

```text
1.0:  [g1]
1.1:  [g1  g2]      canary on g2, then everyone on g2
1.2:      [g2  g3]  canary on g3, then everyone on g3
```

- **The platform chooses the generation,** in the bootstrap values:

```yaml
rollout:
  default: g1                # every tenant and API
  canary:
    tenants: [team-x]        # all of team-x's objects on the next generation
    apis: [team-a.orders]    # only this API's own objects on the next generation
```

- **How each Template follows it:**
    - The parent emits each tenant's child from the child Template of that
      tenant's generation (`api-gateway-policy-g2`). Tenant-wide objects (the
      token check, the filters, telemetry) follow the tenant's generation.
    - The team-facing Templates `api-gateway` and `api` keep their names,
      because teams reference them. The parent gives them each tenant's and
      each API's generation as a `disableOverride` parameter, and they render
      that generation's form.
    - An API's own objects (its route, its rule, its lock, its rate limit
      entry) follow the API's generation, so one API can move before the rest
      of its tenant. So that this works, every Template in a release can
      render the per-API objects of both generations the release holds: the
      tenant's child renders each API's objects in that API's generation,
      inside its own tenant-wide objects (the rate limit filter holds each
      API's entry in the API's generation). A generation's output never
      changes; a release only adds the next generation's forms.
- **Promote and roll back with values only.** When the canary works, the
  platform sets `rollout.default` to the next generation. To roll back, it
  takes a tenant or an API out of the canary list. Neither needs a new chart
  release.
- **A generation in use can't be dropped.** The chart's values schema allows
  only the generations the release contains, so an upgrade to a release
  without `g1` is refused while `rollout.default` or a canary entry still
  names `g1`, and the error names it.
- **No downtime:**
    1. Object names stay the same across generations, so a switch updates
       objects in place; nothing is deleted and created again. A renamed
       object takes two generations: the next one adds the new name, the one
       after removes the old.
    1. Gateway and waypoint pods restart one at a time: at least two pods, a
       disruption budget, and Envoy drains open connections before a pod
       stops.
    1. A mesh (Istio) upgrade uses Istio revisions: the platform moves one
       tenant's gateway to the new revision first, with the `istio.io/rev`
       label rendered from a platform value (`gateway.meshRevision`), and
       moves it back the same way (M22).
    1. The rate limit service restarts one pod at a time (one extra pod
       first, none unavailable). A change of the limits creates a new
       `ConfigMap`, whose name carries a hash of its content, and so rolls
       the pods, as today's chart does, so the change applies at once,
       not when the kubelet next syncs the file (S1). If the service is ever
       unavailable, traffic
       keeps flowing when the platform chose fail open
       (`rateLimit.failureModeAllow`, decided in G.5).
    1. The design stays closed in any apply order (ADR-0004), so a switch
       never opens a gap.

## Consequences

- A new version reaches one API or one tenant first, and everyone only when
  the platform promotes it. A chart release alone changes no tenant.
- The chart carries two forms of every Template during a rollout, and the
  render tests run both. This is more code, limited by the rule of two.
- Every Template change, even a small fix, is staged as a new generation.
  Parts that are not Templates (the rate limit service's image) are upgraded
  with a rolling update.
- A canary API shares its tenant's gateway, filters and token check with the
  APIs on the current generation; only its own objects differ. A change to a
  tenant-wide object is staged per tenant.
- G.28 measures zero dropped requests for every kind of switch.

## Alternatives

- **One generation, all tenants at once (the first version).** Rejected: one
  bug reaches every tenant.
- **Staging only between clusters (test first, then production).** Kept as the
  first stage, but not enough: inside the production cluster every tenant
  would still change at once.
- **Teams pick the Template version in their `TemplateInstance`.** Rejected:
  every team would have to change its instances for each upgrade, and the
  platform would lose control of the rollout.
- **Template Operator's sync mode `off` to freeze tenants.** Rejected: frozen
  tenants never get fixes, and freezing is all or nothing, not a promotion.
- **More than two generations at a time.** Rejected: the chart and its tests
  would grow with every release.
