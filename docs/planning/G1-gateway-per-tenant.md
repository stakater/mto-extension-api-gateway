# G.1 — A gateway per tenant, on request

Story: `docs/roadmap.md` G.1 (👍 Approved by a code owner on 2026-11-16, built
before G.0 by decision; see "Why"). Acceptance: AC-ISO-1, AC-ISO-2, AC-ISO-9,
AC-LIFE-1, AC-LIFE-5 (render parts; live parts wait for G.0), AC-R-1, AC-R-5.

## Why (one paragraph)

Nothing exists yet: no chart, no render harness, so "red first" has nothing to
fail. G.1 is the walking skeleton's first step: the platform installs the
bootstrap chart once, and a team asks for its tenant's API gateway with one
`TemplateInstance` in the namespace where the gateway should run. It also
builds the harness every later story extends. Two decisions by the code owner
on 2026-11-16 shape it: **G.0 (the live spike) is not done**, and G.1 is built
offline first, so everything here is render-proven only and no release is cut
before G.0; and **gateways are not created automatically per tenant**: a team
requests one, and it runs in the team's own namespace (ADR-0002).

## Governing constraints

- ADR-0001: a bootstrap chart rendering a parent `Template` and
  `TemplateInstance` (Template Operator v2, `templates.v2.stakater.com/v2alpha1`);
  no CRD, no controller; sync mode never `off` (T3).
- ADR-0002: one `Gateway` per tenant, requested by a parameterless
  `TemplateInstance` of `api-gateway`, rendered in the request's namespace and
  named after it; the oldest valid request owns it; the tenant comes only from
  the parent's `tenantOf`; `api-gateway` syncs `strict`; listener
  `allowedRoutes.namespaces.from: Selector` on `stakater.com/tenant: <tenant>`,
  kinds `HTTPRoute` only; autoscaler and disruption budget through
  `spec.infrastructure.parametersRef` (M3).
- ADR-0009: listener `tenant` with hostname `*.<tenant>.<base domain>`; one
  listener `extra-<n>` per granted extra hostname; an extra hostname that is
  invalid, overlaps the base domain, or overlaps another tenant's is refused
  and listed.
- ADR-0003: no `EnvoyFilter`, `WasmPlugin` or `TrafficExtension` rendered.
- Gateway class `istio` only (K1, design §9).
- Names (design §6): a request name is a DNS label ≤ 48; a tenant name a DNS
  label ≤ 63.
- Template Operator facts used, read in its docs and source, not live: object
  and array parameters are decoded (T2); a rendered object with an explicit
  namespace lands there; the render context is `.parameters`, `.instance.name`,
  `.instance.namespace` and `.instance.labels` (the labels are the team's, so
  they are never trusted); `strict` refuses edits and deletes at admission (T3);
  anyone who can create a `TemplateInstance` can make the operator read through
  `valueFrom`, so the team Template declares no parameter a team can set.

## Design

