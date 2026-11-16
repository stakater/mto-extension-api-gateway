# mto-extension-api-gateway

The API Gateway extension for the
[Multi-Tenant Operator](https://docs.stakater.com/mto/). Every `Tenant` gets
its own API gateway on OpenShift — a Gateway API `Gateway` on Red Hat
OpenShift Service Mesh 3 — with the platform's security baseline built in as
Red Hat Connectivity Link policies: token check, allowed-API rule, caller
headers set from the token, and rate limit tiers. An API team publishes an
API with a standard `HTTPRoute` and one annotation, and no security switch to
get wrong.

> **Status: design phase.** This repository holds requirements and design. No
> chart is built yet. Start with [docs/vision.md](docs/vision.md), then
> [docs/design.md](docs/design.md).

## What a tenant gets

| On the platform | At the gateway |
|---|---|
| Tenant `team-a` | `Gateway` `team-a`, serving `*.team-a.apis.example.com`, autoscaled |
| Every request | a valid token from the platform's issuer; caller headers replaced from the token; the caller's rate limit tier |
| `HTTPRoute` `orders` in `team-a-dev`, annotated `api-gateway.stakater.com/api: orders` | only callers whose token names `api.team-a.orders` get through |
| Backend Service `orders` | accepts calls from `team-a`'s gateway only |
| Tenant deleted | its gateway and policies removed; other tenants untouched |

## How it is built

Two Helm charts, rendered per tenant by
[Template Operator v2](https://docs.stakater.com/template-operator-v2/), in
the shape of
[mto-extension-vault-enterprise](https://github.com/stakater/mto-extension-vault-enterprise).
No new operator, no custom resource: Gateway API, Istio and Connectivity Link
objects only. See
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
| [Gateway baseline](docs/gateway-baseline.md) | what Service Mesh, Gateway API, Connectivity Link and Template Operator give, with sources |
| [Diagrams](docs/diagrams.md) | C4 and sequence diagrams |
| [ADRs](docs/adr/README.md) | decisions and rejected alternatives |
| [Method](docs/method.md) | how work moves from story to done |
