# CLAUDE.md

Guidance for working in this repository.

## What this is

**The API Gateway extension for the Multi-Tenant Operator.** It lets every
Multi-Tenant Operator `Tenant` ask for its own API gateway on OpenShift, with
one parameterless `TemplateInstance` in the namespace where the gateway should
run (ADR-0002): a Gateway API
`Gateway` on OpenShift Service Mesh 3, with the platform's security baseline
built in as Istio policies plus three platform-owned `EnvoyFilter`s — token
check, allowed-API rule, caller headers set from the token, rate limit tiers —
and a mesh lock
that makes the gateway the only way to the backend. An API team publishes an
API with a `TemplateInstance` of `api`, which renders its `HTTPRoute`.

It reuses the shape of `stakater/mto-extension-vault-enterprise`: a bootstrap
chart, Template Operator v2 objects, the parent fan-out of one child per
`Tenant` (ADR-0001, ADR-0013).

## Status: walking skeleton, render-tested only

G.1 is built: the bootstrap chart (`charts/mto-extension-api-gateway-bootstrap`)
publishes the `api-gateway` Template, and a team's request renders its
tenant's `Gateway` in the team's namespace. The next stories, in order, are in
`docs/roadmap.md`: the kind spike (G.19) first, then the harness (G.20) and
the baseline. **G.0, the OpenShift spike, is not done.** Nothing is proven on
a cluster yet, and no chart is released before G.19 and G.0.

`make verify` gates every PR: markdownlint, relative links, the method checks
in `hack/check_method.py` and their tests, and `make charts`
(`hack/chart-render-tests.sh`: render checks, the golden, and CRD validation
against `hack/crds` through `hack/crd-validate`). It needs helm, yq and Go.
CI runs it, plus the ADR-immutability and story-citation checks. Regenerate
the golden only after an intended change: `make golden`.

## Invariants — never violate these

1. **Only the three allowlisted platform `EnvoyFilter`s, and no `WasmPlugin`
   or `TrafficExtension`, in any rendered output** (ADR-0003): header removal,
   rate limit, correlation ID. Each selects one tenant gateway, matches only
   `jwt_authn`, `router` or no name, and has no Lua.
1. **The token floor and the default deny live once in the Istio root
   namespace** (ADR-0004): a `DENY` on `notRequestPrincipals` listing every
   issuer the platform trusts, and an `ALLOW` with no rules, both selecting the gateway
   label. Never move them next to a gateway; never give that `ALLOW` a rule.
1. **Gateway policy is rendered by the tenant's child, never by the team's
   request** (ADR-0013): `RequestAuthentication`, filters, `Telemetry`, the
   per-API `ALLOW`s and the backend locks. Tenants can't write gateway policy
   or act as the gateway (ADR-0008). No security setting is a per-tenant
   value, except two platform values: the tenant's issuers and the rate-limit
   exemption (a whole tenant or one API). The one team switch is an API's
   own rate limit (`rateLimit: "off"`), which the platform can lock. An issuer run by one tenant is never trusted for another.
1. **An API is an `api` `TemplateInstance`, and its rule checks the host and
   the path** (ADR-0005): the team never writes a route; the template checks
   the parameters, and admission refuses `valueFrom`. The per-API `ALLOW`
   names the route's host and its path (`<path>`, `<path>/*`) or exact
   operations, requires `azp` and every mapped claim, and accepts only the
   API's issuers. APIs on one host whose paths overlap fail closed.
1. **Gateway settings are validated annotations, never parameters** (ADR-0012):
   unknown or refused keys are listed; a claim header never replaces
   `x-sub` or `x-roles`, and never maps to a reserved header.
1. **The allowed-API rule is derived and closed** (ADR-0006):
   `api.<tenant>.<api>`, exact or followed by `.`; never a typed pattern,
   never a wildcard.
1. **A team's request decides only where its gateway runs and what it is
   called** (ADR-0002). The `api-gateway` Template has no parameter a team
   can set (all `disableOverride`); the tenant comes from the parent's
   `tenantOf`, keyed by the request's namespace, never from the request's
   labels; one request per tenant owns the gateway; the Template syncs
   `strict`. The render tests' `trust` and `params` checks hold this.
1. **A team request renders only into its own namespace**; the parent only
   into the platform namespace.
1. **A listener takes only its tenant** (ADR-0002, ADR-0009):
   `from: Selector` on `stakater.com/tenant`, a hostname under the tenant's
   name; never `from: All`. The only listener without a hostname is `entry`,
   for the shared-host prefixes the platform grants (ADR-0009).
1. **Every API backend is locked to its tenant gateway** (ADR-0007) by a
   `DENY` on its target ports, never an `ALLOW`. **Fail closed:** a backend
   that can't be locked gets no allowed-API rule, so its route serves
   nothing.
1. **The gateway class is `istio`**, from the ambient mesh's own control
   plane, never `openshift-default` (K1).
1. **Tenants create only `TemplateInstance`s** (ADR-0005, ADR-0008):
   admission refuses their `HTTPRoute`s.
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
| `docs/gateway-baseline.md` | What Service Mesh, Istio, Gateway API, Kuadrant (the alternative) and Template Operator give, with sources; open questions. |
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

- Baseline: Service Mesh 3.4, Gateway API v1.5.1,
  Template Operator v2 ≥ 0.0.5. When one changes, update
  `docs/gateway-baseline.md` first, then the design.
- Secrets by reference only. No token, client secret or private key in any
  file.
- Feature branches only; PRs cite the story code (CI fails otherwise) or say
  `No story: <reason>`.
- Write "Multi-Tenant Operator" in full.