| Path | What |
|---|---|
| `charts/mto-extension-api-gateway-bootstrap/Chart.yaml` | chart `0.1.0` |
| `…/values.yaml`, `…/values.schema.json` | `gateway.className` (enum `istio`), `gateway.baseDomain` (required), `gateway.extraHostnames`, `gateway.autoscaling` (min ≥ 2), `gateway.podDisruptionBudget`, `gateway.tls.certManager`, `tenants.mode` (`all` or `list`: who may request), `templateSync.mode` (enum `revert`, `strict`) |
| `…/templates/_helpers.tpl` | the parent's sync block, the checks the schema can't express |
| `…/templates/00-rbac.yaml` | ClusterRole: read `Tenant`s, `Namespace`s, `TemplateInstance`s; write `Gateway`s, ConfigMaps, `Certificate`s cluster-wide (tenant namespaces); Role in the platform namespace: write `Template`s and ConfigMaps |
| `…/templates/30-parent-template.yaml` | the parent `Template`; the team body reaches it as the `teamGotemplate` parameter (printed as data, never executed by the parent) |
| `…/templates/40-parent-templateinstance.yaml` | the parent `TemplateInstance`: `Tenant`, `Namespace` and `TemplateInstance` lists by `objectFieldRef` |
| `…/files/parent-gotemplate.tpl` | allowed tenants; `tenantOf`; owner election; refused host names and requests; publishes `api-gateway`; the skipped-tenants ConfigMap |
| `…/files/team-gotemplate.tpl` | one request: `Gateway` `<request>`, ConfigMap `<request>-infra`, `Certificate`s when cert-manager is on, and always `<request>-status` |
| `hack/chart-render-tests.sh` | the fifteen render checks below |
| `hack/crd-validate/` + `go.mod` | the Vault Enterprise extension's validator, generalised to every API group with a vendored CRD |
| `hack/crds/` | vendored CRDs: Gateway API v1.5.1 `gateways`; cert-manager v1.19.1 `certificates` |
| `hack/render-fixtures/` | the parent's parameters (tenants, namespaces, requests), the requests to render, and the golden |
| `Makefile`, `.github/workflows/pull_request.yaml` | `make charts` inside `make verify`; CI installs helm, yq and Go |

A team's request, and what it gets in `team-a-dev`:

```yaml
apiVersion: templates.v2.stakater.com/v2alpha1
kind: TemplateInstance
metadata: { name: api-gateway, namespace: team-a-dev }
spec:
  templateRef: { name: api-gateway, namespace: mto-api-gateways }
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: api-gateway
  namespace: team-a-dev
  labels: { stakater.com/tenant: team-a }
spec:
  gatewayClassName: istio
  infrastructure:
    labels: { stakater.com/tenant: team-a }
    parametersRef: { group: "", kind: ConfigMap, name: api-gateway-infra }
  listeners:
    - name: tenant
      hostname: "*.team-a.apis.example.com"
      port: 443
      protocol: HTTPS
      tls: { mode: Terminate, certificateRefs: [{ kind: Secret, name: api-gateway-tls }] }
      allowedRoutes:
        kinds: [{ group: gateway.networking.k8s.io, kind: HTTPRoute }]
        namespaces:
          from: Selector
          selector: { matchLabels: { stakater.com/tenant: team-a } }
```

Not changing: no policies (G.2), no per-tenant chart (G.3), no entry point
(G.18), no docs page.

## Tests (red first)

`hack/chart-render-tests.sh` ran red before any chart file existed. The
checks: structure, params (every team-Template parameter `disableOverride`),
sync (team Template `strict`), golden, emission (`tenantOf`, `owner`, granted
host names, skips; list mode), requests (owner renders a Gateway in its own
namespace; others only a refused status), trust (forged instance labels and a
request in another tenant's namespace change nothing), listener (AC-R-5),
extrahosts (ADR-0009), forbidden (AC-R-1), namespace (a request renders only
into its own namespace), certs, schema, rbaccover, crd.

Every guard has a positive control. Eleven hand mutations were each caught by
the expected check: the tenant read from instance labels (trust), the owner
check removed (requests), the newest request winning and a skipped tenant
allowed (emission), the team Template at `revert` (sync), a team-settable
parameter (params), a render into the platform namespace (namespace),
`from: All` (listener), wildcard overlap off (extrahosts), no cluster-wide
write on `Gateway`s (rbaccover), the port as a string (crd). The listener and
forbidden-kind checks also mutate a render on every run.

## Out of scope

The security baseline (G.2), API routes (G.3), the backend lock (G.4), the
entry point (G.18), admission policies (G.8), live tests (wait for G.0), chart
publishing (with the first release, after G.0).

## Done means

The roadmap Done line; `make verify` green with `make charts` inside it, output
seen; the golden regenerated only on purpose; design §2, §3.1, §6 and §7 match
the chart; story G.1 marked ✅ with this doc linked. The render-proven
scenarios get their live proof in G.0.
