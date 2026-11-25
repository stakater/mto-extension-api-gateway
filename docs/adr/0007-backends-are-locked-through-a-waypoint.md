# ADR-0007: A backend is locked to its tenant gateway through a waypoint; its team can turn the lock off

- **Status:** Proposed
- **Date:** 2026-11-16 (rewritten on 2026-11-25; the first version locked the
  backend pod at L4 with no waypoint, see Alternatives)

## Context

The gateway's checks mean nothing if a caller inside the cluster can call the
backend directly with its own `x-sub` and `x-roles` headers.

The per-API gateways we replace let each team choose, per API:

1. **A lock:** a waypoint in the backend's namespace (the namespace label
   `istio.io/use-waypoint`) and an L7 `ALLOW` on the backend Service: the
   health and metrics paths for anyone, every other path only for the
   gateway's identity. Ten of the twelve values files we studied use it.
1. **No lock,** for a backend in a shared namespace or outside the mesh; the
   backend must then check the caller itself. Two files use it.

In ambient mode an L7 rule needs a waypoint (M4). A waypoint sees traffic
addressed to the Service. Traffic to a pod's IP, and traffic from outside the
mesh, doesn't pass it (M21). The ingress gateway's own traffic skips the
destination waypoint by default (M4), so the lock never stands in the
gateway's way.

The first version of this ADR locked the pod itself, at L4, with no waypoint.
That also stops calls to a pod's IP, but it refuses monitoring and other
scrapers on the API's port, which work today. The per-API gateways serve
production, and an API must move with nothing broken (docs/migration.md).

## Decision

- **The lock follows today's pattern: a waypoint and an L7 rule.** For every
  backend Service of an API (every `backendRef`, mirrors included), the
  tenant's child renders, in the route's namespace:
    1. the waypoint `api-gateway-waypoint` (class `istio-waypoint`), one per
       namespace, autoscaled with platform values (default 3 to 5 pods, as
       today);
    1. an `AuthorizationPolicy` on the backend Service, enforced by the
       waypoint: **`DENY`** a request to any path but the open paths, from any
       identity but the tenant gateway's service account. This is today's
       behaviour; written as a `DENY`, another policy can't widen it.
- **Open paths are a platform value** (`backendLock.publicPaths`, default
  today's list: `/metrics`, `/health`, `/health/live`, `/health/ready`,
  `/healthz`), exact paths, never a pattern: `/actuator/*` would also open
  `/actuator/env`.
- **The backend's namespace must use a waypoint:** the label
  `istio.io/use-waypoint`, set through the Multi-Tenant Operator `Tenant`. The
  extension doesn't label namespaces or Services. Without the label, the
  policy is not enforced, so the API fails closed: no allowed-API rule, and
  its status says why.
- **The team can turn the lock off** for its API with the `api` instance's
  `backendLock: "off"` (default `"on"`, ADR-0005), as today's
  `allowDirectBackendAccess`. The backend must then check the caller itself
  and must not take the headers as proof. The platform can stop this for a
  tenant (`backendLock.lockedTenants`); a refused `"off"` keeps the lock, and
  the API's status says why. The tenant's status lists every API without a
  lock.
- **Fail closed when the lock is on and can't work:** a Service with no
  selector, an `ExternalName` that the extension didn't render (ADR-0014),
  or a namespace outside the mesh or
  without a waypoint gets no allowed-API rule.
- **During migration** the platform can add the old gateway's identity to an
  API's lock (`migration.oldGateways`), so both gateways pass while they run
  side by side (docs/migration.md).
- The trust domain in the gateway's principal is a platform value (default
  `cluster.local`).

## Consequences

- A call through the Service from a mesh workload that isn't the gateway gets
  `403` from the waypoint (observed on kind); the health and metrics paths stay open, as today.
- **Only mesh callers that use the Service pass the waypoint, as today.** A
  pod outside the mesh, calling the Service or a pod's IP, and a mesh pod
  calling a pod's IP, reach the backend directly and can set their own
  headers (observed on kind, M21). This is a known limit (design §12). STRICT
  mTLS on the backend pods refuses every caller outside the mesh, `/metrics`
  included (observed); an L4 lock on the pod (the first version of this ADR)
  also stops mesh pods on the pod's IP. Both cost scrapers on the API's port
  and stay open choices.
- More pods than the first version: one waypoint per backend namespace with a
  locked API, as today.
- With the lock off, any caller in the cluster can skip the gateway for that
  API. The status shows it, and the platform can lock the tenant.
- The lock trusts the gateway's service account; admission refuses pods that
  run as it (ADR-0008).
- Other internal callers of the API's paths are refused; naming them is story
  G.17. A backend outside the cluster has no lock (ADR-0014).

## Alternatives

- **An L4 `DENY` on the pod, enforced by ztunnel, with no waypoint (the first
  version).** Not chosen: it also refuses monitoring and scrapers on the API's
  port, which work today, so a production move could break them. It needs no
  waypoint pods and also stops calls to a pod's IP; it stays an option for
  backends whose metrics are on another port.
- **Today's `ALLOW` form.** Rejected: the same behaviour, but another `ALLOW`
  on the Service widens it.
- **No team switch.** Rejected: a backend in a shared namespace or outside
  the mesh couldn't move; two such APIs exist today.
- **A `NetworkPolicy` only.** Rejected: an L3 rule allows by pod and namespace
  labels, not by mTLS identity; kept as the platform's own layer.
