# G.19 kind spike: findings (first run)

A first, partial run of the kind spike, done on 2026-11-25 before story G.19
was approved, to check the design points that could change the design. It is
evidence, not the full spike: G.19 repeats it in `hack/lab/` and adds the
rest of its list.

## Setup

- kind, Kubernetes 1.33, **upstream Istio 1.30.8** in ambient mode (not
  OpenShift Service Mesh), Gateway API v1.5.1.
- No Template Operator: the objects the templates would render were applied
  by hand, in the shapes of design §3.
- Two lab token issuers with keys written into the `RequestAuthentication`
  (`jwks`), tokens signed with `openssl`.
- Backends: `go-httpbin` 2.15.0. Rate limit: `envoyproxy/ratelimit` with its
  own Redis, limits per minute for the test (gold 20, silver 10, bronze 4).
- A client pod outside the mesh, and an "intruder" pod inside the mesh.

## Results

| Row | What was checked | Result |
|---|---|---|
| M13 | The gateway Service type | `networking.istio.io/service-type: ClusterIP` in `spec.infrastructure.annotations` is copied to the Service but **ignored**: Istio made a `LoadBalancer` and the gateway stayed not `Programmed`. On the `Gateway`'s own `metadata.annotations` it gives `ClusterIP` and `Programmed`. **Design change: put the annotation on the Gateway.** |
| M10–M12 | Root floor and default deny | No token: `403`. Bad token: `401`. A valid token with no API rule: `403`. |
| M17, Q18 | A token from an issuer the gateway doesn't trust | `401` "Jwt issuer is not configured". |
| M16, Q16 | Two APIs on one host, split by path | A token for `orders` gets `200` on `/orders/v2/x`, and `403` on `/payments/v1/x`, `/orders/v2/../../payments/v1/x`, `//payments/v1/x`, `/orders/v2%2F..%2F..%2Fpayments/v1/x`, `/Payments/v1/x` and `/orders/v2x`. A query string doesn't change the match. |
| ADR-0006 | Closed rule, `azp` required, another tenant's API | A claim for another tenant's API: `403`. No `azp`: `403`. `allowed_apis` as one string, not a list: allowed. |
| M14, M18 | Rate limit entries per API at the virtual host, with no generated name | Both entries attach to the host's virtual host. |
| M20 | The tier from the caller's role, by a CEL expression descriptor | gold 20, silver 10, no role → bronze 4, unknown tier → bronze, bronze and gold roles → gold, the claim as one string → gold, today's role name `api-orders-consumer-silver` → silver. One caller on two APIs has two counters. |
| AC-RL-6 | Rate limiter unreachable | Every request passed (fail open, as configured). |
| M4, Q5 | The waypoint lock | A mesh pod calling the Service on an API path: `403`. On `/healthz` and `/metrics`: passed to the backend. The gateway: `200`. With a temporary "deny everything" on the waypoint, the gateway still got `200`: **the gateway's own traffic skips the waypoint**. |
| M21, Q21 | Calls that bypass the waypoint | A mesh pod calling the pod's IP: `200`. **A pod outside the mesh calling the Service, or the pod's IP: `200`.** The waypoint lock stops only mesh callers that use the Service. |
| — | STRICT mTLS on the backend pods (today's optional `backendPodLabels`) | Callers outside the mesh are refused (connection reset) on every path, `/metrics` included. Mesh callers on the pod's IP still pass. The gateway works. |
| Q22 | External backend: `ExternalName` Service, `ServiceEntry`, `DestinationRule` (`SIMPLE`) | `200` over TLS; the host saw its own name in `Host`, the rewritten path and `x-sub`, and no `Authorization` header. Without the API's role: `403`. |
| ADR-0014 | Name of the `ExternalName` Service | A Service name can't contain dots: `api.<api>.external` is refused. **Design change: `api-<api>-external`.** |
| Q20 | The root token floor changed (a third issuer added) while a client called every 0.25 s on one kept-open connection | 40 of 40 requests `200`. The gateway closed the connection once, gracefully (`Connection: close`), and the client reconnected with no error. |
| Q19 | A third issuer whose key address can't be reached, in the same `RequestAuthentication` | istiod logs the failed fetch. Tokens of the reachable issuer still get `200`; tokens of the unreachable one get `401` "Jwt verification fails". |

## Second run (2026-11-26): monitoring, STRICT and the rate limit configuration

Same lab, for the parts of the design that copy today's charts.

| Row | What was checked | Result |
|---|---|---|
| M23 | The metrics of the gateway and the waypoint, for a `PodMonitor` | Both pods have the port `metrics` (15020) and the annotations `prometheus.io/path: /stats/prometheus`. A scraper outside the mesh read `istio_requests_total` from both pods' IPs: the gateway reports as `source`, the waypoint as `waypoint`. |
| M24 | Kubelet probes on a backend with STRICT mTLS | With readiness and liveness probes on the API's port, the pod became ready and did not restart. A pod outside the mesh still got a connection reset on `/metrics` and on an API path; the gateway still got `200`. |
| S1 | A change of the rate limit `ConfigMap` while the service runs (the image digest today's chart pins, `RUNTIME_WATCH_ROOT=false`) | Three changes of one limit. Twice the service **crashed** when the file changed (`fatal error: concurrent map iteration and map write`, then `fatal error: unexpected signal during runtime execution`), restarted, and read the new limit on start, after about 60 s. Once it reloaded the file with no restart. **Design change: a limit change creates a new `ConfigMap` and rolls the pods; no running pod sees its file change** (design §3.1). |

## Third run (2026-11-26): no takeover at admission

| Row | What was checked | Result |
|---|---|---|
| T10 | A `ValidatingAdmissionPolicy` that refuses an `UPDATE` adding the label `api-gateway.stakater.com/managed` to an object without it; a ConfigMap created by hand by another field manager; then a forced server-side apply with Template Operator's field manager, the label and the same name | Refused as a dry run and for real, with the policy's message naming the object; the live object kept its data and had no new label. A new name was created, and an update of an object that already had the label was allowed. An object without the extension's label (another extension's) was still taken over: the policy doesn't affect other extensions. Template Operator itself was not in the lab; G.19 repeats this with it. |

## Fourth run (2026-11-26): no takeover, with Template Operator

Template Operator **v0.0.8** (the latest release) and **main** (commit
`a07748b`, after v0.0.8), both built from source. A Template in the shape of
the team render: a `Gateway` `mto-api-gateway`, the ConfigMaps
`mto-api-gateway-infra` and `mto-api-gateway-status.<request>`, all with the
extension's label, sync `strict`. The gateway class doesn't exist, so Istio
started no pods. The same results on both versions:

| Check | Result |
|---|---|
| Control, without the policy: a `Gateway` and a ConfigMap made by hand with those names, then a request | **Taken over:** the same UIDs, our listener merged into the `Gateway`, the ConfigMap's data replaced. **Deleting the request deleted both.** |
| With the policy `mto-api-gateway-no-adoption` | The dry run was refused and the status named the `Gateway` (`Applied=False`, `Ready=False`). Nothing was applied, not even the new status ConfigMap. Both objects stayed unchanged, and deleting the request left them. |
| A new namespace | Our objects were created; a Template change updated them; deleting the request deleted them. |
| Another extension's Template, with no label of ours, over a ConfigMap made by hand | Taken over, as that extension wants: the policy doesn't affect it. |
| A request named `orders-gateway`, next to a live `Gateway` `orders-gateway` | Ours is `mto-api-gateway`; the live `Gateway` stayed unchanged, also after the request was deleted. |
| The preflight name check (a prototype script) | Named the two objects with reserved names made by hand; passed once they were removed. |

Issue #11 is answered: the three guards of ADR-0001 hold on both versions.
G.29 builds them into the chart.

## Still to check

- The same on Istio 1.27 (Service Mesh 3.3's Istio).
- Template Operator: empty LIST, missing keys, refusing a taken name (T4,
  T6, T7, issue #11).
- Apply in any order with no request getting through (issue #10, AC-AUTH-7).
- The `entry` listener with no hostname, and everything OpenShift-only (G.0:
  R1–R5, M22, the expression descriptor in Service Mesh's proxy).
- A rolling restart of the rate limit service under load, with a new
  `ConfigMap` (AC-RL-8), and the preflight under `helm template` (AC-OPS-7).
