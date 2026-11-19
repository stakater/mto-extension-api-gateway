# ADR-0005: An API is a TemplateInstance, and its rule checks the host and the path

- **Status:** Proposed
- **Date:** 2026-11-16 (rewritten on 2026-11-19; the first version had the
  team write the `HTTPRoute` and gave each API its own hostnames, see
  Alternatives)

## Context

The first version of this ADR made an API a standard `HTTPRoute` that the
team writes, with one annotation, and gave each API its own hostnames. Two facts from the twelve
per-API values files of the pattern we see in practice change both parts:

1. **Teams set few route fields.** Each file renders one route with one rule.
   Teams set the public path (12 of 12), a path rewrite (10), an in-cluster
   Service and port (11), and an exact operation, path and method (2). One
   file has an external backend (G.16). No file uses header filters,
   timeouts, retries, weights, mirrors or a second rule.
1. **No team chose a host.** All APIs share one front-door host, and the path
   selects the API. With one gateway per tenant (ADR-0002), a tenant's APIs
   then share one host on one gateway. The first version refused that as a
   host conflict, so none of them was served.

The first version scoped the API rule by host because Istio can't attach a policy to a
route (M6). Istio allows a request when any `ALLOW` matches. With host-only
rules, a caller allowed one API matches its rule on every path of the host,
and so reaches the other APIs there. An `AuthorizationPolicy` can also match
the request's paths and methods (M16), and Gateway API matches a path prefix
segment by segment (A6).

Teams also expect to ask for everything the same way: with a
`TemplateInstance`, as for the gateway (ADR-0002). Template Operator can't
validate a parameter's value (T8), and a parameter's `valueFrom` reads with
the operator's own account, from any namespace (T9).

## Decision

