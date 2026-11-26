# The kind lab (story G.19)

A kind cluster with upstream Istio in ambient mode, the Gateway API, two lab
token issuers, echo backends, the rate limit service with Redis and, when you
give it the source, Template Operator v2. It checks the Istio, Envoy and
Template Operator behaviours the design depends on, on objects written by hand
in the shapes of [design §3](../../docs/design.md). No chart renders them yet.
The results are in
[`docs/spikes/g19-kind-findings.md`](../../docs/spikes/g19-kind-findings.md),
and each one is cited by its row in
[`gateway-baseline.md`](../../docs/gateway-baseline.md).

## Run it

Needs Docker (8 GB of memory is enough), `kind`, `kubectl`, `helm`,
`python3` and `openssl`.

```sh
make lab-up                          # Istio 1.30.8 (Service Mesh 3.4)
make lab-test                        # results: hack/lab/.state/results-1.30.8.md
make lab-down

ISTIO_VERSION=1.27.9 make lab-up lab-test   # Service Mesh 3.3's Istio
```

With Template Operator: set `TO_SRC` to a Template Operator v2 source tree. The
lab builds the image (`TO_IMAGE`, default `local/template-operator-v2:lab`) when
it is missing, loads it into kind, and installs cert-manager and the operator
from the tree's `config/default`. Without `TO_SRC`, the Template Operator
checks are skipped and the run says so.

`LAB_OFFLINE=1` skips the one check that needs internet (an external backend at
a public echo host).

## The fixture

The names of [`acceptance.md`](../../docs/acceptance.md):

| Namespace | What runs there |
|---|---|
| `team-a-dev` | the gateway `mto-api-gateway`, the API `orders`, the waypoint `mto-api-gateway-waypoint` |
| `team-a-test` | the API `payments` on the same host as `orders`, and `intruder`, a pod in the mesh |
| `team-a-outside` | `outsider`, a pod outside the mesh; callers come from here, as from the router |
| `mto-api-gateways` | the rate limit service and Redis |
| `istio-system` | the token floor and the default deny |

Token issuers `a` and `b` are trusted by the floor; the gateway trusts `a`
only. Issuer `c` is used for a key address that can't be reached. The keys are
made at run time in `hack/lab/.state/`, which git ignores; no key or token is
in the repo.

## What it checks

`lib/checks.py` (Istio and Envoy) and `lib/to_checks.py` (Template Operator),
each check with its baseline row or acceptance id. Each denial has a matching
allow. Some checks first remove a guard on purpose, as the red control: the
takeover without the admission policy, the outsider without STRICT mTLS, and
the attackers while the tenant's policies are missing. Rows marked `NOTE`
record a behaviour without judging it.

| File | What it is |
|---|---|
| `lab.sh` | `up`, `test`, `down` |
| `lib/tokens.py` | the issuers' keys, their JWKS, RS256 tokens |
| `lib/client.py` | the HTTP client in `intruder` and `outsider` (from a ConfigMap) |
| `lib/ratelimit_filter.py` | the rate limit `EnvoyFilter` of design §3.3 |
| `manifests/` | the fixture, in the order it is applied |
| `to/` | the Templates and RBAC of the Template Operator checks |
