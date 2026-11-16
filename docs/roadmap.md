# Roadmap

Phases → milestones → user stories. **Every story delivers a demo-able outcome.**

## How we work

- **Story format:** *As a `<role>`, I want `<capability>`, so that `<value>`.*
  Every story has a **Done:** line and cites the acceptance scenarios it
  satisfies (`acceptance.md`, e.g. **AC-ISO-1**).
- **Lifecycle:** **📝 Draft** (written, not agreed — may be re-scoped or killed)
  → **👍 Approved** (a human said build it) → **🔨 In progress** → **✅ Done**
  (Done line met, `make verify` green, planning doc linked). Nothing moves from
  Draft to In progress without explicit approval.
- **One story at a time**, end to end. Walking skeleton first: one tenant, one
  API, one caller, checked and proven, then thicken.
- **Reuse, don't redesign.** The bootstrap and per-tenant chart shape, the
  fan-out, the skipped-tenants ConfigMap, the render harness and the version
  rules come from `mto-extension-vault-enterprise` (ADR-0001).
- The method: `method.md`.

## Phases

| Phase | Demo outcome |
|---|---|
| **0 · Prove the ground** | Every open question in `gateway-baseline.md` answered on a live OpenShift with Service Mesh 3 (ambient) and Connectivity Link; ADRs moved to Accepted or superseded. |
| **1 · Walking skeleton** | Tenant created → its gateway appears and scales → an API team writes one annotated `HTTPRoute` → `shop` gets `200`, a caller without the API gets `403`, too fast gets `429`, a pod calling the backend directly is refused. |
| **2 · Trustworthy** | Status and preflight, lifecycle, admission, migration from per-API gateways, an upgrade test — ready for a design partner. |
| **3 · Complete** | RHBK roles from the route, a gateway of its own when an API needs one, observability per tenant, docs. |

---

## Phase 0 — Prove the ground

**Story G.0 — Live spike** 📝 *Draft*

As the engineer building the extension, I want every open Service Mesh,
Gateway API, Connectivity Link and Template Operator question answered on a
live cluster, so that the charts rest on observed behaviour.

Done: all open questions (Q1–Q13) answered with evidence in
`docs/spikes/g0-findings.md`, from hand-written objects (no chart yet) on an
OpenShift lab; each ADR Accepted or superseded; `design.md` and
`gateway-baseline.md` updated where an answer changed them. Planning:
[`planning/G0-live-spike.md`](planning/G0-live-spike.md).

---

## Phase 1 — Walking skeleton

**Story G.1 — A gateway per tenant** 📝 *Draft*

As a platform team, I want to install the extension once and have every tenant
get its own gateway, so that no tenant needs a setup step and no tenant shares
another's gateway.

Done: bootstrap chart with the parent `Template` and `TemplateInstance`; per
valid `Tenant`, `Gateway` `<tenant>` in the gateway namespace with the listener
of ADR-0002 and ADR-0009, its autoscaling ConfigMap and the entry point chosen
in G.0; invalid and reserved
tenant names skipped and listed; the render harness (golden fixtures, CRD
validation against vendored Gateway API and Connectivity Link CRDs, the
security-baseline check) wired into `make verify`. Satisfies **AC-ISO-1**,
**AC-ISO-2**, **AC-R-1**, **AC-R-5**.

**Story G.2 — The security baseline** 📝 *Draft*

As a security owner, I want every tenant gateway to check the token, replace
caller headers from the token and deny by default, so that no API is served
without the checks and no route can weaken them.

Done: the Istio token floor; gateway-level `AuthPolicy` with `overrides`
(`merge`, fixed `when`, issuer pin, audience, tenant floor, header names and
the `azp`/`tier` export from bootstrap values); a default deny per listener;
the render checks and their mutation tests; live, before any API exists: no
token or an invalid token refused, a valid token refused by the default deny,
no moment without a token check on a new route. Satisfies **AC-R-2**,
**AC-R-3**, **AC-R-6**, **AC-ISO-8**, **AC-AUTH-7**, **AC-LIFE-1**.

**Story G.3 — An annotated route becomes an API** 📝 *Draft*

As an API team, I want one annotation on my `HTTPRoute` to publish my API with
the right allowed-API rule, so that I never write a security rule and never get
one wrong.

Done: the per-tenant chart and its child `TemplateInstance`; per annotated
route, a route-level `AuthPolicy` with the derived, closed rule of ADR-0006;
duplicates (oldest wins) and un-annotated routes reported; live: `shop`
`200` with headers replaced, no or invalid token `401`, `bank`, `near`,
`bare` `403`, `plain` serves nothing, the prefix tenant isolated, weakening
route-level policies have no effect. Satisfies **AC-ISO-3**, **AC-ISO-4**,
**AC-AUTH-1**, **AC-AUTH-2**, **AC-AUTH-3**, **AC-AUTH-4**, **AC-AUTH-5**,
**AC-AUTH-6**, **AC-R-4**.

**Story G.4 — The backend lock** 📝 *Draft*

As an API team, I want my backend to accept calls only from my tenant's
gateway, so that nobody in the cluster can skip the gateway's checks.

