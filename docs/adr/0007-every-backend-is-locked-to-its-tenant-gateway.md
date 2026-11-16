# ADR-0007: Every backend is locked to its tenant gateway

- **Status:** Proposed
- **Date:** 2026-11-16

## Context

The gateway's checks mean nothing if a caller inside the cluster can call the
backend Service directly. Today each team renders an Istio
`AuthorizationPolicy` in the application namespace that allows only the
gateway's identity, and a waypoint per application namespace. In ambient mode,
ztunnel gives every workload an mTLS identity and enforces L4 authorization
(source principals) without a waypoint; L7 rules need a waypoint (M4).

## Decision

- **For every backend Service of an API** (every `backendRef`, mirrors
  included), the per-tenant chart renders an Istio `AuthorizationPolicy` in
  the route's namespace: **`DENY`** on the Service's target ports from any
  identity but the tenant gateway's service account (`notPrincipals`). It
  selects the backend's pods by the Service's selector.
- **`DENY`, not `ALLOW`.** `ALLOW` policies add up: a tenant's own `ALLOW`
  on the same pods would widen the lock. A `DENY` can't be widened.
- **Fail closed.** A backend that can't be locked — no selector, an
  `ExternalName`, another kind, or a namespace outside the mesh — gets no
  route-level `AuthPolicy`, so the route keeps the default deny and serves
  nothing. A pod can't opt out of the mesh: admission refuses
  `istio.io/dataplane-mode` on tenant pods (M8, ADR-0008).
- **L4 only, enforced by ztunnel.** No waypoint is required. A team that runs a
  waypoint for its own reasons keeps it; the extension doesn't create one.
- The rule is not optional and has no switch (ADR-0004).

## Consequences

- A call from another pod, or from outside the mesh, straight to the
  backend's API port is refused (AC-ISO-5, M9).
- Fewer pods: no waypoint per application namespace for this purpose.
- The backend's namespace must be in the mesh (ambient). The extension reports
  a route whose namespace isn't (design §8), and the gateway can't reach a
  locked backend outside the mesh.
- Other callers of the same ports (for example, a batch job in the tenant)
  are refused too, and a tenant can't allow them. Naming allowed internal
  callers is story G.17. Ports the Service doesn't target (for example a
  separate metrics port) are not locked (Q5).
- Backends outside the cluster can't be published in v1 (G.16).

## Alternatives

- **An `ALLOW` policy for the gateway (today).** Rejected: any other `ALLOW`
  on the same pods widens it.
- **A waypoint per namespace and an L7 policy.** Rejected as the default: more
  pods, and L4 identity is enough to say "only the gateway".
- **A `NetworkPolicy` only.** Rejected: an L3 rule allows by pod and namespace
  labels, not by mTLS identity; kept as the platform's own layer.
- **No lock.** Rejected: the gateway is then optional.
