# mto-extension-api-gateway

The API Gateway extension for the
[Multi-Tenant Operator](https://docs.stakater.com/mto/). Every `Tenant` can
ask for its own API gateway on OpenShift — a Gateway API `Gateway` on Red Hat
OpenShift Service Mesh 3 — with the platform's security baseline built in:
token check, allowed-API rule, caller headers set from the token, and rate
limit tiers. The checks are Istio policies plus three platform-owned, tested
`EnvoyFilter`s (ADR-0003, proposed). A team asks for its gateway
with one `TemplateInstance` that has no parameters, and publishes each API with
one more `TemplateInstance` that names its host, path and backend. The token
check, the API rule and the header replacement have no switch to get wrong; a
team can turn off only its API's rate limit and backend lock, and the platform
can stop that.

> **Status: design.** The requirements, ADRs and roadmap are proposed; the
> first chart (story G.1) is built on its own code branch (pull request #14),
> render-tested only and not released. Start with
> [docs/vision.md](docs/vision.md), then [docs/design.md](docs/design.md).
> Tested versions: [docs/support-matrix.md](docs/support-matrix.md).
> Feature by feature against today's charts: [docs/parity.md](docs/parity.md).

## What a tenant gets

| On the platform | At the gateway |
|---|---|
| `TemplateInstance` `api-gateway` (no parameters) in `team-a-dev` | `Gateway` `api-gateway` in `team-a-dev`, serving `*.team-a.apis.example.com`, autoscaled; one per tenant |
| Every request | a valid token from one of the API's issuers; caller headers replaced from the token; the caller's rate limit tier |
| `TemplateInstance` of `api` named `orders` in `team-a-dev`: host, path, backend `Service` and port | an `HTTPRoute` to the tenant gateway; only callers whose token names `api.team-a.orders` reach that host and path |
| Backend Service `orders` | accepts calls from `team-a`'s gateway only (except health and metrics paths); on by default, the team can turn it off |
| Tenant deleted | its gateway and policies removed; other tenants untouched |

## How it is built

One Helm chart, installed once per cluster, that renders
[Template Operator v2](https://docs.stakater.com/template-operator-v2/)
objects per tenant, in the shape of
[mto-extension-vault-enterprise](https://github.com/stakater/mto-extension-vault-enterprise).
No new operator, no custom resource: Gateway API and Istio objects only. See
[ADR-0001](docs/adr/0001-template-operator-renders-everything.md) and, for the
part that makes it safe,
[ADR-0004](docs/adr/0004-security-baseline-is-a-gateway-override.md).

## Documents

| | |
|---|---|
| [Vision](docs/vision.md) | why, for whom, value, non-goals |
| [Concepts](docs/concepts.md) | terms, the running example, before and after |
| [Roadmap](docs/roadmap.md) | phases and user stories |
| [Acceptance](docs/acceptance.md) | the security contract as testable scenarios |
| [Design](docs/design.md) | what is rendered, the baseline, the allowed-API rule, limits |
| [Ownership & RACI](docs/raci.md) | who owns what without the extension and with it; platform team vs API team |
| [Gateway baseline](docs/gateway-baseline.md) | what Service Mesh, Istio, Gateway API, Kuadrant (the alternative) and Template Operator give, with sources |
| [Diagrams](docs/diagrams.md) | C4 and sequence diagrams |
| [Parameters](docs/parameters.md) | every setting of today's gateway chart, and who sets it now: the platform, the team, or nobody |
| [ADRs](docs/adr/README.md) | decisions and rejected alternatives |
| [Method](docs/method.md) | how work moves from story to done |
