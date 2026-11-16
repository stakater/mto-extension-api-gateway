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

- **For every API, the per-tenant chart renders an Istio `AuthorizationPolicy`
  in the route's namespace** that allows the backend's pods to be called only
  by the tenant gateway's service account (and the platform's monitoring, set
  by the platform). It selects the backend's pods by the Service's selector.
- **L4 only, enforced by ztunnel.** No waypoint is required. A team that runs a
  waypoint for its own reasons keeps it; the extension doesn't create one.
- The rule is not optional and has no switch (ADR-0004).

## Consequences

- A call from another pod straight to the backend is refused by the mesh
  (AC-ISO-5).
- Fewer pods: no waypoint per application namespace for this purpose.
- The backend's namespace must be in the mesh (ambient). The extension reports
  a route whose namespace isn't (design §8), and the gateway can't reach a
  locked backend outside the mesh.
- Other in-mesh callers of the same pods (for example, a batch job in the
  tenant) need their own allow rule. The lock only covers the pods behind
  annotated routes (Q5).

## Alternatives

- **A waypoint per namespace and an L7 policy (today).** Rejected as the
  default: more pods, and L4 identity is enough to say "only the gateway".
- **A `NetworkPolicy` only.** Rejected: an L3 rule allows by pod and namespace
  labels, not by mTLS identity; kept as the platform's own layer.
- **No lock.** Rejected: the gateway is then optional.