- **An API is a `TemplateInstance` of the Template `api`.** The bootstrap
  parent publishes `api` next to `api-gateway` in `mto-api-gateways`, usable
  only from tenant namespaces, with the same platform parameters (the
  tenant of each namespace, the tenant's gateway, its hostnames), all
  `disableOverride`. The team creates one instance per API, in the backend's
  namespace. The instance's name is the API name: a DNS label, unique in the
  tenant; when two instances of a tenant use one name, the oldest keeps it.

```yaml
apiVersion: templates.v2.stakater.com/v2alpha1
kind: TemplateInstance
metadata:
  name: orders                      # the API name; the rule is api.team-a.orders
  namespace: team-a-dev             # the backend's namespace
spec:
  templateRef: { name: api, namespace: mto-api-gateways }
  parameters:
    - { name: host,    value: public.team-a.apis.example.com }
    - { name: path,    value: /orders/v2 }
    - { name: rewrite, value: /orders/v1 }
    - { name: service, value: orders }
    - { name: port,    value: "80" }
```

| Parameter | Required | Default | Checks |
|---|---|---|---|
| `host` | no | `<api>.<tenant>.<base domain>` | a lowercase host name, no wildcard; one of the tenant's hostnames, or a shared host when `path` is under one of the tenant's prefixes there (ADR-0009) |
| `path` | yes | — | starts with `/`; segments of letters, digits, `-`, `.`, `_`, `~`; no empty, `.` or `..` segment; no trailing `/`, except `/` alone |
| `rewrite` | no | no rewrite | as `path`; not with `operations` |
| `service` | yes | — | a DNS label: a `Service` in the instance's namespace |
| `port` | yes | — | 1 to 65535 |
| `operations` | no | every path under `path` | `METHOD /exact/path`, comma-separated, at most 10; each path under `path`; methods `GET`, `HEAD`, `POST`, `PUT`, `PATCH`, `DELETE`, `OPTIONS` |

- **The instance renders the route.** In its namespace, with `sync: strict`,
  it renders the `HTTPRoute` `api.<api>`: `parentRefs` to the tenant's
  gateway (a platform parameter), the host, and one rule. The rule matches
  `PathPrefix` `path`, or `Exact` path and method for each operation; it
  rewrites with `ReplacePrefixMatch` when `rewrite` is set; its `backendRefs`
  name the Service and port in the same namespace. The route carries the
  annotation `api-gateway.stakater.com/api: <api>`. The instance also renders
  the ConfigMap `api.<api>`: `status: ok` with the URL and the rule, or
  `status: refused` with the reason. An invalid parameter renders no route.
- **The API rule checks the host and the path.** The tenant's child
  (ADR-0013) renders the `ALLOW` `api.<api>` from the route: the route's
  host, and the paths `<path>` and `<path>/*` (no path condition when
  `path` is `/`), or one entry per operation with its exact path and method.

```yaml
rules:
  - from:
      - source: { requestPrincipals: ["https://sso.example.com/realms/apis/*"] }
    to:
      - operation:
          hosts: ["public.team-a.apis.example.com", "public.team-a.apis.example.com:*"]
          paths: ["/orders/v2", "/orders/v2/*"]
    when:
      - key: request.auth.claims[allowed_apis]
        values: ["api.team-a.orders", "api.team-a.orders.*"]
      - key: request.auth.claims[azp]
        values: ["*"]
```

- **APIs on one host must not overlap.** Two APIs overlap when they share a
  host and the `path` of one equals, or is a segment prefix of, the `path` of
  the other: `/orders` overlaps `/orders/v2`, not `/orders-v2`. Both fail closed and are
  listed under `path-conflicts`. Gateway API sends a request to the longest
  matching prefix, but Istio allows it when any rule matches, so an overlap
  would let a caller of `/orders` reach the API on `/orders/v2`. An attached route
  that is not an API and overlaps an API's host and path also stops that API.
- **Tenants write only `TemplateInstance`s.** Admission (ADR-0008, G.8)
  refuses, for tenant users: an `HTTPRoute` in a tenant namespace, and a
  `TemplateInstance` of `api` or `api-gateway` with a `valueFrom` parameter.

## Consequences

- A team asks for everything with one kind of object: one `api-gateway` per
  tenant, one `api` per API.
- The platform controls the shape of every route, so the child can derive an
  exact rule from it. The rule and the route come from the same object.
- A team gets only the route features that are parameters: one host, one
  path prefix or a list of exact operations, one rewrite, one backend. This
  covers every route in the twelve files except the external backend (G.16).
  Each new feature is a new parameter, with a story.
- Several APIs share one host on one tenant gateway, split by path. The v1
  limit "one API per hostname" is gone (ADR-0003, design §12).
- The rule depends on Istio's path matching. G.19 tests segment prefixes,
  path normalization (`//`, `/./`, `/../`, `%2F`), the query string, and that
  the rule sees the path before the rewrite (M16). The platform must not set
  Istio's path normalization to `NONE`.
- Two more admission checks (G.8). Until G.8, a hand-written route on an
  API's host and path stops that API: a fault inside one tenant, not access
  to another API.
- Several tenants share one front-door host when the platform grants each
  its path prefixes there (ADR-0009). An API on that host needs a path under
  its tenant's prefixes.
- The rate limit can't count per API by host. It needs the API name.
- Teams that keep routes in Git keep their `api` instances there instead.
- The route name `api.<api>` is a name teams don't use. G.19 tests that a
  render refuses a taken name (T4).

## Alternatives

- **The team writes the `HTTPRoute` (the first version).** Rejected: teams expect to
  ask only with `TemplateInstance`s, and used four route fields. A free route
  can match by regular expression, header or query parameter, which an
  Istio path rule can't express; the child would have to refuse those routes.
- **Annotations on the `api` instance, not parameters (as ADR-0012).**
  Rejected: an instance's own render can't read its annotations (T6), so the
  child would also have to render every route. Parameters keep the route with
  the team's instance; admission removes `valueFrom`.
- **All of a tenant's APIs in the gateway request.** Rejected: an instance's
  parameter value is a string, so the list of APIs would be JSON in a string;
  one typing error stops the whole instance, and every API of the tenant with
  it; several API teams would edit one object.
- **One API per hostname (the first version).** Rejected: no team chose a host, and
  every caller's URL would change.
- **Kuadrant's per-route `AuthPolicy`.** Rejected by ADR-0003; the path in the
  rule gives the same result here.
