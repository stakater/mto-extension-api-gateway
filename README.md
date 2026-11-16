# mto-extension-api-gateway

The API gateway extension for the
[Multi-Tenant Operator](https://github.com/stakater/multi-tenant-operator).
A team gets a secure, per-API ingress gateway by committing one short
`TemplateInstance`. Token validation, consumer authorization, header stripping,
rate limiting and mTLS to the backend are in the platform's Template, not in the
team's hands and not optional. No team can ship an unauthenticated API, and no
team can route around the gateway.

> **Status: design phase, and gated.** This repository holds requirements and
> design. No chart is built. The value verdict is **build — generic,
> reference-driven, and spike-gated**: run the M.0 spike now, and build when it
> is green — chiefly whether a shared rate-limit service and header stripping
> attach to a Gateway API gateway without a fragile `EnvoyFilter`. Start with
> [docs/vision.md](docs/vision.md).

## What a team gets

| They commit | They get |
|---|---|
| a `TemplateInstance`: `apiName`, backend, external host, tier | a `Gateway` (Envoy) for that one API and environment, with its token check, consumer authorization, rate limit and telemetry |
| nothing about security | token validation + a token-requiring authorization policy, always; there is no parameter to turn them off |
| `apiName: orders` | a consumer scope `api-orders-consumer-*`, **derived** — a team can't set it to `*` |
| a backend namespace in their tenant | a `gw-only` rule so only the gateway reaches the backend, over mTLS through the namespace's waypoint |
| a change to the Template version (platform) | every gateway on the new version at the next render — no per-team work |
| a hand-written raw `Gateway` | refused at admission: the Template is the only way in |

## How it is built

A Template Operator v2 `Template` published once, rendered per gateway by a
team-authored `TemplateInstance`; the backend side (`ReferenceGrant`,
`gw-only`, waypoint) rendered by a platform `TemplateGroupInstance`; mesh and
waypoint membership from the `Tenant`. Everything it writes is a standard
Gateway API, Istio or Kubernetes object, so there is **no config operator**
(ADR-0001). It governs north-south ingress and composes with
`mto-extension-service-mesh` (east-west), reusing its guardrail so a team can't
route around the Template (ADR-0006).

## Documents

| | |
|---|---|
| [Vision](docs/vision.md) | **the value verdict**, why, for whom, and an honest account of what it is not |
| [Concepts](docs/concepts.md) | the terms, with one running example |
| [Roadmap](docs/roadmap.md) | phases, user stories, open decisions |
| [Acceptance](docs/acceptance.md) | the secure gateway, the backend side and the governance as testable scenarios |
| [Design](docs/design.md) | rendered objects, baked security, the backend side, composition, rate limiting, telemetry, prerequisites, limits |
| [Ownership & RACI](docs/raci.md) | who owns what without the extension and with it; the platform vs application-team RACI |
| [API gateway baseline](docs/api-gateway-baseline.md) | what OpenShift Service Mesh 3.4, Gateway API and the identity provider give and where they stop, with sources |
| [Diagrams](docs/diagrams.md) | C4 and sequence diagrams |
| [ADRs](docs/adr/README.md) | decisions and rejected alternatives |
| [Method](docs/method.md) | how work moves from story to done |

The customer-facing deck for this extension will live in
`stakater-sales/mto-sales` (`src/pages/api-gateway.astro`, speaker notes in
`SPEAKER-NOTES-API-GATEWAY.md`), once the build gate is passed. This repository
is the source of truth; the deck follows it.
