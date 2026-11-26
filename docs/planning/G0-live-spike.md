# G.0 — Live spike on OpenShift

Story: `docs/roadmap.md` G.0 (📝 Draft — needs 👍 Approved before starting).
Acceptance: none directly; it decides how AC-ISO-2 and the entry point are
built (G.18), and re-runs the kind lab's acceptance suite on OpenShift.

## Why (one paragraph)

The kind spike (G.19) answers how Istio and Template Operator behave. Some
questions exist only on OpenShift: what TLS server name (SNI) an OpenShift
`Route` sends to a gateway, whether a wildcard passthrough `Route` works on a
dedicated IngressController, how the Service Mesh operator names and maps the
`istio` GatewayClass and the gateway's ports, what a Multi-Tenant Operator
tenant editor can create, and whether the whole suite holds with real RHBK
tokens. The entry point decides the listener shape (ADR-0009), so it is
measured before G.18 renders anything.

## Governing constraints

- ADR-0001..0015 (0011 Rejected): this spike moves each to Accepted or writes a
  superseding ADR.
- Baseline: Service Mesh 3.3 and 3.4, Gateway API v1.5.1, Template Operator v2
  ≥ 0.0.5. Record exact versions of every component and of OpenShift.
- Public repo: no customer name, host, cluster, realm or token in the findings
  or the fixtures. Use the fixture names of `acceptance.md` and
  `apis.example.com`-style hosts.
- Secrets by reference: no token, client secret or private key in any file.
- Call as the caller (acceptance rules): real tokens, through the real entry
  point, every denial paired with an allow.

## Design

Environment: an OpenShift 4.20+ lab cluster with Service Mesh 3 in ambient
mode (discovery selectors on `istio-discovery=enabled`, M5), the
Multi-Tenant Operator with the fixture tenants, Template Operator v2, RHBK with
the fixture clients (a protocol mapper puts `allowed_apis`, a list with one
role per API and tier, in the access token), a Redis, and an echo backend.

Steps, each recorded in `docs/spikes/g0-findings.md` with the command, the
output and the answer:

1. Install, record versions. Install the bootstrap chart with the lab's values;
   confirm the root-namespace policies, the rate limit service and the
   admission policy.
1. Request `team-a`'s gateway; confirm `Programmed=True`, the `istio` class
   from the Service Mesh operator, the Service type, the ports the gateway
   pods listen on, and the autoscaler and disruption budget (Q7).
1. **Entry point (Q10):** with hostname-bound listeners, send a request through
   a reencrypt `Route` and through a passthrough `Route`; record the SNI the
   gateway sees and the result. Try one wildcard passthrough `Route` per tenant
   on a dedicated IngressController with `WildcardsAllowed`. Try to claim a host
   under the base domain with a tenant-made `Route`.
1. Run the kind lab's acceptance suite through the chosen entry point, with
   RHBK tokens.
1. Q9: as a tenant editor, `kubectl auth can-i` for every kind of ADR-0008,
   before and after the admission policy.
1. Repeat steps 2 and 4 after a Service Mesh minor upgrade (3.3 → 3.4).
1. **Shared host (R1–R3, Q17):** grant `front.example.com` with `/orders` to
   `team-a` and `/billing` to `team-b`, with `InterNamespaceAllowed` on the
   router; confirm that each reencrypt `Route` reaches its own gateway's
   `entry` listener with the service CA certificate, and that the longest
   path wins.
1. **Key reload (M19):** set the control plane's key reload interval to 3
   minutes; change a lab issuer's signing keys and record how long its tokens
   are refused.
1. **Tier expression (M20):** confirm that Service Mesh 3's proxy includes the
   expression rate limit descriptor; if it doesn't, record it for ADR-0003's
   tier claim fallback.
1. **Mesh revisions (M22):** run two control-plane revisions; move `team-a`'s
   gateway to the new revision with `istio.io/rev`, and back, under load.

## Tests (red first)

This story writes no chart. The red step is the acceptance suite run through
an entry point before the extension's policies exist: every denial scenario
must fail. Then install the chart and record the suite green.

## Out of scope

Rendering the entry point (G.18), migration (G.9), RHBK automation (G.11),
performance beyond what Q7 and Q12 need.

## Done means

The roadmap Done line: the OpenShift-only questions answered with evidence in
`docs/spikes/g0-findings.md`; the entry point decided in an ADR (ADR-0009
kept or superseded); every ADR Accepted or superseded; `design.md` and
`gateway-baseline.md` updated where an answer changed them; `make verify`
green.
