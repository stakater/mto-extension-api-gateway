# CLAUDE.md

Guidance for working in this repository.

## What this is

**The API Gateway extension for the Multi-Tenant Operator.** It gives every
Multi-Tenant Operator `Tenant` its own API gateway on OpenShift: a Gateway API
`Gateway` on OpenShift Service Mesh 3, with the platform's security baseline
built in as Red Hat Connectivity Link policies — token check, allowed-API
rule, caller headers set from the token, rate limit tiers — and a mesh lock
that makes the gateway the only way to the backend. An API team publishes an
API with a standard `HTTPRoute` and one annotation.

It reuses the shape of `stakater/mto-extension-vault-enterprise`: a bootstrap
chart, a per-tenant chart rendered by Template Operator v2, the parent fan-out
per `Tenant` (ADR-0001).

## Status: design phase — no code yet

This repo holds **requirements and design only**. No chart yet. `make verify`
already gates the docs: markdownlint, relative links, the method checks in
`hack/check_method.py` and their tests. CI runs it on every PR, plus the
ADR-immutability and story-citation checks. Every story is 📝 Draft until a
human approves it. The first story is **G.0, a live spike** — do it before
writing any chart.

## Invariants — never violate these

1. **No `EnvoyFilter`, `WasmPlugin` or `TrafficExtension` in any rendered
   output** (ADR-0003). Connectivity Link's own managed `EnvoyFilter`s are the
   product's, not ours.
1. **The security baseline is a Gateway-level override** (ADR-0004), with
   `strategy: merge`, a fixed `when` and a pinned issuer: token, tenant floor,
   header replacement, the `azp`/`tier` export and tiers. An Istio token floor
   sits under it, and a default deny on every listener refuses everything a
   route doesn't allow. A route-level policy never has an `authentication`
   rule or a `when`. No security setting is a per-tenant value.
1. **The allowed-API rule is derived and closed** (ADR-0006):
   `api.<tenant>.<api>`, exact or followed by `.`; never a typed pattern,
   never a wildcard.
1. **A listener takes only its tenant** (ADR-0002, ADR-0009):
   `from: Selector` on `stakater.com/tenant`, a hostname under the tenant's
   name; never `from: All`.
1. **Every API backend is locked to its tenant gateway** (ADR-0007) by a
   `DENY` on its target ports, never an `ALLOW`. **Fail closed:** a backend
   that can't be locked gets no route-level policy, so its route serves
   nothing.
1. **The gateway class is `istio`**, from the ambient mesh's own control
   plane, never `openshift-default` (K1).
1. **Tenants create `HTTPRoute`s only** (ADR-0008).
1. **Templates never use sync mode `off`** (T3): an upgrade must reach every
   tenant.

## Public repository

This repo is public. **No customer name, host, cluster, realm, team name or
token in any file**, including spike findings and fixtures. Use the fixture
names of `docs/acceptance.md` (`team-a`, `orders`, `shop`) and
`*.apis.example.com`. Grep before every push.

## Documentation map

| Doc | What it is |
|---|---|
| `docs/vision.md` | **Read first.** Why this exists, for whom, the value, non-goals. |
| `docs/concepts.md` | Terms, the running example, before and after. |
| `docs/method.md` | How this is built — and where each rule is enforced: story → plan → red → green → verify → validate → review. |
| `docs/roadmap.md` | Phases and user stories with lifecycle status. |
| `docs/acceptance.md` | The security contract as testable scenarios. |
| `docs/design.md` | What is rendered, the baseline and its render check, the allowed-API rule, names, status, limits. |
| `docs/raci.md` | Who owns what — the copy-the-chart world today vs this extension; platform team vs API team. |
| `docs/gateway-baseline.md` | What Service Mesh, Gateway API, Connectivity Link and Template Operator give, with sources; open questions. |
| `docs/diagrams.md` | C4 and sequence diagrams. |
| `docs/adr/` | Architecture Decision Records. |
| `docs/planning/` | One planning doc per story, from `TEMPLATE.md`. |

**ADRs are immutable once accepted.** Supersede, don't edit.

## Workflow for any change (in order)

1. **Story** in `docs/roadmap.md`, 📝 Draft until a human approves.
1. **Planning doc** from `docs/planning/TEMPLATE.md`, committed first.
1. **Red first.** A failing render check or acceptance assertion, then the
   change.
1. **Verify.** `make verify` green, output seen; docs updated in the same
   change, story marked ✅ with the planning doc linked.
1. **Review.** An adversarial `/code-review` before merge, plus a code owner's
   approval (`.github/CODEOWNERS`). Defects found become stories.

The full method, and where each rule is enforced, is `docs/method.md`.

## Conventions inherited from mto-extension-vault-enterprise

Read its `CLAUDE.md` and `charts/README.md`; every rule there applies once the
charts land — the render harness rules (no check that can pass on its own
failure, mutation-test every guard), the live-test rules (assert as the
caller, a denial needs a matching allow), quoted tenant-derived values,
`tenantValues` as the only path to a tenant chart value, version bumps,
vendored CRDs, the skipped-tenants ConfigMap.

## Related extensions

The Multi-Tenant Operator's Service Mesh extension (in design) owns mesh
membership, east-west rules between tenants and the shared platform ingress.
It refuses tenant-created `Gateway`s and filters. This extension must agree
with it on one list of refused kinds (story G.8); neither duplicates the other.

## Boundaries

- Baseline: Service Mesh 3.4, Connectivity Link 1.4.1+, Gateway API v1.5.1,
  Template Operator v2 ≥ 0.0.5. When one changes, update
  `docs/gateway-baseline.md` first, then the design.
- Secrets by reference only. No token, client secret or private key in any
  file.
- Feature branches only; PRs cite the story code (CI fails otherwise) or say
  `No story: <reason>`.
- Write "Multi-Tenant Operator" in full.
