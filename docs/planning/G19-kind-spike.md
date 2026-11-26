# G.19 — Kind spike

Story: `docs/roadmap.md` G.19 (✅ Done on 2026-11-26: 81 of 81 checks on Istio 1.27.9
and 1.30.8).
Acceptance (live parts, on objects written by hand in the shapes of design §3,
before any chart renders them): AC-ISO-5, AC-ISO-8, AC-ISO-12, AC-AUTH-1,
AC-AUTH-2, AC-AUTH-3, AC-AUTH-7, AC-AUTH-8, AC-AUTH-9, AC-AUTH-10, AC-RL-1,
AC-RL-2, AC-RL-3, AC-RL-4, AC-RL-6, AC-EXT-1, AC-LIFE-7.

## Why (one paragraph)

The design rests on Istio, Envoy and Template Operator behaviours that the
docs don't settle (the **VERIFY** rows of `gateway-baseline.md`). Four first
runs in a scratch lab answered most of them and changed the design six times
(`docs/spikes/g19-kind-findings.md`), but that lab lives outside the repo, ran
only Istio 1.30.8, and can't be run again by anyone else. This story puts the
lab in the repo, runs every check on Istio 1.27.9 (Service Mesh 3.3) and
1.30.8 (Service Mesh 3.4), and adds the three checks still missing: any apply
order (issue #10, AC-AUTH-7), and Template Operator's empty LIST and missing
key (T6, T7).

## Governing constraints

- **Public repo** (CLAUDE.md): no customer name, host, cluster, realm or token.
  Fixture names of `acceptance.md`, hosts under `apis.example.com`. Signing keys
  are made at run time in `hack/lab/.state/`, which git ignores.
- **Acceptance rules:** call as the caller, through the gateway's Service; a
  denial counts only with its status code and a matching allow by a caller who
  should pass.
- ADR-0001, ADR-0002: the gateway is `mto-api-gateway`; every object of ours
  has a reserved name and the label `api-gateway.stakater.com/managed`.
- ADR-0003, ADR-0004, ADR-0006: the root floor and default deny, the token only
  from `Authorization`, the closed rule with `azp` required, the tier by a CEL
  expression over the role claim, today's role names as exact values.
- ADR-0005: two APIs on one host, split by path; the rule checks host and path.
- ADR-0007: the waypoint lock as a `DENY` with open paths; STRICT per tenant.
- ADR-0014: an external backend through an `ExternalName` Service, a
  `ServiceEntry` and a `DestinationRule`.
- Baseline rows answered here: M4, M10, M12, M13, M14, M16–M21, M23, M24, Q5,
  Q16, Q18–Q22, S1, T4, T6, T7, T10.

## Design

`hack/lab/`, run with `make lab-up`, `make lab-test` and `make lab-down`:

| File | What it does |
|---|---|
| `README.md` | prerequisites, the fixture, how to run, what each check proves |
| `lab.sh` | `up`: kind cluster `api-gw-lab` (node `kindest/node:v1.33.12`), Gateway API v1.5.1, Istio from its Helm charts in ambient mode at `ISTIO_VERSION` (default 1.30.8) with the key reload set to 3 minutes, the lab issuers' keys, the fixture; with `TO_IMAGE`, cert-manager and Template Operator. `test`: every check, a results table in `.state/results-<istio>.md`. `down`: deletes the cluster |
| `lib/tokens.py` | makes the issuers' RSA keys, prints a JWKS, mints RS256 tokens with chosen claims |
| `lib/client.py` | runs in the client pods (from a ConfigMap): one request, a burst with status counts, a kept-open connection, a direct call |
| `lib/ratelimit_filter.py` | writes the rate limit `EnvoyFilter` of design §3.3 for the fixture's APIs, with the CEL tier expression |
| `manifests/*.yaml` | namespaces, the root floor and default deny, the gateway and its token check, the backends and routes, the API rules, the rate limit service and Redis, the lock, the external backend, the clients |
| `to/*.yaml` | Template Operator checks: the takeover guard, the empty LIST, the missing key |

Fixture, as `acceptance.md`: `team-a-dev` (gateway `mto-api-gateway`, API
`orders`), `team-a-test` (API `payments` on the same host, pod `intruder` in
the mesh), `team-a-outside` (pod `outsider`, not in the mesh),
`mto-api-gateways` (the rate limit service and Redis). Two trusted lab issuers
(`a`, `b`) and a third (`c`) whose key address is unreachable.

Checks (each prints `PASS`, `FAIL` or `NOTE` with its row):

| Row | Check |
|---|---|
| M12, AC-AUTH-1/2/3 | no token `403`, bad token `401`, valid token without the API `403`, valid token `200` |
| M17, Q18, AC-AUTH-10 | a token of issuer `b` on a gateway that trusts only `a`: `401` |
| AC-AUTH-9 | the token in `?access_token=`: `403` |
| M16, Q16, AC-AUTH-8 | `orders`' caller refused on `payments` and on six path tricks |
| M10, ADR-0006 | another tenant's API, `orders2`, no `azp`: `403`; a string claim: `200` |
| M14, M18, M20, AC-RL-1..4 | gold, silver, no role, unknown tier, two tiers, string claim, today's role name each limited at its rate; a counter per API |
| AC-RL-6 | the rate limit service scaled to zero: requests pass (fail open) |
| M4, Q5, AC-ISO-5 | `intruder` through the Service `403` on the API's path; open paths reach the backend; the gateway `200` |
| M21, Q21 | `intruder` on a pod's IP, `outsider` on the Service and a pod's IP: recorded (`NOTE`), the known limit |
| M24, AC-ISO-12 | with STRICT: `outsider` refused on every path, probes pass, the gateway `200` |
| M23 | the gateway's and the waypoint's metrics read from outside the mesh |
| Q20 | the root floor changed under a kept-open connection: no failed request |
| Q19 | issuer `c`'s keys unreachable: `a`'s tokens `200`, `c`'s `401` |
| Q22, AC-EXT-1 | the external backend over TLS, with the `Host` rewritten and no `Authorization` sent (needs internet; skipped with `LAB_OFFLINE=1`) |
| AC-AUTH-7, issue #10 | every policy of `orders` removed and applied again in shuffled orders while an attacker calls: the attacker never gets `200` |
| S1 | a change of the mounted rate limit configuration: the service's restarts recorded (`NOTE`) |
| T4, T10, AC-LIFE-7 | with Template Operator: the takeover without the policy (control), none with it |
| T6, T7 | with Template Operator: what a LIST with no objects gives the template, and a missing key on a listed object |

## Tests (red first)

The lab is the test. Its red steps are the controls: each guard is checked
once without it, and that run must show the failure the guard stops. The
takeover without the admission policy, the outsider without STRICT, and the
attacker while the policies are missing (before the root floor) must each
fail as expected, and the run records it.

## Out of scope

Any chart or template (G.20 onwards), OpenShift (G.0), the entry point and the
router (G.18), the upgrade suite (G.10). The lab writes the objects by hand in
the shapes of design §3; the render tests prove later that the chart renders
the same shapes.

## Done means

The roadmap Done line; `make lab-up lab-test` passes on Istio 1.27.9 and
1.30.8 on a clean kind cluster; `docs/spikes/g19-kind-findings.md` records
both runs; every row above in `gateway-baseline.md` cites its result; the
story is ✅ with this doc linked; `make verify` green.
