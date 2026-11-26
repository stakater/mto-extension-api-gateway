# ADR-0009: A tenant serves only the hosts and paths it is granted

- **Status:** Proposed
- **Date:** 2026-11-16 (rewritten on 2026-11-19; the first version gave every
  host to one tenant and rejected a shared host, see Alternatives; internal
  hosts added on 2026-11-26)

## Context

Two tenants must never serve the same API address, and a tenant must not take
over a host or path that belongs to another tenant or to the platform. A
Gateway API listener with a `hostname` only accepts routes whose hostnames
intersect it (A3).

The per-API gateways we replace serve one front-door host for all teams:
the path selects the API, and the OpenShift router sends each path to its
own gateway with one OpenShift `Route` per path. Those gateways run in
production. Moving an API must not change its address for its callers
(AC-MIG-1), so tenants must be able to share a host, split by path.

To split a host by path, the router must read the path, so it terminates TLS
and encrypts again to the gateway (R1). That second connection is reported to
carry no TLS server name (SNI), so a listener with a hostname refuses it
(R4). The router trusts OpenShift's service CA for that connection (R3).
Routes of one host in several namespaces need the router's
`InterNamespaceAllowed` setting (R2), and that setting lets any namespace
claim a free path of the host.

## Decision

- **Each tenant gateway's listener `tenant` has the hostname
  `*.<tenant>.<base domain>`**, with the base domain a platform value
  (`apis.example.com`).
- **Extra hostnames:** the platform may grant a tenant extra hostnames
  (bootstrap value, per tenant). Each gets its own listener on that tenant's
  gateway. The parent refuses an extra hostname that overlaps the base domain
  (reserved for tenant names, including tenants created later), another
  tenant's extra hostname (a wildcard intersection, not an equality), or a
  shared host.
- **Shared hosts:** the platform may grant tenants path prefixes on a shared
  host (bootstrap value `gateway.sharedHosts`):

```yaml
gateway:
  sharedHosts:
    - host: front.example.com
      paths:
        team-a: [/orders, /payments]
        team-b: [/billing]
```

The parent refuses a shared host under the base domain or equal to an extra
hostname, a prefix that is not a valid path (the `path` rules of ADR-0005),
and two prefixes of different tenants on one host where one equals, or is a
segment prefix of, the other. Refusals are listed in the skipped-tenants
ConfigMap.

- **The entry point for a shared host:** the tenant's gateway request renders,
  in the gateway's namespace, one reencrypt OpenShift `Route` per granted
  prefix (host, path, the gateway's Service). The gateway gets one more
  listener, `entry`, with no hostname and a certificate from OpenShift's
  service CA, for the router's connection.
- **An API on a shared host** must have its `path` under one of its tenant's
  prefixes on that host; the `api` template refuses any other (ADR-0005).
- **Internal hosts:** the platform may grant a tenant host names on the
  cluster router's own domain (bootstrap values `gateway.internalDomain` and
  `gateway.internalHosts`, per tenant), as today's internal host of each API
  (`<gateway>-<namespace>.<router domain>`):

```yaml
gateway:
  internalDomain: apps.cluster.example.com
  internalHosts:
    team-a: [orders-team-a.apps.cluster.example.com]
```

Each is one DNS label under `internalDomain`, so the router's own wildcard
certificate covers it. The parent refuses an internal host outside that
domain, one granted to two tenants, and one equal to an extra hostname or a
shared host. The tenant's gateway request renders one reencrypt OpenShift
`Route` per internal host, with no path, to the gateway's Service, as
today; the gateway gets the `entry` listener. An API also answers on an
internal host when its `api` instance names it in `internalHost`; APIs
share an internal host by path, as any host (ADR-0005).

- **Nobody else claims these hosts:** admission refuses a tenant's OpenShift
  `Route` for a host under the base domain, for a shared host, or for a
  granted internal host (ADR-0008).
- TLS for the tenant's own and extra hostnames: one certificate per listener,
  from a platform-named issuer (Q10). G.0 measures how the entry point reaches
  those listeners, and G.18 renders it.

## Consequences

- An API keeps its address and path when it moves from a per-API gateway to
  its tenant's gateway.
- The platform owns the path map of a shared host; a new prefix for a tenant
  is a platform change.
- The `entry` listener accepts any host. For it, the host and path checks are
  the `api` template (only granted hosts and prefixes), the router (only
  granted hosts and paths reach the gateway), and the API rule (host and
  path, ADR-0005). This holds because tenants can't write routes (ADR-0008).
- The router matches a path as a string prefix, longest first (R1): a
  request for `/ordersx` reaches `team-a`'s gateway and gets `404` there.
- `InterNamespaceAllowed` applies to the whole router, so admission is the
  guard for every shared host and the base domain (G.8, G.23).
- Host names under the base domain still show who owns an API; a shared host
  does not.
- An API keeps today's internal host when it moves: the platform grants the
  old name to the tenant. The old gateway's `Route` holds that host until it
  is deleted, and the router then admits the tenant's `Route` (R5); that
  switch is a step of the migration runbook.
- The `entry` listener exists when a tenant has a shared-host prefix or an
  internal host.

## Alternatives

- **Every host belongs to one tenant (the first version).** Rejected: every
  caller of a moved API would have to change its address, in production.
- **Passthrough `Route`s for a shared host.** Rejected: the router can't read
  the path of a passthrough connection (R1), so it can't split the host.
- **A platform gateway in front of the tenant gateways** (for example the
  Service Mesh extension's ingress), splitting the shared host by path.
  Rejected for v1: one more hop and one more component in every request's
  path, while the router already splits by path today.
- **Free hostnames, checked at admission.** Rejected: the platform, not the
  tenant, decides which host and path a tenant serves.
- **An internal host derived from the API's name** (`<api>-<tenant>.<router
  domain>`), with no grant. Not chosen: a moved API would change its internal
  host, so its internal callers would have to change.
