# ADR-0012: Teams tune their gateway with validated parameters on the request

- **Status:** Proposed
- **Date:** 2026-11-17 (changed from annotations to parameters on
  2026-11-26, so that both requests use one style)

## Context

ADR-0002 gives a team a gateway with no security parameter, so nothing in the
request can weaken a check. Teams still need some settings. Across the twelve
per-team values files of the pattern we see in practice, teams changed four
things beyond their routes:

| Setting | Changed by teams | What it does |
|---|---|---|
| Claim → header mapping | one team: `client_id` → its own header name, instead of `azp` → `x-sub` | the backend's contract for who called |
| Correlation ID | some on, some off | a header that ties log lines of one call together |
| Access log and traces | one team: its own log format and two extra trace headers | the team's own observability |
| Rate limit | one team off | the team's switch on each `api` instance (ADR-0004), not a gateway knob |

No team changed scaling or public paths. Other differences (an external
backend, a legacy issuer, no backend lock, one public host split by path) are
not settings: they are parameters of the `api` instance (ADR-0014 for the
external backend, ADR-0007 for the lock), later stories (G.9, G.17), or the
entry point (ADR-0009, G.18).

Template Operator facts (T6, T8, T9):

- the render context of an instance holds its parameters, name, namespace
  and labels, not its annotations;
- a parameter can read a Secret or ConfigMap through `valueFrom`; admission
  refuses `valueFrom` on `api` and `api-gateway` instances (ADR-0008);
- parameters have no enum, range or pattern validation;
- an unknown parameter name fails the instance (`ParameterResolutionFailed`)
  before anything is applied; the objects it applied earlier stay.

## Decision

- **A team sets its settings as four optional parameters of its gateway
  request** (`TemplateInstance` of `api-gateway`), as it sets an API's
  parameters on its `api` request: one style for both requests. Beside them,
  the request has only the required `version` (ADR-0015); every other
  parameter of `api-gateway` stays a `disableOverride` default (ADR-0002).
- **The tenant's child `TemplateInstance` reads them** from the owner
  request's `spec.parameters` (it lists the tenant's `TemplateInstance`s,
  ADR-0013), validates each value, and uses only the valid ones. Each refused
  value is listed, with the reason, in the tenant's status ConfigMap; the
  gateway keeps working with the default.
- **A misspelt parameter name fails the request in Template Operator.**
  Nothing new is applied and nothing is deleted, so the running gateway keeps
  working; no change reaches it until the team fixes the name.
- **The settings of v1:**

| Parameter | Value | Default | Checks |
|---|---|---|---|
| `claimHeaders` | `claim=header,…`, at most 5 | none | header names lowercase letters, digits and `-`; not a name in the platform's `headers.refusedTargets` (default `authorization`, `host`, `cookie`, `x-sub`, `x-roles`, `x-request-id`, `x-forwarded-*`, `x-envoy-*`, tracing headers, `content-*`); claim names letters, digits, `_`, `.`, `-` |
| `correlationId` | `on` or `off` | `off` | the header name is a platform value |
| `accessLog` | a provider name, or `off` | `off` | the name is in the platform's list of access log providers |
| `traceHeaders` | `header,…`, at most 5 | none | header names as above; only when the platform configures tracing |

- **Claim headers are added, never replaced.** `x-sub` and `x-roles` always
  stay. A mapped claim is optional, as today: when a token lacks it, the
  header is not set, and the caller's copy is still removed by the header
  filter (ADR-0003), so it can never be forged. Only `azp` is required in the
  API rule. (Decided on 2026-11-26: an earlier version required every mapped
  claim, which would refuse today's tokens that lack it.)
- **Trace tags follow today's chart.** The gateway's `Telemetry` tags its
  traces with the correlation header (when it is on) and every claim header,
  automatically; `traceHeaders` adds the team's other headers.
- **The trace sampling rate is a platform value, not a setting.** When the
  platform configures tracing (`telemetry.tracing.enabled`) and a team sets
  `accessLog` or `traceHeaders`, the gateway's `Telemetry` samples
  `telemetry.tracing.samplingPercentage` of its requests (default 100 %, as
  today's chart does for each gateway with its telemetry on). A gateway
  without these settings follows the mesh's own rate.
- **Security, hostnames, scaling and rate limits are not gateway settings.**
  They stay platform values (ADR-0004, ADR-0009); a team turns one API's rate
  limit off with that API's `rateLimit` parameter (ADR-0004).

## Consequences

- A team changes its settings without the platform team, and without any way
  to weaken a check.
- One style: a team writes parameters on both requests, and Template Operator
  shows the values it resolved in the request's status.
- No `valueFrom`: admission refuses it, so a request can't make Template
  Operator read a Secret.
- A wrong value is visible: it is listed with the reason, not silently
  ignored. A misspelt name is visible in Template Operator's status, and stops
  all changes to that tenant's gateway until it is fixed; the running gateway
  is not touched.
- A settings change changes only the tenant's policy; the `Gateway` and its
  pods stay as they are.
- The settings are per gateway, so all APIs of a tenant share them. Istio sets
  claim headers per `RequestAuthentication` and telemetry per workload, both
  per gateway. When APIs of one tenant need settings that can't be combined,
  they wait for a second gateway per tenant (G.12) or keep their old gateway.
- When a team removes a header mapping, the header filter stops removing that
  name. A backend that still trusts the old header must stop first; the
  platform can keep the name in its reserved list.

## Alternatives

- **Annotations on the gateway request.** The first form of this decision,
  changed on 2026-11-26. A misspelt key would only be listed, and would not
  stop the request. Rejected: the two requests would use two styles, and a
  wrong key would show only in a ConfigMap, not in Template Operator's status.
  The `valueFrom` risk that first favoured annotations is closed by admission.
- **Settings only as platform values per tenant.** Rejected: every change
  waits for the platform team, for settings that can't weaken security.
- **Settings on each `api` request.** Rejected for these settings: Istio sets
  claim headers and telemetry per gateway, not per route.
