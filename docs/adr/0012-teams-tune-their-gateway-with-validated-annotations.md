# ADR-0012: Teams tune their gateway with validated annotations on the request

- **Status:** Proposed
- **Date:** 2026-11-17

## Context

ADR-0002 gives a team a gateway with no parameters, so nothing in the request
can be wrong. Teams still need some settings. Across the twelve per-team
values files of the pattern we see in practice, teams changed four things
beyond their routes:

| Setting | Changed by teams | What it does |
|---|---|---|
| Claim → header mapping | one team: `client_id` → its own header name, instead of `azp` → `x-sub` | the backend's contract for who called |
| Correlation ID | some on, some off | a header that ties log lines of one call together |
| Access log and traces | one team: its own log format and two extra trace headers | the team's own observability |
| Rate limit | one team off | the team's switch on each `api` instance (ADR-0004), not a gateway knob; not by a team setting |

No team changed scaling or public paths. Other differences (an external
backend, a legacy issuer, no backend lock, one public host split by path) are
not settings: they are parameters of the `api` instance (ADR-0014 for the
external backend, ADR-0007 for the lock), later stories (G.9, G.17), or the
entry point (ADR-0005, G.18).

Template Operator facts (T6–T8): the render context of an instance holds its
name, namespace and labels, not its annotations; a parameter can read a
Secret or ConfigMap through `valueFrom`; parameters have no enum, range or
pattern validation, and an undeclared parameter fails the instance.

## Decision

- **A team sets its knobs as annotations on its gateway request**
  (`TemplateInstance` of `api-gateway`), with the prefix
  `api-gateway.stakater.com/`. The request still has no parameters.
- **The tenant's child `TemplateInstance` reads them** (it lists the tenant's
  `TemplateInstance`s, ADR-0013), validates each one, and uses only the valid
  ones. Each refused or unknown key is listed, with the reason, in the
  tenant's status ConfigMap; the gateway keeps working with the default.
- **The knobs of v1:**

| Annotation | Value | Default | Checks |
|---|---|---|---|
| `claim-headers` | `claim=header,…`, at most 5 | none | header names lowercase letters, digits and `-`; not a platform or reserved header (`authorization`, `host`, `cookie`, `x-sub`, `x-roles`, `x-request-id`, `x-forwarded-*`, `x-envoy-*`, tracing headers, `content-*`); claim names letters, digits, `_`, `.`, `-` |
| `correlation-id` | `on` or `off` | `off` | the header name is a platform value |
| `access-log` | a provider name, or `off` | `off` | the name is in the platform's list of access log providers |
| `trace-headers` | `header,…`, at most 5 | none | header names as above; only when the platform configures tracing |

- **Claim headers are added, never replaced.** `x-sub` and `x-roles` always
  stay. Every mapped claim is required in the API rule, so the header is
  always written from the token, and the header filter removes the caller's
  copy of every mapped name (ADR-0003).
- **Security, hostnames, scaling and rate limits are not gateway knobs.** They
  stay platform values (ADR-0004, ADR-0009); a team turns one API's rate limit
  off with that API's `rateLimit` parameter (ADR-0004).

## Consequences

- A team changes its settings without the platform team, and without any way
  to weaken a check.
- No parameter, so no `valueFrom`: a request still can't make Template
  Operator read a Secret.
- A typo is visible: an unknown key is listed, not silently ignored.
- A knob change re-renders only that tenant's child.
- The knobs are per gateway, so all APIs of a tenant share them. Istio sets
  claim headers per `RequestAuthentication`, which is per gateway.
- When a team removes a header mapping, the header filter stops removing that
  name. A backend that still trusts the old header must stop first; the
  platform can keep the name in its reserved list.

## Alternatives

- **`TemplateInstance` parameters.** Rejected: a parameter can read Secrets
  through `valueFrom`, and Template Operator can't check ranges or names.
- **Settings only as platform values per tenant.** Rejected: every change
  waits for the platform team, for settings that can't weaken security.
- **Annotations on each `HTTPRoute`.** Rejected for these knobs: Istio sets
  claim headers and telemetry per gateway, not per route.
