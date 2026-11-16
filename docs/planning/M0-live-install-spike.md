# M.0 — Live-install spike

Story: `docs/roadmap.md` M.0 (📝 Draft; may start on approval). Acceptance:
none directly — this story produces evidence, not a feature. Output:
`docs/spikes/m0-findings.md`, and each Proposed ADR moved to Accepted or
superseded.

## Why (one paragraph)

The design rests on behaviour taken from a reference architecture that wires its
gateway with an `EnvoyFilter` (**D3**), and on the assumption that Istio's
token and authorization policies attach to a Gateway API gateway. Before any
chart is built, these must be observed on a live OpenShift Service Mesh 3.4
(ambient) install. The biggest risk is **Q1**: if the only way to attach a
shared rate-limit service and strip headers is a fragile `EnvoyFilter`, the
"platform owns one Template" value shrinks and the scope narrows (`vision.md`).

## Governing constraints

- ADR-0002 (security baked) and ADR-0007 (rate limit always on) both assume the
  mechanisms work on a Gateway API gateway — **Q1**, **Q4**, **Q6** test that.
- ADR-0005 (two-sided render) assumes `TemplateGroupInstance` can render
  cross-namespace and target a tenant's application namespaces — **Q2**,
  **Q3**, **Q11**.
- ADR-0006 (compose with service-mesh) assumes the service-mesh guardrail
  exempts the Template Operator identity — **Q9**.
- Baseline rows this spike closes: **D4/Q1, A1/A3/Q4, A2/Q5, A4/A5/Q6, J5/Q7,
  D2/Q8, J1/J2/Q10, T3/Q2/Q11, X1/Q9**.

## Design (what to stand up)

A single cluster: OpenShift 4.20+, OpenShift Service Mesh 3.4 ambient, Template
Operator v2, the Multi-Tenant Operator, an identity provider realm issuing
consumer tokens, and a shared Envoy rate-limit service. One tenant `team-a`,
one gateway for API `orders` with backend `orders-api` in `team-a-test`. Build
the objects **by hand** (no chart yet) to observe behaviour, then write the
findings.

## Investigations (one per question)

| Q | What to do | Pass looks like |
|---|---|---|
| **Q1** | Attach the shared rate-limit service and a header strip to the `istio` Gateway: try, in order, a GA filter API / `HTTPRoute` filters / a waypoint policy, then `EnvoyFilter`. | A supported mechanism is found, **or** it is confirmed that only `EnvoyFilter` works (and the cost is recorded for ADR-0007). |
| **Q2** | Render gateway-side objects from a `TemplateInstance` in the gateway namespace, and backend-side objects from a `TemplateGroupInstance` into the application namespace. | Both render; cross-namespace works, or a split/alternative is identified. |
| **Q3** | One waypoint in `team-a-test` shared by two gateways; enrol via the `Tenant` label. | The gateway's traffic reaches the backend through the waypoint; `gw-only` lists both gateways. |
| **Q4** | `RequestAuthentication` + `AuthorizationPolicy` with `targetRefs` → the `Gateway`. No-token call. | No token → `403`; a valid token → `200`. |
| **Q5** | A token whose `allowed_apis` is for another API. | Wrong-API token → `403`; right-API → `200`. |
| **Q6** | Send `x-sub`/`x-roles` from the caller. | The backend sees only the gateway-set values. |
| **Q7** | OpenShift `Route` (re-encrypt) in front of the gateway. | The external host serves the API; TLS/SNI handshake works. |
| **Q8** | Inspect whether the tier is carried in the token or set per gateway in the reference. | A documented decision: per-gateway (v1) or per-consumer (M.11). |
| **Q9** | Install the service-mesh extension guardrail; render the gateway as the Template Operator identity; hand-create a `Gateway` as a tenant user. | Template Operator passes; the tenant user is refused. |
| **Q10** | Deploy ~20 gateways + waypoints; measure istiod push, resource use, render time. | Numbers recorded; a rough ceiling per cluster. |
| **Q11** | Confirm the `TemplateGroupInstance` reads the `Tenant`/`Namespace` inputs it needs. | Inputs readable (shared with service-mesh/Keycloak M.0). |

## Tests (red first)

None (a spike). Each investigation has an explicit pass/fail above; a `403`,
`429` or a refused admission is the evidence, not a green golden file.

## Out of scope

No charts, no CI, no customer migration. Just observed behaviour and the ADR
decisions it settles.

## Done means

`docs/spikes/m0-findings.md` answers Q1–Q11 with evidence; each Proposed ADR is
Accepted or superseded (especially ADR-0007 once Q1 is known); `design.md` §8
updated to the chosen rate-limit mechanism; the roadmap's phase-1 gate is
cleared or the scope is narrowed with a written reason.
