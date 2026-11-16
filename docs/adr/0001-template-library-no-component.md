# ADR-0001: The gateway is a platform-owned Template a team instantiates; no component of our own

- **Status:** Proposed
- **Date:** 2026-11-16

## Context

The reference architecture deploys per-API ingress gateways by having each team
copy a Helm chart into its own repository and keep the full values file,
including the security switches. Everything a gateway needs is a standard
Kubernetes, Istio or Gateway API object the mesh reads directly (**J1–J3**,
**A1–A5**). Template Operator v2 can hold a Helm chart in a `Template` and
render it from a `TemplateInstance` with parameters, reverting drift (**T3**).

## Decision

Publish `api-gateway` as a platform-owned Template Operator v2 `Template`
(bootstrapped once). A team gets a gateway by committing a `TemplateInstance`
that references the Template and sets a few API-shaped parameters; Template
Operator renders the chart into the team's gateway namespace. The extension
runs **no operator, no controller, no gateway, no rate-limit service and no
identity provider of its own** — it renders objects and publishes a Template.

## Consequences

- Nothing new runs on the customer's cluster; the cheapest extension to build
  and support.
- The Template is a **contract**: a team can set only the exposed parameters,
  so security can be kept out of its hands (ADR-0002). A copied values file
  could never give that.
- Health is limited to what a parent TemplateInstance can compute (design §12).
- Depends on Template Operator rendering cross-namespace and reading the inputs
  it needs (**Q2**, **Q11**), shared with the service-mesh and Keycloak
  extensions.

## Alternatives

- **An `api-gateway-config-operator`.** Rejected: the gateway is standard
  objects, not a REST API to drive; YAGNI.
- **A controller watching Tenants and writing gateways.** Rejected: breaks the
  extension pattern and adds a component for what a render does.
- **A shared Helm chart teams install themselves (status quo).** Rejected: it
  can't stop a team editing the security values — the whole problem (ADR-0002).
