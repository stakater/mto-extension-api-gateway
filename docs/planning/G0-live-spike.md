# G.0 — Live spike

Story: `docs/roadmap.md` G.0 (📝 Draft — needs 👍 Approved before starting).
Acceptance: none directly; it decides whether the AC-ISO, AC-AUTH and AC-RL
scenarios are achievable as designed.

## Why (one paragraph)

The design rests on product behaviour that we read in docs and source but did
not observe: Connectivity Link policies on a gateway whose backends run in
ambient mode, a Gateway-level override composed with a listener-level default
deny, a CEL predicate on a list claim, header replacement on the shipped
wasm-shim, an L4 backend lock without a waypoint, and Template Operator
rendering Gateway API and Connectivity Link kinds from list parameters, and
the window before a new route's policies are programmed. Thirteen
questions (`gateway-baseline.md`, "Open questions") are load-bearing. Answer
them with hand-written objects before any chart is written, so the charts
don't carry an assumption that a product doesn't meet.

## Governing constraints

- ADR-0001..0009 are all Proposed; this spike moves each to Accepted or writes
  a superseding ADR.
- Baseline: Service Mesh 3.4, Connectivity Link 1.4.1 or later (never 1.4.0,
  K1), Gateway API v1.5.1, Template Operator v2 ≥ 0.0.5. Record exact versions
  of every component and of OpenShift.
- Public repo: no customer name, host, cluster, realm or token in the findings
  or the fixtures. Use the fixture names of `acceptance.md` and
  `apis.example.com`-style hosts.
- Secrets by reference: no token, client secret or private key in any file.
- Call as the caller (acceptance rules): real tokens, through the real entry
  point, every denial paired with an allow.

## Design

Environment: an OpenShift 4.20+ lab cluster with:

- Service Mesh 3.4 in ambient mode (`Istio`, `IstioCNI`, `ZTunnel`), discovery
  selectors on `istio-discovery=enabled` (M5);
- Connectivity Link 1.4.1+ with a `Kuadrant` instance; Limitador with in-memory
  storage first, then Redis for Q12;
- the Multi-Tenant Operator with tenants `team-a`, `team-b`, `team` and the
  namespaces of the fixture, mesh labels set through each `Tenant`;
- Template Operator v2 ≥ 0.0.5;
- RHBK with a realm and the fixture clients `shop`, `bank`, `near`, `core`,
  `bare`; a protocol mapper that puts `allowed_apis` (list) and `tier` in the
  access token;
- an echo backend that returns the request headers.

Files under `docs/spikes/g0/` (hand-written, no chart):

| File | Contents |
|---|---|
| `platform.yaml` | gateway namespace, `Gateway` `team-a` and `team-b` (ADR-0002, ADR-0009), parametersRef ConfigMaps, OpenShift `Route`s (re-encrypt) |
| `baseline.yaml` | per gateway: `AuthPolicy` baseline (`overrides`, `merge`), listener-level default deny, `RateLimitPolicy` tiers — as in design §3.1 |
| `apis.yaml` | the fixture `HTTPRoute`s with annotations, route-level `AuthPolicy`s and backend locks — as in design §3.2 |
| `acceptance.sh` | the live AC scenarios as `curl` calls with tokens from RHBK, printing status code and echoed headers |
| `q6-template.yaml` | a `Template` + child `TemplateInstance` with `objectFieldRef` LIST parameters for `HTTPRoute` and `Service` |
| `q9-rbac.sh` | `kubectl auth can-i` as a tenant editor for every kind in ADR-0008 |
| `q13-window.sh` | a new route called without a token from the moment it is accepted |

Steps, each recorded in `docs/spikes/g0-findings.md` with the command, the
output, and the answer to its question:

1. Install, record versions. Apply `platform.yaml`; confirm `Programmed=True`,
   the gateway Deployment name, replicas, HPA and PDB (Q7).
1. Apply `baseline.yaml`; confirm each policy `Accepted` and `Enforced`.
1. Apply `apis.yaml`; run `acceptance.sh` for AC-AUTH-1..6 (Q2, Q3, Q4),
   AC-ISO-1..5 (Q5, Q8), AC-RL-1..3 (Q12).
1. Remove the route-level policy of `orders`; confirm `403` (default deny back).
   Add a weakening route-level policy as cluster admin; confirm `401` without
   a token (Q3).
1. Q1: confirm no sidecar anywhere, the backends in ambient, and every AC still
   green.
1. Q5: from `intruder`, call `orders` directly; confirm refused; confirm
   probes and the platform's metrics scrape still work.
1. Q6: apply `q6-template.yaml`; confirm the child gets the routes as a list and
   renders an `AuthPolicy` into `team-a-dev`; record the RBAC it needed.
1. Q9: run `q9-rbac.sh`; record what a tenant editor can create today.
1. Q10, Q11: record the entry point and certificate setup used, and try to
   claim a host under the base domain with a tenant-made OpenShift `Route`;
   check `x-request-id` reaches the echo backend.
1. Q13: with the Istio token floor removed, create a new route and call it
   without a token in a tight loop from the moment it is accepted; record any
   `2xx`. Repeat with the floor in place.

## Tests (red first)

This story writes no chart, so there is no render test. The red step is the
acceptance script: run it first against a gateway **without** the baseline
policies and record which scenarios fail (they must: no token gets through).
Then apply the policies and record them green. Each denial also gets a
mutation run: change the guard on purpose (for example, the predicate to
`true`) and see the scenario fail.

## Out of scope

Charts, render harness, admission policies (G.8), migration (G.9), RHBK
automation (G.11). Performance and load beyond what Q7 and Q12 need.

## Done means

The roadmap Done line: all thirteen questions answered with evidence in
`docs/spikes/g0-findings.md`; every ADR Accepted or superseded by a new ADR;
`design.md` and `gateway-baseline.md` updated where an answer changed them
(VERIFY markers resolved); `make verify` green; G.1's planning doc can start
from the spike's YAML.
