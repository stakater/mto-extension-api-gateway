# ADR-0014: An API's backend can be outside the cluster, as in today's chart

- **Status:** Proposed
- **Date:** 2026-11-25

## Context

An API team needs to publish an API whose backend runs outside the cluster:
the tenant gateway checks the caller, and then calls a host on another
network.

The per-API gateways we replace support this. In one of the twelve values
files we studied, the team sets the external host, its port, the path the
host expects, and how the gateway speaks TLS to it. The chart then renders,
in the gateway's namespace:

| Object | Purpose |
|---|---|
| `ServiceEntry` (`MESH_EXTERNAL`, DNS) | registers the host in the mesh, so the gateway may call it, also when the mesh allows only registered hosts |
| `DestinationRule` | the gateway's TLS to the host: `SIMPLE` (server certificate checked with a CA), `MUTUAL` (also a client certificate) or `DISABLE` (plain HTTP); the SNI; the Secret with the CA, and with the client certificate for `MUTUAL` |
| `ExternalName` Service | a local name that the route's `backendRef` points to |

The route rewrites the `Host` header to the external host and the path to the
one the host expects. The caller's token is not forwarded; the host gets the
headers set from the token. The backend lock doesn't apply: the host is
outside the mesh.

ADR-0005 and ADR-0007 first refused such a backend (an `ExternalName` was
invalid, story G.16 later). The per-API gateways serve production, and an API
must move with nothing broken (docs/migration.md).

## Decision

- **An API's backend can be a host outside the cluster, with today's design.**
  The `api` instance sets `externalHost` instead of `service` (exactly one of
  the two), and:

| Parameter | Required | Default | Checks |
|---|---|---|---|
| `externalHost` | instead of `service` | — | a lowercase host name, no wildcard, not in the cluster's own domain |
| `port` | yes | — | 1 to 65535 |
| `rewrite` | no | no rewrite | the path the host expects (ADR-0005) |
| `tls` | no | `SIMPLE` | `SIMPLE`, `MUTUAL` or `DISABLE` |
| `tlsSni` | no | `externalHost` | a host name |
| `tlsSecret` | for `MUTUAL`; for `SIMPLE` when the host's CA is not a public one | — | a Secret in the gateway's namespace with `ca.crt`, and `tls.crt` and `tls.key` for `MUTUAL` |

- **What is rendered,** as in today's chart:
    1. by the `api` instance, in its own namespace: the `ExternalName` Service
       `api.<api>.external`, and the route to it, which rewrites the `Host`
       header to `externalHost`;
    1. by the tenant's child, in the gateway's namespace, where the gateway
       calls from: the `ServiceEntry` and the `DestinationRule`
       `api.<api>.external`.
- **Everything else is as for any API:** the token check, the API rule on host
  and path, the issuers, the rate limit and the team settings.
- **No backend lock and no token forwarding,** as today. The status lists the
  API as `external`.
- **Only the extension's own `ExternalName` Service is accepted** as an API's
  backend; one written by hand is still invalid (ADR-0007).

## Consequences

- Every API of the per-API gateways can move, including the one with an
  external backend.
- The external host gets `x-sub`, `x-roles` and the team's claim headers, not
  the token. Anything that can reach the host on its network can send the
  same headers; the host must protect itself, as today (for example by
  accepting only the gateway's client certificate, `MUTUAL`).
- A team can point its API at any host, as today. A platform list of allowed
  hosts per tenant is a later option (Alternatives).
- With `DISABLE`, the call leaves the cluster in plain text, as today.
- The CA and client certificate Secret must be in the gateway's namespace,
  where the gateway reads it.

## Alternatives

- **Refuse backends outside the cluster (the first version, story G.16).**
  Rejected: the API that uses one today couldn't move.
- **A platform list of allowed external hosts per tenant.** Not chosen for
  now, to keep today's design; it stops a team from sending callers' requests
  to any host, and can be added as a platform value later.
- **Forward the caller's token to the external host,** so it checks the caller
  itself. Not chosen for now, as today; a later option per API. Istio forwards
  the token for every route of a gateway, so the other APIs' routes would have
  to remove it.
- **Token exchange,** a new token for the host from the identity provider.
  Rejected for now: it needs a component outside Istio's policies.