Done: per backend Service of an annotated route, an Istio
`AuthorizationPolicy` (L4, ztunnel): `DENY` on the target ports from every
identity but the tenant gateway's; no route-level policy for a backend that
can't be locked (fail closed); live: `intruder` and `outsider` refused, also
after an extra `ALLOW`, the gateway allowed, `legacy` and `stray` serve
nothing. Satisfies **AC-ISO-5**, **AC-ISO-7**.

**Story G.5 — Rate limit tiers** 📝 *Draft*

As a platform team, I want each authenticated caller limited by its tier on
every API, so that no caller uses more than its share of a tenant's gateway.

Done: gateway-level `RateLimitPolicy` with `overrides`, tiers and the tier
claim name from bootstrap values, `bronze` as the catch-all for a missing or
unknown tier, counted per caller; live: `429` at the limit, per-caller counters. Satisfies
**AC-RL-1**, **AC-RL-2**, **AC-RL-3**.

---

## Phase 2 — Trustworthy

**Story G.6 — Status and preflight** 📝 *Draft* — per-tenant status ConfigMap
(APIs, routes that are not APIs, duplicates, namespaces outside the mesh, hosts
outside the tenant's hostnames); preflight for Service Mesh, Gateway API CRDs,
Connectivity Link and the issuer. Satisfies **AC-OPS-2**.

**Story G.7 — Lifecycle** 📝 *Draft* — route deleted, tenant deleted, a hand
edit reverted; nothing left behind, nothing else touched. Satisfies
**AC-LIFE-2**, **AC-LIFE-3**, **AC-LIFE-4**.

**Story G.8 — Admission, agreed with the Service Mesh extension** 📝 *Draft* —
a `ValidatingAdmissionPolicy` for the kinds of ADR-0008 and for a `parentRef`
to another tenant's gateway; one shared list of refused kinds with the Service
Mesh extension. Satisfies **AC-ISO-6**.

**Story G.9 — Migration from per-API gateways** 📝 *Draft* — a runbook and a
lab rehearsal: role names mapped to `api.<tenant>.<api>` in the identity
provider, a values file turned into an annotated route, the entry point moved,
the old gateway removed. Satisfies **AC-MIG-1**.

**Story G.10 — Upgrades prove themselves** 📝 *Draft* — the live suite runs
before and after a Service Mesh minor upgrade and after a chart version bump;
both runs kept as evidence. Satisfies **AC-OPS-1**, **AC-OPS-3**, **AC-OPS-4**.

---

## Phase 3 — Complete

**Story G.11 — Identity-provider roles from the route** 📝 *Draft* — the
`api.<tenant>.<api>` role and the API's client created in RHBK from the
annotated route, so that the three owners of a new API become one request.
Needs a supported way to configure RHBK from the cluster; decided in its
planning doc.

**Story G.12 — A gateway of its own** 📝 *Draft* — opt-in: a second gateway for
a tenant, for one API or one environment, chosen by the platform per tenant
(ADR-0002).

**Story G.13 — An issuer per tenant** 📝 *Draft* — only if a customer needs
tenants with different identity providers; today one issuer per cluster
(ADR-0004).

**Story G.14 — Observability per tenant** 📝 *Draft* — gateway access logs in
the platform's JSON format, traces and metrics labelled with the tenant and the
API, delivered through the Multi-Tenant Operator's telemetry gateways.

**Story G.15 — Documentation** 📝 *Draft* — the extension's page in the
Multi-Tenant Operator docs, and a tutorial that fits the free edition (two
tenants).

**Story G.16 — Backends outside the cluster** 📝 *Draft* — an API whose
backend is outside the cluster (today an `ExternalName` Service, refused in
v1): a platform-approved list of external hosts per tenant, reached through
the mesh's egress, with what the lock can and can't promise there.

**Story G.17 — Internal callers of an API backend** 📝 *Draft* — an API team
names ServiceAccounts of its own namespace that may also call the backend's
API ports, so internal callers don't have to go through the gateway.

---

## Developer experience — enforcing the method

The method (`method.md`) is enforced by `make verify` and the PR workflow. These
stories close the gaps it lists under "Known enforcement gaps".

**Story DX.1 — CI is a merge gate** 📝 *Draft*

As a reviewer, I want a red `verify` check to block the merge, so that the
method can't be skipped by merging past a failing check.

Done: `verify` listed in the required status checks for this repo in
`stakater-ab/stakater-github-config`; a PR with a failing check can't be
merged.

**Story DX.2 — The method on every edit** 📝 *Draft*

As an engineer or agent, I want the fast checks to run after every edit, so
that a broken rule shows up while I work rather than at the PR.

Done: a Claude Code PostToolUse hook in `.claude/settings.json` runs
`make method links` after each edit to a Markdown file; the hook is documented
in `CLAUDE.md`.

---

## Not on the roadmap (non-goals)

Running the identity provider · installing Service Mesh, Connectivity Link or
the Gateway API CRDs · mesh membership and east-west traffic · a shared
multi-tenant entry point · API management features. See `vision.md`.
