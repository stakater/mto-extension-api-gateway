# CLAUDE.md

Guidance for working in this repository.

## What this is

**The API gateway extension for the Multi-Tenant Operator.** It turns the
per-API ingress gateway into a platform-owned Template Operator v2 `Template` a
team instantiates with a short `TemplateInstance`. Every security-critical
setting — token validation, consumer authorization, header stripping, the
`gw-only` backend rule, mTLS to the backend, and the rate-limit hook — is baked
into the Template and has **no parameter**. A team chooses which API, backend
and host; the platform owns how it is secured, and upgrades every gateway at
once.

It governs **north-south** traffic (into a tenant) and composes with
`mto-extension-service-mesh`, which governs **east-west** (between tenants). It
follows the Template Operator pattern of the OpenBao and service-mesh
extensions, without a config operator: standard Gateway API, Istio and
Kubernetes objects rendered per gateway (ADR-0001).

## Status: design phase, gated — no code yet

This repo holds **requirements and design only**. Every story is 📝 Draft until
a human approves it. The value verdict (`docs/vision.md`) is **build — generic,
reference-driven, and spike-gated**: story **M.0** (a live-install spike) may
run on approval; phases 1–2 wait for M.0, chiefly **Q1** — whether a shared
rate-limit service and header stripping attach to a Gateway API gateway without
a fragile `EnvoyFilter`.

## No customer names — ever

This extension generalises a production reference architecture. **No customer
name, hostname, realm, team or cluster name from it appears in this repo.** The
running example is always generic: `team-a`, the `orders` API, `team-a-test`,
`api-team-a-test.apps.example.com`, realm `apis`. If you are adding content
drawn from the reference, anonymise it first.

## Scope — deliberately small, and held

The extension does exactly four things (`docs/design.md` §1):

1. Publish the `api-gateway` Template (the secure gateway, per API per
   environment).
1. Keep security un-switchable and the consumer scope derived from `apiName`
   (ADR-0002, ADR-0003).
1. Render the backend side (`ReferenceGrant`, `gw-only`, waypoint) and take
   mesh/waypoint membership from the `Tenant` (ADR-0005).
1. Report health.

It does **not** build the rate-limit service or the identity provider, provision
consumer clients (v1; ADR-0009), do the east-west boundary (that's the
service-mesh extension), or authenticate human end-users. A story that adds a
fifth thing needs an ADR saying why.

## Invariants — never violate these

1. **Security is baked, never a parameter.** No `auth.enabled`, no free-text
   `allowedApis`, no `allowGatewayAccessOnly`, no `rateLimit.enabled`. A
   `RequestAuthentication` is always paired with a token-requiring
   `AuthorizationPolicy` (ADR-0002, baseline A1).
1. **Consumer scope is derived from `apiName`** (`api-<apiName>-consumer-*`),
   never typed, never `*` (ADR-0003).
1. **The team sets only API-shaped parameters.** The values schema rejects
   anything else.
1. **Rendered from the `TemplateInstance` and the `Tenant`, never run-time.**
1. **No namespace labels written by the extension.** Mesh and waypoint
   membership come from the reviewed `Tenant` (ADR-0005).
1. **The backend is reachable only through the gateway, over mTLS.** `gw-only`
   is always rendered; enforcement is server-side (baseline M2, S1).
1. **One telemetry path.** Through the platform collector; never a second
   pipeline (ADR-0010).
1. **The Template is the only ingress path.** A team's hand-written
   `Gateway`/waypoint is refused (ADR-0006).
1. **Secrets by reference only.** The extension needs none; if one is ever
   needed, never inline it.
1. **Fail visibly.** A backend not meshed, an invalid host, a missing
   prerequisite: reported, never silently tolerated.

## Legacy — do not model on these

The Vault (`IntegrationConfig`) and ArgoCD (`Extensions` CR) integrations in
tenant-operator are legacy. The models are `mto-extension-openbao` (Template
Operator v2 charts) and `mto-extension-service-mesh` (docs, method, the
guardrail pattern this extension composes with).

## Documentation map

| Doc | What it is |
|---|---|
| `docs/vision.md` | **Read first.** The value verdict, why, for whom, honesty about what it is not. |
| `docs/concepts.md` | Plain-language primer and terms, one running example (`team-a`, `orders`). |
| `docs/method.md` | How this is built: story → plan → red → green → verify → validate. |
| `docs/roadmap.md` | Phases, stories with lifecycle status, open decisions. |
| `docs/acceptance.md` | End-to-end acceptance scenarios, testable. |
| `docs/design.md` | The design: rendered objects, baked security, the backend side, composition, rate limiting, telemetry, config, limits. |
| `docs/raci.md` | Who owns what — the copy-the-chart world today vs the Template model, and the platform/application-team RACI. |
| `docs/api-gateway-baseline.md` | What OpenShift Service Mesh 3.4, Gateway API and the identity provider do and don't, with sources; open questions (VERIFY → M.0). |
| `docs/diagrams.md` | C4 (context, container) and sequence diagrams. |
| `docs/adr/` | Architecture Decision Records — the *why* and the rejected alternatives. |
| `docs/planning/` | One planning doc per story, from `TEMPLATE.md`. |

**ADRs are immutable once accepted.** Supersede, don't edit.

## Workflow for any change (in order)

1. **Story** in `docs/roadmap.md` with a **Done:** line. 📝 Draft until a human
   approves.
1. **Planning doc** `docs/planning/<story>-<slug>.md` from `TEMPLATE.md`.
1. **Red first.** A failing render test (including the "no such parameter"
   guards) or acceptance check, then the change.
1. **Verify.** `make` green (once it exists), docs updated in the same change,
   story marked ✅ with the planning doc linked.

## Conventions to inherit from mto-extension-openbao / service-mesh

- `make` with no target runs exactly what CI runs.
- Golden render fixtures; an intentional output change regenerates the golden.
- `values.schema.json` for every value; the schema is what forbids a security
  parameter from existing.
- Bump `Chart.yaml` `version` with every chart change.
- `npx -y markdownlint-cli2 "**/*.md"` clean before every commit.

## Boundaries

- Baseline is **Red Hat OpenShift Service Mesh 3.4** (Istio 1.30, Gateway API
  GA) on OpenShift 4.20+, ambient mode, floor 3.3. When the stack changes,
  update `docs/api-gateway-baseline.md` first, then the design.
- Write only stable APIs: `gateway.networking.k8s.io/v1`, `security.istio.io/v1`,
  `admissionregistration.k8s.io/v1`. Avoid Technology Preview. If `EnvoyFilter`
  is unavoidable for rate limiting (Q1), keep it minimal and own its upgrade
  risk (ADR-0007).
- Always "Multi-Tenant Operator" in prose, never the abbreviation. A
  **consumer** is a machine client of an API, never a tenant member; **human**
  access is the group contract.
- Feature branches only; PRs cite the story code.
- The customer deck lives in `stakater-sales/mto-sales`
  (`src/pages/api-gateway.astro`, `SPEAKER-NOTES-API-GATEWAY.md`) and follows
  this repo, once the build gate is passed.
