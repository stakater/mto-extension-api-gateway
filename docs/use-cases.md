# Use cases: today's gateway charts and the extension

This page lists every use case that today's gateway charts deploy, and how
the extension handles each one. The sources are the twelve values files of
the per-API gateway chart (one per API and environment), the values files of
the other charts (the shared rate limit service, the realm, the end-to-end
runner and the mesh), the charts themselves, and the platform team's
runbook. Use this page before an API moves ([migration.md](migration.md)):
each use case says what is deployed today, how the extension does it, and
what changes for callers, the API team and the platform team. For the
feature-by-feature view, see [parity.md](parity.md).

## Status key

| Status | Meaning |
|---|---|
| Same | The extension gives the same result as today's chart. |
| Better | The same result, and safer or simpler. |
| Changed | The result is different. The use case gives the reason. |
| Later | Not yet. A story on the [roadmap](roadmap.md) adds it. |
| Not supported | Not supported, by decision. The use case gives the reason. |
| Stays with the platform | Not part of the extension. The platform team keeps it as it is. |

## Sources

| Source | What it deploys | Values files |
|---|---|---|
| The per-API gateway chart | one Helm release per API and environment: the gateway, its OpenShift `Route`s, the token check, the rate limit hook, telemetry and the backend lock | 12: seven for the test cluster (six for the test environment, one for the load-test environment), five for a lab cluster where every API fronts one echo backend |
| The rate limit chart | the shared rate limit service and Redis, once per cluster | 2: the defaults, and one replica for the lab cluster |
| The realm chart | one Keycloak realm per environment, its roles and its consumer clients | 4: the defaults, and three environments |
| The end-to-end chart | one check per API | 6: the defaults, two environments, three APIs |
| The mesh charts | the Service Mesh operator, Istio in ambient mode, mesh telemetry, Kiali | defaults only; the per-cluster values are kept in another repository |
| The runbook | how a team adds an API, and the day-2 tasks | — |

Every use case has four parts: **Today** (the chart, the template, the values
keys, how many values files use it, and who sets it), **New design** (the
team's `TemplateInstance`, the platform values, and the design source),
**What changes** (for callers, the API team and the platform team), and the
**Status**. The YAML uses the fixture names of [acceptance.md](acceptance.md).
Names of planned platform values are proposals ([parameters.md](parameters.md)).

## Contents

| Use case | Status |
|---|---|
| [UC-01 One gateway per API and environment](#uc-01-one-gateway-per-api-and-environment) | Changed |
| [UC-02 Attach an API to a gateway that already runs](#uc-02-attach-an-api-to-a-gateway-that-already-runs) | Same |
| [UC-03 Gateway entry TLS and Service type](#uc-03-gateway-entry-tls-and-service-type) | Changed |
| [UC-04 Gateway autoscaling and disruption budget](#uc-04-gateway-autoscaling-and-disruption-budget) | Same |
| [UC-05 Gateway and waypoint metrics](#uc-05-gateway-and-waypoint-metrics) | Same |
| [UC-06 Object names and labels](#uc-06-object-names-and-labels) | Changed |
| [UC-07 Shared front-door host split by path](#uc-07-shared-front-door-host-split-by-path) | Same |
| [UC-08 Internal host per API](#uc-08-internal-host-per-api) | Changed |
| [UC-09 API with only an internal host](#uc-09-api-with-only-an-internal-host) | Same |
| [UC-10 Public path and path rewrite](#uc-10-public-path-and-path-rewrite) | Same |
| [UC-11 Exact method and path operations](#uc-11-exact-method-and-path-operations) | Changed |
| [UC-12 Route features that no API uses](#uc-12-route-features-that-no-api-uses) | Not supported |
| [UC-13 Backend in the gateway namespace](#uc-13-backend-in-the-gateway-namespace) | Same |
| [UC-14 Backend in another namespace with a ReferenceGrant](#uc-14-backend-in-another-namespace-with-a-referencegrant) | Changed |
| [UC-15 Backend outside the cluster with TLS](#uc-15-backend-outside-the-cluster-with-tls) | Same |
| [UC-16 Several gateways call one backend Service](#uc-16-several-gateways-call-one-backend-service) | Same |
| [UC-17 One API on two public paths](#uc-17-one-api-on-two-public-paths) | Changed |
| [UC-18 Token check against the realm of the environment](#uc-18-token-check-against-the-realm-of-the-environment) | Changed |
| [UC-19 Keys from another address and the CA that istiod trusts](#uc-19-keys-from-another-address-and-the-ca-that-istiod-trusts) | Same |
| [UC-20 Several realms on one cluster](#uc-20-several-realms-on-one-cluster) | Same |
| [UC-21 Allowed-API rule](#uc-21-allowed-api-rule) | Better |
| [UC-22 Caller headers set from the token](#uc-22-caller-headers-set-from-the-token) | Better |
| [UC-23 A team claim header](#uc-23-a-team-claim-header) | Changed |
| [UC-24 Legacy issuer mode](#uc-24-legacy-issuer-mode) | Not supported |
| [UC-25 A gateway with the token check off](#uc-25-a-gateway-with-the-token-check-off) | Not supported |
| [UC-26 Tier rate limit on an API](#uc-26-tier-rate-limit-on-an-api) | Better |
| [UC-27 Rate limit off for an API](#uc-27-rate-limit-off-for-an-api) | Same |
| [UC-28 Lock on with its own waypoint](#uc-28-lock-on-with-its-own-waypoint) | Better |
| [UC-29 Lock that reuses the waypoint of another release](#uc-29-lock-that-reuses-the-waypoint-of-another-release) | Same |
| [UC-30 Waypoint in another namespace](#uc-30-waypoint-in-another-namespace) | Same |
| [UC-31 Lock off and direct backend access](#uc-31-lock-off-and-direct-backend-access) | Same |
| [UC-32 Open paths for probes and scrapers](#uc-32-open-paths-for-probes-and-scrapers) | Changed |
| [UC-33 STRICT mTLS on backend pods](#uc-33-strict-mtls-on-backend-pods) | Changed |
| [UC-34 The waypoint covers the whole namespace](#uc-34-the-waypoint-covers-the-whole-namespace) | Better |
| [UC-35 Correlation ID](#uc-35-correlation-id) | Same |
| [UC-36 JSON access log and full trace sampling](#uc-36-json-access-log-and-full-trace-sampling) | Same |
| [UC-37 An API log format and extra trace headers](#uc-37-an-api-log-format-and-extra-trace-headers) | Changed |
| [UC-38 Different settings for APIs in one namespace](#uc-38-different-settings-for-apis-in-one-namespace) | Changed |
| [UC-39 Several environments of one team on one cluster](#uc-39-several-environments-of-one-team-on-one-cluster) | Changed |
| [UC-40 Namespace labels from the Tenant](#uc-40-namespace-labels-from-the-tenant) | Better |
| [UC-41 Rate limit service and tiers](#uc-41-rate-limit-service-and-tiers) | Same |
| [UC-42 Rate limit service availability](#uc-42-rate-limit-service-availability) | Same |
| [UC-43 One rate limit replica on a small cluster](#uc-43-one-rate-limit-replica-on-a-small-cluster) | Same |
| [UC-44 Redis with Sentinel and its password](#uc-44-redis-with-sentinel-and-its-password) | Stays with the platform |
| [UC-45 Realm import per environment](#uc-45-realm-import-per-environment) | Stays with the platform |
| [UC-46 Roles per API and tier](#uc-46-roles-per-api-and-tier) | Stays with the platform |
| [UC-47 Consumer clients mappers and secrets](#uc-47-consumer-clients-mappers-and-secrets) | Stays with the platform |
| [UC-48 Token lifetimes](#uc-48-token-lifetimes) | Stays with the platform |
| [UC-49 Realm import again and new signing keys](#uc-49-realm-import-again-and-new-signing-keys) | Changed |
| [UC-50 Consumer tooling](#uc-50-consumer-tooling) | Stays with the platform |
| [UC-51 End-to-end runner per API](#uc-51-end-to-end-runner-per-api) | Stays with the platform |
| [UC-52 Mesh installation and version](#uc-52-mesh-installation-and-version) | Stays with the platform |
| [UC-53 Mesh logs traces and metrics](#uc-53-mesh-logs-traces-and-metrics) | Stays with the platform |
| [UC-54 Kiali](#uc-54-kiali) | Stays with the platform |
| [UC-55 GitOps with Argo CD](#uc-55-gitops-with-argo-cd) | Same |
| [UC-56 Unsafe values fail at render](#uc-56-unsafe-values-fail-at-render) | Better |
| [UC-57 Team copies of the chart](#uc-57-team-copies-of-the-chart) | Better |
| [UC-58 Onboard a new API](#uc-58-onboard-a-new-api) | Better |
| [UC-59 Change an API](#uc-59-change-an-api) | Same |
| [UC-60 Onboard a consumer](#uc-60-onboard-a-consumer) | Stays with the platform |
| [UC-61 Change a tier or a rate](#uc-61-change-a-tier-or-a-rate) | Same |
| [UC-62 Rotate keys and secrets](#uc-62-rotate-keys-and-secrets) | Same |
| [UC-63 Upgrade the gateway chart and the mesh](#uc-63-upgrade-the-gateway-chart-and-the-mesh) | Better |
| [UC-64 Offboard an API a consumer or a gateway](#uc-64-offboard-an-api-a-consumer-or-a-gateway) | Same |
| [UC-65 Verify and troubleshoot an API](#uc-65-verify-and-troubleshoot-an-api) | Better |
| [UC-66 Promote from test to production](#uc-66-promote-from-test-to-production) | Same |

## 1. The gateway

### UC-01 One gateway per API and environment

**Status:** Changed. One gateway per tenant, on request ([ADR-0002](adr/0002-one-gateway-per-tenant-requested-by-the-team.md)).

**Today.** Each API has its own gateway in each environment. One Helm release
of the per-API gateway chart renders a Gateway API `Gateway` of class `istio`
(`gateway/gateway.yaml`). Istio deploys its Deployment, Service and
ServiceAccount `<gateway.name>-istio`. The listener accepts routes only from
its own namespace (`allowedRoutes.namespaces.from: Same`). Every gateway
object goes into `gateway.namespace`, and the same release also writes into
the backend's namespace. Values keys: `gateway.create`, `gateway.name`,
`gateway.namespace`. All 12 values files use it. The API team sets it. A team
with two APIs and three environments runs six gateways, each with at least
three pods.

**New design.** A team asks once for its tenant's gateway, with one
`TemplateInstance` of `api-gateway` in the tenant namespace where the gateway
must run. The request has one required parameter, `version` (UC-63), and
four optional, non-security ones (UC-23, UC-35 to UC-37). Template Operator renders the
`Gateway` `mto-api-gateway` there, and Istio deploys `mto-api-gateway-istio`.
The listener accepts routes from every namespace of the tenant. Each API is
then one `api` instance (UC-13 to UC-15). Sources:
[design §3.2](design.md), [ADR-0002](adr/0002-one-gateway-per-tenant-requested-by-the-team.md),
[migration §2](migration.md).

```yaml
apiVersion: templates.v2.stakater.com/v2alpha1
kind: TemplateInstance
metadata:
  name: api-gateway
  namespace: team-a-dev            # where the tenant's gateway runs
spec:
  templateRef: { name: api-gateway, namespace: mto-api-gateways }
```

Platform values: `tenants.mode` and `tenants.list` (which tenants may ask),
and `gateway.baseDomain` (required).

**What changes.** Callers: nothing. API team: one request per tenant, not one
release per API. The APIs of a tenant share the gateway pods, so a load peak
on one API reaches the other APIs of the tenant; the autoscaler and the
per-caller rate limit reduce this. Platform team: fewer gateway pods, and it
decides how every gateway runs. A second gateway per tenant is story G.12
(Later).

### UC-02 Attach an API to a gateway that already runs

**Status:** Same.

**Today.** With `gateway.create: false`, a release renders only the route and
the policies, and attaches them to the `Gateway` named `gateway.name` in
`gateway.namespace`. It renders no OpenShift `Route`, no autoscaler and no
`PodMonitor`. Values key: `gateway.create`. No values file uses it: all 12
set `true`.
The API team would set it.

**New design.** Every `api` instance of a tenant attaches to the tenant's
gateway. The platform gives the gateway's name to the `api` Template as a
fixed parameter, so the team names no gateway. Sources:
[design §3.4](design.md), [ADR-0005](adr/0005-an-api-is-a-templateinstance-checked-by-host-and-path.md).

**What changes.** Callers: nothing. API team: nothing to set. Platform team:
nothing.

### UC-03 Gateway entry TLS and Service type

**Status:** Changed. The gateway Service is `ClusterIP`, and router traffic
goes to the `entry` listener.

**Today.** The gateway has one HTTPS listener on port 443 with no host name,
so it accepts any TLS server name: the router's reencrypted connection
carries none. TLS terminates at the gateway with a certificate from
OpenShift's service CA (Secret `<gateway.name>-tls`, rotated automatically).
Both OpenShift `Route`s are `reencrypt`, with no destination CA. The gateway
Service is type `NodePort`, so it is also open on a port of every node.
Values key: `gateway.tls.mode` (`Terminate` in all 12 files). The rest is
fixed in the template.
The API team sets the TLS mode; the platform team owns the router.

**New design.** The gateway has the listener `tenant` for
`*.<tenant>.<base domain>`, one listener `extra-<n>` for each host name that
the platform grants, and the listener `entry` with no host name for
shared-host prefixes and internal hosts. The `entry` listener's Secret comes
from OpenShift's service CA, as today. The other listeners get a certificate
from the platform's issuer (`gateway.tls.certManager.issuerRef`) or a Secret
that the platform provides. The Service is `ClusterIP`. Sources:
[design §3.2 and §10](design.md),
[ADR-0009](adr/0009-a-tenant-serves-only-the-hosts-and-paths-it-is-granted.md),
[gateway-baseline R3, R4, M13](gateway-baseline.md).

**What changes.** Callers that come through the router: nothing. A caller
that uses a node port of the gateway loses it; check the access logs before
the move. API team: nothing. Platform team: chooses the certificate source
for the `tenant` and `extra-<n>` listeners. Story G.0 measures how a
reencrypted connection reaches the `entry` listener, and story G.18 renders
the entry point.

### UC-04 Gateway autoscaling and disruption budget

**Status:** Same. The values move from the API team to the platform team.

**Today.** Each release renders a `HorizontalPodAutoscaler` (3 to 5 pods at
80 % CPU) and a `PodDisruptionBudget` (`minAvailable: 1`) for its gateway
(`gateway/autoscaling.yaml`). Values keys: `gateway.autoscaling.*`,
`gateway.podDisruptionBudget.*`. All 12 files keep the defaults. The chart
can't set labels, resources or node placement on the gateway pods; the
mesh's proxy resources apply.
The API team sets these values.

**New design.** The request renders the ConfigMap `mto-api-gateway-infra`,
which `spec.infrastructure.parametersRef` names. Istio makes the autoscaler
and the disruption budget from it. The platform values have today's
defaults. Sources: [design §3.2](design.md), [parameters §2](parameters.md),
story G.21.

```yaml
gateway:
  autoscaling: { minReplicas: 3, maxReplicas: 5, targetCPUUtilizationPercentage: 80 }
  podDisruptionBudget: { minAvailable: 1 }
```

**What changes.** Callers: nothing. API team: no scaling values. Platform
team: one autoscaler per tenant gateway; the tenant's quota must allow the
minimum. Story G.1 built a minimum of 2, and story G.21 sets today's 3.

### UC-05 Gateway and waypoint metrics

**Status:** Same.

**Today.** Each release renders a `PodMonitor` for its gateway (port
`metrics`, path `/stats/prometheus`, every 30 s), and the release that creates
a waypoint also renders one for the waypoint. Kiali and Grafana read these
metrics. Values keys: `observability.podMonitor.enabled`, `.interval`. All 12
files keep the default (on).
The API team sets these values.

**New design.** The request renders the `PodMonitor` `mto-api-gateway`, and
the tenant's child renders `mto-api-gateway-waypoint` for each waypoint that
the extension renders. Platform values: `monitoring.podMonitor.enabled` and
`.interval` (`true`, `30s`). Sources: [design §3.2 and §3.5](design.md),
[gateway-baseline M23](gateway-baseline.md), AC-OPS-8.

**What changes.** Callers: nothing. API team: nothing. Platform team:
dashboards and alerts follow the new pod names (UC-06). A waypoint that the
extension doesn't render (UC-29, UC-30) keeps the `PodMonitor` of its
creator; when that creator is a per-API release, its `PodMonitor` goes with
the release.

### UC-06 Object names and labels

**Status:** Changed. The names are fixed and reserved.

**Today.** `gateway.name` names the `Gateway`, the `HTTPRoute`, the `Route`s
`<name>-internal` and `<name>-external`, the pods `<name>-istio`, the TLS
Secret, the autoscaler, the `PodMonitor` and the internal host. The release
name names the policies and filters (`<release>-<chart>-jwt` and others).
Every object carries the standard Helm labels. The API team sets the names.
All 12 files.

**New design.** The gateway is always `mto-api-gateway`, and its pods are
`mto-api-gateway-istio`. The tenant's objects are `mto-api-gateway-jwt`,
`-strip-headers`, `-ratelimit`, `-correlation-id`, `-telemetry` and `-apis`.
Each API has its `HTTPRoute` and status ConfigMap `api.<api>`, its rule
`api.<api>` and its lock `api.<api>.<service>`. Every object outside
`mto-api-gateways` starts with `mto-api-` or `api.` and carries the label
`api-gateway.stakater.com/managed: "true"`. Sources:
[design §6](design.md), [ADR-0001](adr/0001-template-operator-renders-everything.md),
[ADR-0002](adr/0002-one-gateway-per-tenant-requested-by-the-team.md).

**What changes.** Callers: nothing. API team: the request's name is free; it
names only the request's status ConfigMap. Platform team: dashboards,
alerts and the end-to-end runner's label targets follow the new names
([migration §3.h](migration.md)). A selector on today's Helm labels finds
nothing. Template Operator never takes over an object of today's charts,
because no name matches (AC-LIFE-7).

## 2. Hosts, paths and routes

### UC-07 Shared front-door host split by path

**Status:** Same. The platform now grants the path prefixes.

**Today.** All APIs of a cluster share one front-door host, and the path
selects the API. Each release renders a reencrypt OpenShift `Route`
`<name>-external` with the host and `gateway.pathPrefix`
(`gateway/route.yaml`). Routes in many namespaces claim one host, so the
router has `routeAdmission.namespaceOwnership: InterNamespaceAllowed`. The
router picks the longest path that matches. A public front door, outside the
charts, sends callers to this host and also fronts the realm. Values keys:
`gateway.hosts.external`, `gateway.pathPrefix`. 11 of the 12 files use it,
on two clusters. The API team sets the host and the path; the router setting
is the platform's.

**New design.** The platform grants each tenant path prefixes on the shared
host (`gateway.sharedHosts`). The tenant's request renders one reencrypt
`Route` for each granted prefix, to the `entry` listener. The `api` instance
sets `host` to the shared host and a `path` under one of the tenant's
prefixes. The API rule checks the host and the path, so APIs share the host
safely. Sources: [design §3.2 and §3.4](design.md),
[ADR-0005](adr/0005-an-api-is-a-templateinstance-checked-by-host-and-path.md),
[ADR-0009](adr/0009-a-tenant-serves-only-the-hosts-and-paths-it-is-granted.md),
[migration §1 and §3.f](migration.md).

```yaml
# platform values
gateway:
  baseDomain: apis.example.com
  sharedHosts:
    - host: front.example.com
      paths:
        team-a: [/orders-v2]          # shorter than today's path /orders-v2/v1
```

```yaml
# the API team's api instance, in the backend's namespace
apiVersion: templates.v2.stakater.com/v2alpha1
kind: TemplateInstance
metadata: { name: orders, namespace: team-a-dev }
spec:
  templateRef: { name: api, namespace: mto-api-gateways }
  parameters:
    - { name: host,    value: front.example.com }
    - { name: path,    value: /orders-v2/v1 }
    - { name: rewrite, value: /orders/v1 }
    - { name: service, value: orders }
    - { name: port,    value: "80" }
```

**What changes.** Callers: the same host, path and token. A path of no API
on the host gets `403` from the tenant gateway, not `404`. API team: sets
`host` and `path`, as today. Platform team: grants each tenant a prefix that
is shorter than today's per-API path, so the old `Route` keeps the traffic
until the switch. Admission refuses a tenant's own `Route` for the shared
host (story G.23). Story G.0 confirms that the router prefers the longest
path before any production move. The front door and its DNS stay with the
platform.

### UC-08 Internal host per API

**Status:** Changed. The platform grants the internal host to the tenant.

**Today.** Each gateway also answers on
`<gateway.name>-<gateway.namespace>.<internal domain>`, under the cluster
router's own domain, through a reencrypt `Route` `<name>-internal` with no
path. The router's wildcard certificate covers it. The route, the
authorization policy and the rate limit entries also name this host. Values
keys: `gateway.name`, `gateway.namespace`, `gateway.hosts.internalDomain`.
All 12 files render one. The host comes from the API team's values.
The platform team owns the router's domain.

**New design.** The platform sets `gateway.internalDomain` and grants each
tenant its internal hosts (`gateway.internalHosts`). The tenant's request
renders one reencrypt `Route` for each granted host, to the `entry`
listener. The `api` instance names one in `internalHost`, and the API then
also answers there, on the same path. APIs share an internal host by path.
Sources: [design §3.2 and §3.4](design.md),
[ADR-0009](adr/0009-a-tenant-serves-only-the-hosts-and-paths-it-is-granted.md),
[migration §3.a and §3.f](migration.md), AC-ISO-13.

```yaml
# platform values
gateway:
  internalDomain: apps.cluster.example.com
  internalHosts:
    team-a: [orders-team-a.apps.cluster.example.com]   # today's name: <gateway>-<namespace>
```

```yaml
# on the api instance
    - { name: internalHost, value: orders-team-a.apps.cluster.example.com }
```

**What changes.** Callers: nothing, when the platform grants today's name.
API team: names the host in `internalHost`. Platform team: grants only the
names that callers use ([migration §3.b](migration.md) reads the router's
access log). Each name is one DNS label under the domain. The switch deletes
the old gateway's internal `Route`, and the router then admits the tenant's
`Route` (gateway-baseline R5). Story G.0 measures how long the host has no
backend.

### UC-09 API with only an internal host

**Status:** Same.

**Today.** With `gateway.hosts.external: ""`, the release renders only the
internal `Route`, so the API has no public host. 1 values file uses it (the
load-test environment, which has no DNS for a public host yet). The API team
sets it. The file's comment says that the chart fails without a public host;
it does not.

**New design.** The `api` instance sets `host: "-"` and `internalHost`.
Sources: [design §3.4](design.md),
[ADR-0005](adr/0005-an-api-is-a-templateinstance-checked-by-host-and-path.md),
[migration §3.a](migration.md).

```yaml
  parameters:
    - { name: host,         value: "-" }
    - { name: internalHost, value: reports-team-a.apps.cluster.example.com }
    - { name: path,         value: /reports/v1 }
    - { name: service,      value: reports }
    - { name: port,         value: "80" }
```

**What changes.** Callers: nothing. API team: one more parameter. Platform
team: grants the internal host (UC-08).

### UC-10 Public path and path rewrite

**Status:** Same.

**Today.** The route publishes every path under `gateway.pathPrefix`
(`PathPrefix`, segment by segment). When the backend's prefix is different,
the route rewrites it (`ReplacePrefixMatch`). A rewrite to `/` serves a
backend from its root. Values keys: `gateway.pathPrefix`,
`backend.internal.pathPrefix`, `backend.external.pathPrefix`. All 12 files
set a path. 10 files rewrite it (5 of them to `/`), and 2 keep the backend's
path. The API team sets it.

**New design.** The `api` instance sets `path`, and `rewrite` when the
backend's path is different. The checks are the same: segments, no empty or
dot segment, no trailing `/`. Sources: [design §3.4](design.md),
[ADR-0005](adr/0005-an-api-is-a-templateinstance-checked-by-host-and-path.md).

```yaml
    - { name: path,    value: /orders-v2/v1 }
    - { name: rewrite, value: /orders/v1 }   # or "/"; leave it out when the paths are equal
```

**What changes.** Callers: nothing. API team: gives no backend path when it
equals the public path (today's chart requires it). Platform team: nothing.

### UC-11 Exact method and path operations

**Status:** Changed. A path or method outside the operations gets `403`, not
`404`.

**Today.** `gateway.matches` replaces the prefix match with `HTTPRoute`
matches, written in the CRD's own syntax. 2 values files (one API, test and
load test) publish one operation: `POST` on one exact path. The other paths
under the prefix stay unpublished, and a valid token on such a path gets
`404`. The API team sets it. The chart's comment says that an exact path
needs no rewrite, but no rule checks it.

**New design.** The `api` instance sets `operations`: `METHOD /exact/path`,
comma-separated, at most 10, each under `path`, and not with `rewrite`. The
route matches each exact path and method, and the API rule allows only
those. Sources: [design §3.4](design.md),
[ADR-0005](adr/0005-an-api-is-a-templateinstance-checked-by-host-and-path.md).

```yaml
    - { name: path,       value: /reports/v1 }
    - { name: operations, value: "POST /reports/v1/fetch" }
```

**What changes.** Callers: a valid token on a path or method that the API
doesn't serve gets `403` (the default deny), not `404` ([design §4](design.md)).
Callers and end-to-end checks that test for `404` change first
([migration §3.b](migration.md)). API team: one string instead of a match
list. Platform team: nothing.

### UC-12 Route features that no API uses

**Status:** Not supported, by decision: each feature becomes a parameter
when an API needs it ([ADR-0005](adr/0005-an-api-is-a-templateinstance-checked-by-host-and-path.md)).

**Today.** `gateway.matches` also accepts header and query matches, a method
on a prefix, an exact path for any method, and several prefixes for one API.
The route has one rule and one backend: no timeouts, retries, redirects,
CORS, weights, mirrors or header filters, so the defaults of Istio and the
router apply. No values file uses these.
The API team would set them.

**New design.** The `api` instance has only its parameters. Each new route
feature is a new parameter, with a story. A request header that the team
adds or removes is a possible later parameter. Sources:
[design §12](design.md), [parity §2](parity.md).

**What changes.** Nothing for today's APIs. A future API that needs a
feature asks the platform team for a story.

## 3. Backends

### UC-13 Backend in the gateway namespace

**Status:** Same.

**Today.** The backend Service is in the gateway's namespace. The route
names the Service and its port, and no `ReferenceGrant` is needed. Values
keys: `backend.internal.namespace`, `.service`, `.port`. 7 values files use
it: the five on the lab cluster (one echo Service) and two for one API in
shared namespaces. The runbook also names a team whose gateway and
application share one namespace. The chart refuses an internal and an
external backend together, and neither.
The API team sets it.

**New design.** The `api` instance lives in the backend's namespace and
names `service` and `port`; it sets exactly one of `service` and
`externalHost`. Its route attaches to the tenant gateway, which runs in this
namespace or in another namespace of the tenant. Sources:
[design §3.4](design.md),
[ADR-0005](adr/0005-an-api-is-a-templateinstance-checked-by-host-and-path.md),
AC-EXT-2.

```yaml
metadata: { name: orders, namespace: team-a-dev }   # the backend's namespace
spec:
  templateRef: { name: api, namespace: mto-api-gateways }
  parameters:
    - { name: path,    value: /orders/v1 }
    - { name: service, value: orders }
    - { name: port,    value: "80" }
```

**What changes.** Callers: nothing. API team: puts the instance in the
backend's namespace. Platform team: nothing. With the lock on, a backend
that the lock can't cover serves nothing (UC-28, [design §7](design.md)).

### UC-14 Backend in another namespace with a ReferenceGrant

**Status:** Changed. The route lives next to its backend, so there is no
`ReferenceGrant`.

**Today.** The gateway runs in its own namespace (usually one gateway
namespace per API and environment), and the backend in the application's
namespace. The release renders the route in the gateway's namespace, and a
`ReferenceGrant` in the backend's namespace for that one Service. The
gateway namespace is in the mesh but has no waypoint label. One release
writes into two namespaces. Values keys: `backend.internal.namespace`
different from `gateway.namespace`. 4 values files on the test cluster use
it, and the runbook calls it the usual layout.
The API team sets it; the platform team sets the namespace labels.

**New design.** The API team creates the `api` instance in the backend's
namespace. Its route lives there and attaches to the tenant gateway through
the listener's tenant selector. No `ReferenceGrant` is needed. The tenant
gateway can stay in today's gateway namespace: the team puts its request
there. The lock renders in the route's namespace. Sources:
[design §3.4 and §11](design.md), [parameters §1](parameters.md),
[gateway-baseline A1, A2](gateway-baseline.md).

```yaml
# the gateway request, in today's gateway namespace
metadata: { name: api-gateway, namespace: team-a-dev }
---
# the API, in the backend's namespace
metadata: { name: payments, namespace: team-a-test }
spec:
  templateRef: { name: api, namespace: mto-api-gateways }
  parameters:
    - { name: host,    value: front.example.com }
    - { name: path,    value: /payments/v2 }
    - { name: rewrite, value: /payments/v1 }
    - { name: service, value: payments }
    - { name: port,    value: "80" }
```

**What changes.** Callers: nothing. API team: writes the `api` instance in
the backend's namespace, not in the gateway's. Platform team: both
namespaces must belong to one tenant; a backend in another tenant's
namespace can't use this gateway. Both namespaces need the mesh's discovery
label (UC-40).

### UC-15 Backend outside the cluster with TLS

**Status:** Same ([ADR-0014](adr/0014-an-api-backend-can-be-outside-the-cluster.md)).

**Today.** For a host outside the cluster, the release renders in the
gateway's namespace a `ServiceEntry` (`MESH_EXTERNAL`, DNS), a
`DestinationRule` (TLS `SIMPLE`, `MUTUAL` or `DISABLE`, the SNI, and a Secret
with `ca.crt`) and an `ExternalName` Service `<name>-upstream`. The route
rewrites the `Host` header and the path. There is no lock, and the token is
not forwarded. Values keys: `backend.external.host`, `.port`, `.pathPrefix`,
`.tls.mode`, `.tls.sni`, `.tls.credentialName`. 1 values file uses it (`SIMPLE`
with a private CA). The runbook names one more team with a backend outside
the cluster. The same file sets lock values "by convention only"; the chart
ignores them.
The API team sets it.

**New design.** The `api` instance sets `externalHost`, `port`, `rewrite`,
`tls`, `tlsSni` and `tlsSecret`. It renders the `ExternalName` Service
`mto-api-<api>-external` and the route. The tenant's child renders the
`ServiceEntry` and the `DestinationRule` `api.<api>.external` in the
gateway's namespace. There is no lock, the gateway doesn't forward the token, and the
tenant's status lists the API under `external`. Sources:
[design §3.4](design.md),
[ADR-0014](adr/0014-an-api-backend-can-be-outside-the-cluster.md), AC-EXT-1,
story G.16.

```yaml
metadata: { name: partner, namespace: team-a-dev }
spec:
  templateRef: { name: api, namespace: mto-api-gateways }
  parameters:
    - { name: host,         value: front.example.com }
    - { name: path,         value: /partner-v2/1.0 }
    - { name: externalHost, value: api.partner.example.com }
    - { name: port,         value: "443" }
    - { name: rewrite,      value: /partner/api }
    - { name: tls,          value: SIMPLE }
    - { name: tlsSecret,    value: partner-ca }   # ca.crt, in the gateway's namespace
```

**What changes.** Callers: nothing. API team: copies the CA Secret into the
tenant gateway's namespace ([migration §3.a](migration.md)). The lock values
of today's file have no equivalent. Platform team: the cluster's network
lets the gateway reach the host ([design §10](design.md)).

### UC-16 Several gateways call one backend Service

**Status:** Same. After the move, one tenant gateway calls the Service.

**Today.** On the lab cluster, five releases in one namespace route to one
echo Service. Each release renders its own lock `ALLOW` for its own gateway
identity, and Istio adds the `ALLOW`s up. The runbook names one more such
namespace on the test cluster. 5 values files use it.
Each API team sets its own release, and no team sees the whole.

**New design.** In the end state, the tenant gateway calls the Service, and
each API renders its own `DENY` `api.<api>.<service>`; each allows only the
tenant gateway, so they agree. During the move, `migration.oldGateways`
lists, for each backend Service, the principals of every old gateway that
calls it, and [migration §3.d](migration.md) turns off every old lock on
that Service in one change. Story G.0 confirms on Service Mesh whether a
gateway's traffic passes the waypoint at all (gateway-baseline M4). Sources:
[ADR-0007](adr/0007-backends-are-locked-through-a-waypoint.md),
[parameters §2](parameters.md), [migration §1 and §3.d](migration.md).

```yaml
# platform values, during the move
migration:
  oldGateways:
    team-a-dev/orders:
      - cluster.local/ns/team-a-dev/sa/orders-gateway-istio
      - cluster.local/ns/team-a-dev/sa/payments-gateway-istio
```

**What changes.** Callers: nothing. API team: nothing. Platform team: lists
every old gateway for each Service while they run side by side. An old
gateway that can't move (UC-24) stays in the list until it goes.

### UC-17 One API on two public paths

**Status:** Changed. Two `api` instances with two names, and a separate
rate limit counter for each.

**Today.** Two releases publish one API on two paths of the shared host.
Both use the same allowed-API pattern, so the same roles work on both
paths. Because the rate limit takes the API name from that pattern, both
paths also count in one counter for each caller. On the test cluster, two
APIs each have two releases (an older and a newer path). On the lab
cluster, one API has a path for the platform's tokens and a shorter path
for a retired issuer's tokens (UC-24), on one backend. 6 values files (three
pairs) use it.

**New design.** One `api` instance for each path, with two names, and both
names mapped to the same old role name in `migration.legacyRoles`. Each API
has its own rule and its own counter. Sources:
[migration §3.a](migration.md),
[ADR-0006](adr/0006-allowed-api-rule-is-derived-and-tenant-qualified.md).

```yaml
migration:
  legacyRoles:
    team-a.orders:    api-orders-consumer
    team-a.orders-v1: api-orders-consumer
```

**What changes.** Callers: the same addresses and tokens. A caller that uses
both paths gets one limit for each path, not one shared limit. API team:
two instances. Platform team: maps both names. The parent refuses one old
role name mapped to APIs of two tenants, so both backends must be in one
tenant, or the second path needs new roles.

## 4. Token check and access

### UC-18 Token check against the realm of the environment

**Status:** Changed. Issuers are platform values, and the token comes only
from the `Authorization` header.

**Today.** `gateway.auth.enabled: true` renders a `RequestAuthentication` on
the gateway with the issuer `<host>/realms/<realm>`, the audiences, and the
keys from the realm's key address; istiod fetches the keys. Istio reads the
token from the `Authorization` header and from the `access_token` query
parameter, and doesn't forward it to the backend. No token or a wrong API
gives `403`, an invalid token gives `401`, and a token of another issuer
gives `403`. Values keys: `gateway.auth.enabled`, `gateway.auth.jwt.host`,
`.realm`, `.audiences`. 11 of the 12 files use it; the twelfth uses the
legacy mode (UC-24). The API team sets the issuer for each gateway. The
release's notes print it.

**New design.** The platform registers issuers (`auth.issuers`) with their
audiences, and `auth.defaultIssuers` names the default. An API can name
others with its `issuers` parameter (UC-20). Once per cluster, the token
floor (`DENY` without a valid token of a trusted issuer) and the default
deny live in the Istio root namespace. For each tenant, a
`RequestAuthentication` reads the token only from the `Authorization`
header. No value turns the check off. Sources:
[design §3.1, §3.3 and §4](design.md),
[ADR-0004](adr/0004-security-baseline-is-a-gateway-override.md),
[migration §1](migration.md).

```yaml
auth:
  issuers:
    test: { url: https://sso.example.com/realms/apis, audiences: [apis] }
  defaultIssuers: [test]
```

**What changes.** Callers: a token in `?access_token=` is refused;
[migration §3.b](migration.md) checks the old gateway's access log for it
first. A token of an issuer that the gateway doesn't trust gets `401`, not
`403`. No token, an invalid token and a wrong API keep their codes. API
team: no issuer values. Platform team: registers each realm once; its
tokens must carry `azp` and the allowed-APIs claim. The API's status
ConfigMap `api.<api>` replaces the release's notes.

### UC-19 Keys from another address and the CA that istiod trusts

**Status:** Same.

**Today.** When istiod can't reach the issuer's public host,
`gateway.auth.jwt.jwksUri` fetches the keys from an internal address of the
same realm, and the issuer still matches the token's `iss`. 6 values files
(test environment) use it. On the lab cluster, istiod trusts the internal
CA through the mesh chart (`pilot.trustedCA`), so 4 files there need no
override; the load-test file needs none either. Without that trust, istiod
uses a key set that refuses every token.
The API team sets `jwksUri`; the platform team sets the CA trust in the mesh chart.

**New design.** `auth.issuers.<name>.jwksUri`, once per issuer. Istio's
control plane must trust the CA of every issuer's key address; it is an
install requirement. Sources: [parameters §2](parameters.md),
[design §10](design.md), [migration §1](migration.md).

```yaml
auth:
  issuers:
    test:
      url: https://sso.example.com/realms/apis
      audiences: [apis]
      jwksUri: https://sso.cluster.example.com/realms/apis/protocol/openid-connect/certs
```

**What changes.** Callers: nothing. API team: nothing. Platform team: one
value per issuer instead of one per gateway, and it keeps the mesh's
trusted CA bundle. With no `jwksUri`, Istio uses OIDC discovery, which gives
the same keys for Keycloak.

### UC-20 Several realms on one cluster

**Status:** Same, through platform values.

**Today.** Each environment has its own Keycloak instance and realm. The
test cluster runs three environments, and so three realms. Each gateway's
values name the realm of its environment: on the test cluster, 6 files use
the test realm and 1 file the load-test realm. The lab cluster has its own
realm.
The realm administrator runs the realms; each API team names one in its values.

**New design.** Each realm is one entry in `auth.issuers`. A tenant uses its
default issuers (`auth.defaultIssuers` or `auth.tenantIssuers`), and an API
can name others in `issuers`. The token floor accepts every trusted issuer;
each tenant's check and each API rule accept only their own. Sources:
[ADR-0004](adr/0004-security-baseline-is-a-gateway-override.md),
[design §3.1](design.md), AC-AUTH-10, AC-AUTH-11.

```yaml
# platform values
auth:
  issuers:
    test:     { url: https://sso.example.com/realms/apis, audiences: [apis] }
    loadtest: { url: https://sso-load.example.com/realms/apis, audiences: [apis] }
  defaultIssuers: [test]
```

```yaml
# on the load-test API's instance
    - { name: issuers, value: loadtest }
```

**What changes.** Callers: nothing. API team: names a non-default issuer on
its `api` instance. Platform team: registers each realm. Two environments of
one tenant on one cluster share one gateway (UC-39).

### UC-21 Allowed-API rule

**Status:** Better. The rule is derived and closed, and today's role names
still work.

**Today.** An `AuthorizationPolicy` `ALLOW` on the gateway allows a request
only with a valid token whose `allowed_apis` claim matches a pattern in
`gateway.auth.jwt.allowedApis`, on the gateway's hosts. Every file uses the
free-text pattern `api-<api>-consumer-*`; nothing stops `*`. The pattern
accepts any tier string. The policy checks the host and the claim, not the
path. The same name must match the realm's roles and the rate limit, and no
chart checks the three together. 11 files use it. The API team sets it.

**New design.** For each API, the tenant's child renders the `ALLOW`
`api.<api>`: the route's host and path (or the exact operations), the API's
issuers, `azp` present, and the claim value `api.<tenant>.<api>` or
`api.<tenant>.<api>.*`. During the move, `migration.legacyRoles` maps the API
to today's role name, and the rule also accepts `<old>-<tier>` for each
tier that the platform defines, as exact values. Sources:
[design §3.5 and §5](design.md),
[ADR-0005](adr/0005-an-api-is-a-templateinstance-checked-by-host-and-path.md),
[ADR-0006](adr/0006-allowed-api-rule-is-derived-and-tenant-qualified.md),
AC-MIG-2.

```yaml
migration:
  legacyRoles:
    team-a.orders: api-orders-consumer   # accepts api-orders-consumer-gold, -silver, -bronze
```

**What changes.** Callers: the same tokens. A role with a tier that the
platform doesn't define (accepted today) is refused, so such a caller gets a
defined tier role first ([migration §3.c](migration.md)). API team: no
pattern to type; the API name is the instance's name. Platform team: maps
each API that moves. The rule also checks the path, so APIs share a host
(UC-07).

### UC-22 Caller headers set from the token

**Status:** Better. The header removal also covers the underscore variants.

**Today.** `gateway.auth.jwt.forwardClaims` writes claims into request
headers for the backend: `x-sub` from `azp` and `x-roles` from
`allowed_apis`. An `EnvoyFilter` removes the caller's copies of these
headers before the token filter runs, so a token without the claim can't
leave a forged value. Other caller headers, such as business ids that the
caller chooses for each request, pass through unchanged. The token itself
doesn't reach the backend. A backend may trust these headers only with the
lock on. 8 values files map both headers; the legacy file maps `x-sub` only.
The API team sets `forwardClaims`.

**New design.** The platform values `auth.headers.caller` (`x-sub`, from
`auth.claims.caller`, default `azp`) and `auth.headers.roles` (`x-roles`,
from `allowed_apis`) apply to every tenant gateway. The platform filter
`mto-api-gateway-strip-headers` removes the caller's copies of every claim
header, their underscore variants, and the names in `headers.removed`,
before the token filter. It never removes `authorization` or `host`. Other
headers pass through. Sources: [design §3.3 and §4](design.md),
[ADR-0003](adr/0003-istio-native-policies-and-platform-owned-envoyfilters.md),
[ADR-0004](adr/0004-security-baseline-is-a-gateway-override.md), AC-AUTH-4.

**What changes.** Callers: nothing. Backends: the same `x-sub` and `x-roles`
values; `x-roles` carries the list claim base64-encoded, as today
([design §12](design.md)). API team: nothing to set. Platform team: the
header names are platform values, the same for every tenant.

### UC-23 A team claim header

**Status:** Changed. The setting applies to the whole tenant gateway, and
`x-sub` and `x-roles` are always added too.

**Today.** One API maps its own claim to its own header: `client_id` to a
header with a name that the backend chooses. It maps no
`x-sub` and no `x-roles`. A token without the claim sets no header. A
version header from the caller passes through. 3 values files (one API: test,
load test and the lab cluster) use it. The API team sets it.

**New design.** The parameter `claimHeaders` on the gateway request: at
most 5 `claim=header` pairs, and a name in `headers.refusedTargets` is
refused. The claim is optional, as today; only `azp` is required. The
tenant's child adds these headers to `x-sub` and `x-roles`, and removes the
caller's copies. Sources: [design §8](design.md),
[ADR-0012](adr/0012-teams-tune-their-gateway-with-validated-parameters.md),
AC-KNOB-1.

```yaml
metadata:
  name: api-gateway
  namespace: team-a-dev
spec:
  templateRef: { name: api-gateway, namespace: mto-api-gateways }
  parameters:
    - { name: version,      value: "1.0.0" }
    - { name: claimHeaders, value: "client_id=x-client" }
```

**What changes.** Callers: nothing; a token without `client_id` still
passes. Backends: this API's backend also gets `x-sub` and `x-roles`, and
every API of the tenant gets the extra header (UC-38). API team: sets the
parameter once per tenant. Platform team: nothing.

### UC-24 Legacy issuer mode

**Status:** Not supported, by decision: the platform retires the issuer
([ADR-0004](adr/0004-security-baseline-is-a-gateway-override.md)).

**Today.** A separate release accepts the tokens of a retired issuer: the
issuer in `gateway.auth.legacy.issuer`, its public keys written into the
values (`jwks`), its audiences, an allow list of client IDs on `azp`
(`allowedClients`), and `x-sub` from `azp`. Nothing fetches keys. The tokens
carry no tier role, so the rate limit stays off. Only manual tests cover
it. 1 values file (lab cluster) uses it, on a short prefix of the shared
host that covers the retired issuer's old paths. The API team sets it.

**New design.** Not supported. Such an API stays on its old gateway until
its callers use the identity provider's tokens. The old release keeps its
`Route`, because admission lets Argo CD through
([ADR-0008](adr/0008-tenants-never-create-gateways-or-policies.md)). While it
runs, its principal stays in `migration.oldGateways` for its backend
Service. Sources: [design §12](design.md), [migration §3](migration.md).

**What changes.** Callers: nothing while the old gateway runs. API team:
keeps one old release. Platform team: keeps today's chart for that release
until the callers move.

### UC-25 A gateway with the token check off

**Status:** Not supported, by decision; a platform exemption for one API is
a later option ([design §12](design.md)).

**Today.** With `gateway.auth.enabled: false` and no legacy issuer, a release
renders no token check and no authorization policy: the gateway is open. No
rule in the chart stops it. No values file in the source does this; the
runbook says that one test gateway runs so.
The API team sets it.

**New design.** No API runs without a token check: the token floor and the
default deny hold on every gateway
([ADR-0004](adr/0004-security-baseline-is-a-gateway-override.md)). Such an
API stays on its old gateway.

**What changes.** Callers: must send a token before the API can move. API
team: keeps the old release. Platform team: decides later whether an
exemption for one API is necessary.

## 5. Rate limit per API

### UC-26 Tier rate limit on an API

**Status:** Better. No Lua, the tier from the role by exact text, and
counters per tenant, API, tier and caller.

**Today.** `rateLimit.enabled: true` renders an `EnvoyFilter`. A Lua filter
reads the caller's `allowed_apis` roles for the API, takes the highest tier
by `rateLimit.tierPrecedence` (gold, then silver, then bronze), and gives
bronze when it finds none. Envoy's rate limit filter then asks the shared
service, with the descriptors tier, API name (from the first allowed-API
pattern) and `sub`, on the virtual host of each host. The gateway fails open
(service down or slower than 0.25 s: the call passes). A limited call gets
`429`, with no `X-RateLimit-*` headers. A bug: an API name with a hyphen
never matches the Lua pattern, so every caller of such an API gets bronze.
8 values files use it, and the bug hits 6 of them (two APIs). The API team
turns it on; the platform team sets the tiers (UC-41).

**New design.** The tenant's child renders `mto-api-gateway-ratelimit` on
every tenant gateway: one entry for each API, matched on its host and path,
with the descriptors `tenant`, `api`, `tier` and `azp`. A CEL expression
finds the tier from the caller's role for the API (`api.<tenant>.<api>.<tier>`
or `<old>-<tier>`), from the highest rate down; no role gives the lowest
tier. The `api` instance's `rateLimit` is `"on"` by default. Sources:
[design §3.1 and §3.3](design.md),
[ADR-0003](adr/0003-istio-native-policies-and-platform-owned-envoyfilters.md),
[gateway-baseline M20](gateway-baseline.md), AC-RL-1 to AC-RL-4.

```yaml
# platform values (today's rates)
rateLimit:
  tiers:
    gold:   { requestsPerUnit: 100, unit: second }
    silver: { requestsPerUnit: 50,  unit: second }
    bronze: { requestsPerUnit: 10,  unit: second }
  defaultTier: bronze
  failureModeAllow: true
```

**What changes.** Callers: the callers of an API with a hyphen in its name
get the tier that their role names; a gold caller goes from 10 to 100 calls
per second. The API's owner confirms that the backend can take it before the
move ([migration §3.c](migration.md)). The counter keys on `azp` (the
client's ID), not `sub`; in a client-credentials token both name the same
client. Counters start again at zero at the move. A caller of two APIs keeps
two counters. A token without `azp` gets `403`. API team: nothing to set.
Platform team: one tier list for the filter and the service.

### UC-27 Rate limit off for an API

**Status:** Same.

**Today.** `rateLimit.enabled: false` (the default) renders no rate limit
filter. 4 values files use it: one API on test, load test and the lab
cluster (no limit until the backend has a load test; on the lab cluster, no
rate limit service in that release), and the legacy release.
The API team sets it.

**New design.** `rateLimit: "off"` on the `api` instance. The filter stays on
the gateway; the API gets no entry and so no counter, and the tenant's
status lists it. The platform can refuse `"off"` for a tenant
(`rateLimit.lockedTenants`), or exempt a tenant or one API
(`rateLimit.unlimitedTenants`, `rateLimit.unlimitedApis`). Sources:
[ADR-0004](adr/0004-security-baseline-is-a-gateway-override.md), AC-RL-5,
AC-RL-7.

```yaml
    - { name: rateLimit, value: "off" }
```

**What changes.** Callers: nothing. API team: one parameter. Platform team:
can lock the switch for a tenant.

## 6. Backend lock

### UC-28 Lock on with its own waypoint

**Status:** Better. The lock is a `DENY` that another policy can't widen.

**Today.** `security.allowGatewayAccessOnly: true` renders, in the backend's
namespace, an `AuthorizationPolicy` `ALLOW` on the backend Service: the open
paths for anyone (UC-32), every other path only for the gateway's service
account. A waypoint (class `istio-waypoint`) enforces it. With
`security.waypoint.create: true`, the release also renders the waypoint, its
autoscaler (3 to 5 pods at 80 % CPU), its disruption budget (1) and its
`PodMonitor`. The namespace must carry `istio.io/use-waypoint=<name>`, set in
the `Tenant`. The chart refuses the token check on an in-cluster backend
until the team chooses the lock or no lock. 9 values files lock their
backend, and 2 of them create the waypoint. The API team sets it.

**New design.** The lock is on by default (`backendLock: "on"`). The tenant's
child renders, in the route's namespace, the `DENY` `api.<api>.<service>`:
every path but the platform's open paths, from every identity but
`mto-api-gateway-istio`. It also renders the waypoint
`mto-api-gateway-waypoint` with its `parametersRef` ConfigMap (3 to 5 pods at
80 % CPU, disruption budget 1) and its `PodMonitor`, one for each namespace
with a locked API. The status checks the value of the namespace's waypoint
label. Sources: [design §3.5](design.md),
[ADR-0007](adr/0007-backends-are-locked-through-a-waypoint.md), AC-ISO-5.

```yaml
# Tenant (platform team): the backend namespace uses the extension's waypoint
spec:
  namespaces:
    metadata:
      specific:
        - namespaces: [team-a-dev]
          labels:
            istio-discovery: enabled
            istio.io/dataplane-mode: ambient
            istio.io/use-waypoint: mto-api-gateway-waypoint
```

**What changes.** Callers: nothing. API team: nothing; the lock is on by
default. Platform team: sets the label in the `Tenant`, and moves it from
today's waypoint at clean-up ([migration §3.h](migration.md)). The waypoint
stays while the label names it. Tenants can't take a Service or a pod out of
the waypoint
([ADR-0008](adr/0008-tenants-never-create-gateways-or-policies.md)).

### UC-29 Lock that reuses the waypoint of another release

**Status:** Same. A platform value replaces the team's `create: false`.

**Today.** A namespace has one waypoint. When several APIs share the
namespace, one release creates the waypoint and the others set
`security.waypoint.create: false` with its name. When the release that
created it goes, the waypoint goes for all of them. 5 values files reuse a waypoint in
their own namespace (4 on the lab cluster, 1 on the test cluster).
The API team sets it.

**New design.** The platform lists the namespace in
`backendLock.existingWaypoints`. The extension then renders no waypoint and
no waypoint `PodMonitor` there, and that waypoint enforces the lock. Without
an entry, the extension renders one waypoint for the namespace itself, so
no API owns it. Sources: [parameters §2](parameters.md),
[ADR-0007](adr/0007-backends-are-locked-through-a-waypoint.md),
[migration §1 and §2](migration.md), AC-ISO-14.

```yaml
backendLock:
  existingWaypoints:
    team-a-dev: shared-waypoint
```

**What changes.** Callers: nothing. API team: no waypoint values. Platform
team: lists the namespace during the move, then moves the label to
`mto-api-gateway-waypoint` and removes the entry
([migration §3.h](migration.md)). Today's chart renders a waypoint only while
its release's lock is on. So the release that owns the waypoint can't turn
its lock off ([migration §3.d](migration.md)) and keep the waypoint with
values alone.

### UC-30 Waypoint in another namespace

**Status:** Same.

**Today.** 2 values files (test cluster) use a waypoint that runs in the
gateway's namespace and that no release of the chart creates. The backend
namespace binds to it with `istio.io/use-waypoint` and
`istio.io/use-waypoint-namespace`, and the files set `waypoint.create: false`.
It is not known whether this layout still runs.
The API team sets the values; the platform team sets the labels and made the waypoint.

**New design.** `backendLock.existingWaypoints` with the waypoint's
namespace; the status checks both labels. At clean-up,
[migration §3.h](migration.md) removes `istio.io/use-waypoint-namespace` when
the namespace moves to the extension's waypoint. Source:
[ADR-0007](adr/0007-backends-are-locked-through-a-waypoint.md).

```yaml
backendLock:
  existingWaypoints:
    team-a-test: team-a-dev/shared-waypoint
```

**What changes.** Callers: nothing. API team: nothing. Platform team: lists
the namespace, and moves both labels at clean-up.

### UC-31 Lock off and direct backend access

**Status:** Same.

**Today.** `security.allowGatewayAccessOnly: false` with
`security.allowDirectBackendAccess: true` accepts that callers can reach the
backend without the gateway. The backend must then check the caller itself
and must not trust the headers. The files use it where a lock is not
possible: a shared namespace with many Services (the waypoint label would
cover all of them), a backend whose own `Route` is in use, and a namespace
without the ambient label. 2 values files (one API, test and load test) use
it.
The API team sets it.

**New design.** `backendLock: "off"` on the `api` instance. No lock and no
waypoint are rendered for it, and the status lists it under `unlocked`. The
platform can refuse it for a tenant (`backendLock.lockedTenants`). The
route's namespace still needs the mesh's discovery label
([design §7](design.md), `outside-mesh`); the ambient label is optional with
the lock off. Sources:
[ADR-0007](adr/0007-backends-are-locked-through-a-waypoint.md), AC-ISO-11.

```yaml
    - { name: backendLock, value: "off" }
```

**What changes.** Callers: nothing. API team: one parameter. Platform team:
checks that the namespace has the discovery label; a gateway in that
namespace needs it today too.

### UC-32 Open paths for probes and scrapers

**Status:** Changed. One platform list, not a value in each release.

**Today.** `security.publicPaths` keeps exact paths open to any caller on a
locked backend: `/metrics`, `/health`, `/health/live`, `/health/ready`,
`/healthz`. Patterns are not allowed: `/actuator/*` would also open
`/actuator/env`. The 9 locked files keep the default.
The API team can change the list.

**New design.** `backendLock.publicPaths`, with the same default and exact
paths only; a render check refuses a pattern. Sources:
[ADR-0007](adr/0007-backends-are-locked-through-a-waypoint.md), AC-ISO-11.

**What changes.** Callers: nothing. API team: can't open a path. Platform
team: owns the list for every tenant.

### UC-33 STRICT mTLS on backend pods

**Status:** Changed. The platform turns it on for a tenant, not the team for
an API.

**Today.** `security.backendPodLabels` renders a `PeerAuthentication`
`STRICT` on the backend pods. Plaintext callers from outside the mesh are
refused, also on the open paths. No values file uses it.
The API team would set it.

**New design.** `backendLock.strictMtlsTenants`: for a listed tenant, a
`PeerAuthentication` `api.<api>.<service>` on the pods that each locked
Service selects. It is off by default, because a scraper outside the mesh
can then no longer read `/metrics`. Sources:
[ADR-0007](adr/0007-backends-are-locked-through-a-waypoint.md),
[gateway-baseline M24](gateway-baseline.md), AC-ISO-12.

```yaml
backendLock:
  strictMtlsTenants: [team-a]
```

**What changes.** Nothing today, because no API uses it. The platform team
decides for each tenant.

### UC-34 The waypoint covers the whole namespace

**Status:** Better. The design states the effect, keeps the waypoint while
the label names it, and refuses opt-out labels.

**Today.** `istio.io/use-waypoint` on a namespace sends every Service of the
namespace through the waypoint, also the Services that are not APIs. The
chart's notes say that their own `Route`s that skip the gateway are refused.
This is why a shared namespace runs with the lock off (UC-31). Calls to a
pod's IP, and calls from outside the mesh, skip the waypoint. The
namespace's Services must not carry the label themselves, but nothing
enforces this. When the release that created the waypoint goes, the whole
namespace loses it.
The platform team sets the label in the `Tenant`.

**New design.** The same effect. The waypoint stays while the namespace's
label names it, also with no locked API left, and the status lists it under
`idle-waypoints`. Admission refuses `istio.io/use-waypoint` and
`istio.io/use-waypoint-namespace` on a tenant's Service or pod; a backend that
carries one is listed under `lock-bypass` and serves nothing. Calls to a
pod's IP and from outside the mesh still skip the waypoint; STRICT mTLS
closes the second (UC-33). Sources: [design §7 and §12](design.md),
[ADR-0007](adr/0007-backends-are-locked-through-a-waypoint.md),
[ADR-0008](adr/0008-tenants-never-create-gateways-or-policies.md).

**What changes.** Callers: nothing. API team: can't label a Service out of
the waypoint. Platform team: decides for each namespace, and moves the label
to retire a waypoint.

## 7. Correlation, logs and traces

### UC-35 Correlation ID

**Status:** Same. The knob applies to the tenant gateway, and the header
name is a platform value.

**Today.** `gateway.headers.correlationId.enabled: true` renders an
`EnvoyFilter` that adds the correlation header from Envoy's `x-request-id`
when the caller sent none; a caller's value stays. With telemetry on, the
header is also a trace tag. 7 values files use it: all five on the lab
cluster, and one API's test and load-test files. That API's backend needs
the header, and makes its own id without it, which breaks the chain back to
the caller. The API team turns it on; the header name is a chart default.

**New design.** The parameter `correlationId: "on"` and the platform's
header name `correlationId.header`, set to today's name at the move. The
filter is `mto-api-gateway-correlation-id`. With the telemetry settings on, the
header is a trace tag. Sources: [design §3.3 and §8](design.md),
[ADR-0012](adr/0012-teams-tune-their-gateway-with-validated-parameters.md),
[migration §1](migration.md), AC-KNOB-1.

```yaml
# platform values
correlationId:
  header: x-correlation-id        # today's header name
```

```yaml
# on the gateway request
    - { name: correlationId, value: "on" }
```

**What changes.** Callers: nothing. API team: one parameter for the tenant;
every API of the tenant gets the header. Platform team: sets the header name
once.

### UC-36 JSON access log and full trace sampling

**Status:** Same. The knob applies to the tenant gateway, and the platform
lists the providers.

**Today.** `gateway.telemetry.enabled: true` renders a `Telemetry` for the
gateway's pods: a JSON access log provider of the mesh (default: the shared
JSON format) and 100 % trace sampling (the mesh default is 1 %). The
correlation header and every claim header become trace tags. The tracing
provider is the mesh's. 6 values files use it (five on the lab cluster, one
for load test); 4 of them use the shared format. The mesh must define the
provider, or istiod refuses the `Telemetry`.
The API team sets it; the platform team defines the providers in the mesh.

**New design.** The parameter `accessLog` names a provider from
`telemetry.accessLogProviders`. With `telemetry.tracing.enabled`, the
`Telemetry` samples `telemetry.tracing.samplingPercentage` (default 100) and
tags the correlation header and every claim header, as today. The preflight
checks that the providers exist in the mesh. Sources:
[design §3.3, §8 and §9](design.md),
[ADR-0012](adr/0012-teams-tune-their-gateway-with-validated-parameters.md),
[migration §1](migration.md).

```yaml
# platform values: they can't default to today's, so the move sets them
telemetry:
  accessLogProviders: [json-default, json-team]
  tracing: { enabled: true, samplingPercentage: 100 }
```

```yaml
# on the gateway request
    - { name: accessLog, value: json-default }
```

**What changes.** Callers: nothing. API team: one parameter for the tenant.
Platform team: sets the two values. A gateway without the knobs follows the
mesh's sampling rate, as today.

### UC-37 An API log format and extra trace headers

**Status:** Changed. The setting applies to the tenant gateway, not to one
API.

**Today.** One API selects its own JSON access log provider (the shared
fields, plus its business headers and the correlation header) and two extra
trace headers that the caller sends. 3 values files (one API) set it; in the
test environment it is set but off. The provider lives in the shared mesh
chart.
The API team sets it; the platform team defines the provider.

**New design.** The parameters `accessLog` (that provider) and
`traceHeaders` (at most 5 headers) on the tenant's request. Every API of
the tenant gets the same log format and tags. Sources:
[design §8](design.md),
[ADR-0012](adr/0012-teams-tune-their-gateway-with-validated-parameters.md).

```yaml
    - { name: accessLog,    value: json-team }
    - { name: traceHeaders, value: "x-transaction-id,x-version" }
```

**What changes.** Callers: nothing. API team: the setting applies to every
API of the tenant (UC-38). Platform team: lists the provider.

## 8. Tenancy and layout

### UC-38 Different settings for APIs in one namespace

**Status:** Changed. Gateway settings apply to the whole tenant
([design §12](design.md)).

**Today.** Each release has its own settings, so APIs in one namespace can
differ. On the lab cluster, one namespace runs five gateways: one API maps
its own claim header, logs with its own format and has no rate limit; the
others map `x-sub` and `x-roles` and log with the shared format. 5 values
files.
Each API team sets its own release.

**New design.** One gateway per tenant, so one set of claim headers,
correlation ID, log provider and trace headers. The rate limit and the lock
stay per API. The APIs agree on one set, keep their old gateways, or wait
for a second gateway (story G.12). A union often works: claim headers are
optional and are added to `x-sub` and `x-roles`; a log format that holds all
fields serves all APIs, with empty fields for the others; extra trace tags
do no harm. Sources: [design §12](design.md),
[ADR-0012](adr/0012-teams-tune-their-gateway-with-validated-parameters.md),
[migration §3.b](migration.md).

```yaml
  parameters:
    - { name: version,       value: "1.0.0" }
    - { name: claimHeaders,  value: "client_id=x-client" }
    - { name: correlationId, value: "on" }
    - { name: accessLog,     value: json-team }        # holds the shared fields too
    - { name: traceHeaders,  value: "x-transaction-id,x-version" }
```

**What changes.** Callers: nothing. Backends: can get headers that they did
not get before (UC-23). API team: agrees on one set for the tenant. Platform
team: nothing, or story G.12 when a tenant needs two sets.

### UC-39 Several environments of one team on one cluster

**Status:** Changed. One gateway per tenant, also across environments
([ADR-0002](adr/0002-one-gateway-per-tenant-requested-by-the-team.md)).

**Today.** Each team is one tenant. Inside the tenant, each environment has
its own gateway namespace and application namespace. On the test cluster, a
team has a test environment, a second test environment and a load-test
environment; two environments can also share one production cluster. Each
environment has its own gateways and its own realm. Each values file is one
API in one environment.
The platform team makes the namespaces in the `Tenant`; the API team makes one release for each API and environment.

**New design.** The tenant has one gateway, and its environments share it:
its pods, its settings and its issuers. API names are unique in a tenant, so
the same API in two environments needs two `api` instances with two names
(mapped to the same old role name, UC-17), each with its own host or path
and its own `issuers`. The rate limit counts for each API name. To keep
environments apart, the platform makes one tenant per environment, uses one
cluster per environment, or later uses story G.12. Sources:
[ADR-0002](adr/0002-one-gateway-per-tenant-requested-by-the-team.md),
[design §12](design.md), [parameters §3](parameters.md).

```yaml
# one tenant, two environments on one cluster
metadata: { name: orders, namespace: team-a-dev }
spec:
  templateRef: { name: api, namespace: mto-api-gateways }
  parameters:
    - { name: host,    value: orders.team-a.apis.example.com }
    - { name: path,    value: /orders/v2 }
    - { name: service, value: orders }
    - { name: port,    value: "80" }
---
metadata: { name: orders-test, namespace: team-a-test }
spec:
  templateRef: { name: api, namespace: mto-api-gateways }
  parameters:
    - { name: host,    value: orders-test.team-a.apis.example.com }
    - { name: path,    value: /orders/v2 }
    - { name: service, value: orders }
    - { name: port,    value: "80" }
    - { name: issuers, value: loadtest }
```

**What changes.** Callers: nothing, when each environment keeps its host and
path. API team: one API name for each environment. Platform team: decides
for each team between one tenant with a shared gateway and one tenant per
environment. In one tenant, a load peak in one environment reaches the
others.

### UC-40 Namespace labels from the Tenant

**Status:** Better. The extension reports a label that is not there or is wrong.

**Today.** Every gateway and backend namespace needs `istio-discovery=enabled`
(istiod reads only such namespaces) and `istio.io/dataplane-mode=ambient`. A
locked backend namespace also needs `istio.io/use-waypoint=<name>`. The
platform team sets them in the Multi-Tenant Operator `Tenant`; the chart
can't. A missing label fails silently: Helm succeeds, and the gateway is
never `Programmed`. Ambient mode also needs OVN-Kubernetes
`routingViaHost: true` on the cluster.

**New design.** The labels stay in the `Tenant`. The tenant's status lists a
route whose namespace lacks the discovery label (`outside-mesh`: it serves
nothing, with or without the lock), a locked API whose namespace lacks the
ambient label or names another waypoint, and the gateway's `Programmed`
condition. The platform team also labels the extension's namespace
`mto-api-gateways`, and the preflight checks it. Sources:
[design §7, §9 and §10](design.md), [migration §1 and §2](migration.md),
story G.6.

```yaml
# the extension's own namespace (platform team, once per cluster)
apiVersion: v1
kind: Namespace
metadata:
  name: mto-api-gateways
  labels:
    istio-discovery: enabled
    istio.io/dataplane-mode: ambient
```

**What changes.** Callers: nothing. API team: sees why an API doesn't serve
in `mto-api-gateway-apis`. Platform team: the same labels, and one more
namespace.

## 9. Shared rate limit service

### UC-41 Rate limit service and tiers

**Status:** Same. The bootstrap chart deploys the service from platform
values.

**Today.** The rate limit chart runs `envoyproxy/ratelimit` in a platform
namespace: gRPC on 8081 with `appProtocol: grpc`, and a debug port on 6070.
Its configuration has a domain, the tree tier → API → caller, gold 100, silver
50 and bronze 10 calls per second, and a fallback of 10 per second for an
unknown tier. The image is pinned by digest. A change of the limits rolls the
pods, because the service reads its configuration once. A local cache
answers callers that are already over their limit (16 MiB). The service
exports no metrics. Any pod can call it. Values keys: `domain`, `tiers.*`,
`ratelimit.*`. 1 defaults file; the per-cluster values are in another
repository. The runbook quotes gold at 1000 per second; the chart says 100.

**New design.** The bootstrap chart renders `ratelimit` in
`mto-api-gateways` (Deployment, Service, autoscaler, disruption budget,
ServiceAccount `ratelimit`), an `AuthorizationPolicy` that allows only tenant
gateways, and the immutable ConfigMap `ratelimit-config-<hash>`: domain
`mto-api-gateway`, the tree tenant → API → tier → `azp`, and the default tier
for an unknown tier. A change of the limits makes a new ConfigMap and rolls
the pods. Sources: [design §3.1](design.md),
[ADR-0003](adr/0003-istio-native-policies-and-platform-owned-envoyfilters.md),
AC-RL-8, AC-RL-9.

```yaml
rateLimit:
  service:
    image: envoyproxy/ratelimit@sha256:<a multi-arch digest that the release tested>
    logLevel: info
    redisPoolSize: 32
    localCacheSizeBytes: 16777216
    resources:
      requests: { cpu: 200m, memory: 256Mi }
      limits: { cpu: "1", memory: 512Mi }
```

**What changes.** Callers: the same limits; counters start again at the
move. API team: nothing. Platform team: runs the new service next to
today's until the last API moves ([migration §4](migration.md)), and
confirms which gold rate is live. Only gateways can now call the service,
so no pod can use up another tenant's counters.

### UC-42 Rate limit service availability

**Status:** Same.

**Today.** 3 to 8 pods at 70 % CPU. At least 2 pods stay available in a
drain (the budget renders only above one replica). Pods spread over hosts
and zones, and a rollout adds one extra pod and makes none unavailable.
Health probes call `/healthcheck`, which fails without a live Redis
connection (startup, readiness and liveness). Gateways fail open. A Redis
password change rolls the pods. Values keys: `ratelimit.autoscaling.*`,
`ratelimit.pdb.minAvailable`, `ratelimit.redisHealthCheckActiveConnection`;
the gateway's `rateLimit.failureModeAllow`.
The platform team sets them; the API team sets the failure mode.

**New design.** The same defaults as platform values:
`rateLimit.service.autoscaling.*` (3, 8, 70),
`rateLimit.service.podDisruptionBudget.minAvailable` (2),
`rateLimit.service.redisHealthCheck` (`true`),
`rateLimit.failureModeAllow` (`true`, fail open, documented as a limit), and
`rateLimit.redis.passwordRevision`, which rolls the pods on a password
change. Sources: [design §3.1](design.md), [parameters §2](parameters.md),
[ADR-0015](adr/0015-teams-choose-their-gateway-version.md),
AC-RL-6.

**What changes.** Callers: nothing. API team: nothing. Platform team:
changes `passwordRevision` with the Redis password (UC-62).

### UC-43 One rate limit replica on a small cluster

**Status:** Same.

**Today.** The lab cluster's values turn the autoscaler off and run 1 rate
limit pod (so no disruption budget), and 1 Redis node with 1 Sentinel. A
restart loses the counters. 1 values file.
The platform team sets it.

**New design.** `rateLimit.service.autoscaling.minReplicas: 1`; the
disruption budget is then not rendered, and the values schema refuses a
`minAvailable` that is not below the minimum. Redis is the platform's.
Sources: [design §3.1](design.md), [parameters §2](parameters.md).

```yaml
rateLimit:
  service:
    autoscaling: { minReplicas: 1, maxReplicas: 1 }
  redis:
    type: sentinel
    address: [redis-node-0.redis-headless.redis.svc.cluster.local:26379]
```

**What changes.** Nothing.

### UC-44 Redis with Sentinel and its password

**Status:** Stays with the platform.

**Today.** The rate limit chart includes Redis (a Bitnami subchart): 3 nodes
with Sentinel (master set `mymaster`), append-only persistence on 1 Gi, and a
password in a SealedSecret that the chart owns, so a render never changes
it. Sentinel has no password, because the client authenticates only the
data connection. An `AuthorizationPolicy` allows only the rate limit
service's identity and Redis itself. Values keys: `redis.*`.
The platform team sets it.

**New design.** Redis is a prerequisite, not rendered. Bootstrap values
name it: `rateLimit.redis.type` (`sentinel`), `.address` (the Sentinel
addresses), `.sentinel.masterSet`, `.passwordSecret` and `.passwordKey`
(`redis-password`, in `mto-api-gateways`), and `.passwordRevision`. Today's
Redis can serve both services, because the domains differ, so the keys
differ. Its policy must first also allow
`cluster.local/ns/mto-api-gateways/sa/ratelimit`. Sources:
[design §2 and §10](design.md), [migration §1](migration.md).

```yaml
rateLimit:
  redis:
    type: sentinel
    sentinel: { masterSet: mymaster }
    address:
      - redis-node-0.redis-headless.redis.svc.cluster.local:26379
      - redis-node-1.redis-headless.redis.svc.cluster.local:26379
      - redis-node-2.redis-headless.redis.svc.cluster.local:26379
    passwordSecret: ratelimit-redis
    passwordKey: redis-password
    passwordRevision: "1"
```

**What changes.** Callers: nothing. API team: nothing. Platform team: keeps
Redis, copies the password Secret into `mto-api-gateways`, and adds the new
principal. After the last move, it removes today's rate limit service and
its entry in Redis' policy ([migration §4](migration.md)).

## 10. Realm and consumers

### UC-45 Realm import per environment

**Status:** Stays with the platform.

**Today.** The realm chart imports one realm into one Keycloak instance per
environment, through a `KeycloakImport` of Stakater's RHBK operator. It
renames the exported realm at render, pins the issuer with `frontendUrl` in
one environment, and imports the whole realm again on every sync
(`overrideIfExists: true`). The base export also holds a public client with
direct grants, the default scopes, the key providers and the realm
policies. 4 values files (defaults and three environments). The realm
administrator sets it.

**New design.** Not rendered ([design §2](design.md)). The tenant gateway
reads today's tokens and roles. `auth.issuers.<name>.url` equals the pinned
issuer. Source: [parity §12](parity.md).

**What changes.** Nothing. After a move, the realm chart's note about
`realmRevision` no longer applies (UC-49).

### UC-46 Roles per API and tier

**Status:** Stays with the platform. Roles made from the `api` instance are
Later (story G.11).

**Today.** The realm chart makes every role `api-<api>-consumer-<tier>` from
`realm.apis` × `realm.tiers` (four APIs, three tiers), and removes other
roles of that form. Each API name must match a gateway's allowed-API
pattern, and each tier must exist in the rate limit service. No chart checks
the three together.
The realm administrator sets it.

**New design.** The tenant gateway accepts today's roles through
`migration.legacyRoles`. A new API maps to an old-form role name the same
way, while the realm chart makes only old-form roles. Roles of the form
`api.<tenant>.<api>.<tier>`, made from the `api` instance, are story G.11.
The tier names are one platform list for the filter and the service.
Sources: [ADR-0006](adr/0006-allowed-api-rule-is-derived-and-tenant-qualified.md),
[design §12](design.md).

```yaml
migration:
  legacyRoles:
    team-a.orders:  api-orders-consumer
    team-a.reports: api-reports-consumer    # a new API, while the realm chart makes old-form roles
```

**What changes.** Callers: the same roles. API team: nothing. Platform team:
still adds each API to `realm.apis`, and maps it once. A later rename to
`api.<tenant>.<api>.<tier>` changes every caller's token
([migration §4](migration.md)).

### UC-47 Consumer clients mappers and secrets

**Status:** Stays with the platform.

**Today.** Each `consumers.clients` entry `<client>:<api>:<tier>` becomes a
confidential client with only the client-credentials grant, a service account
with its roles, an audience mapper (the gateways' audience in `aud`) and an
`allowed_apis` mapper (all realm roles in one list claim). The client
secrets come from a sealed Secret, one key per client. The chart refuses a
malformed entry, a reserved client ID, an unknown role, two tiers for one API
on one client, and a missing secret. 3 environment files use it.
The realm administrator sets it.

**New design.** Not changed. The gateway needs `azp`, the audience and the
allowed-APIs claim in each token ([design §10](design.md)); today's clients
have them.

**What changes.** Nothing.

### UC-48 Token lifetimes

**Status:** Stays with the platform.

**Today.** `realm.timeouts.accessTokenLifespan` (300 s) and
`ssoSessionMaxLifespan` (36000 s); the chart fails when Keycloak would cut
the lifetime without a message. A longer life lets a revoked or re-tiered
client work until its token expires.
The realm administrator sets it.

**New design.** Not changed. The token life also limits how long old tokens
fail after a key change ([design §12](design.md), UC-49).

**What changes.** Nothing.

### UC-49 Realm import again and new signing keys

**Status:** Changed. The mesh reloads keys every 3 minutes, and
`realmRevision` goes. A signing key that never changes is Later (story G.27).

**Today.** Each import of the realm makes new signing keys. The realm chart
tells the administrator to change `gateway.auth.jwt.realmRevision` on every
gateway, which rolls the gateway pods; no values file sets it, and it is not
known whether it refreshes istiod's keys. The realm chart can pin a signing
key in its own sealed Secret, at a priority above the generated key; it is
off everywhere. No chart sets istiod's key refresh (Istio's default is
20 minutes).

**New design.** No `realmRevision`. The mesh setting
`PILOT_JWT_PUB_KEY_REFRESH_INTERVAL=3m` is an install requirement, and the
preflight checks it. After a key change, new tokens fail for up to
3 minutes, and tokens signed with the old key fail until callers get new
ones (up to the token life). Sources: [design §10 and §12](design.md),
[gateway-baseline M19](gateway-baseline.md), [parity §4](parity.md).

**What changes.** Callers: at most 3 minutes of `401` after a realm import,
instead of an unknown time. API team: no value to change. Platform team:
sets the mesh setting; it can turn on today's pinned key to remove the gap.

### UC-50 Consumer tooling

**Status:** Stays with the platform.

**Today.** Scripts next to the realm chart: create or update a client over
Keycloak's admin API (roles synced, other API roles removed, a secret made,
kept or rotated, and an optional scope that carries a version);
seal a new client secret for the environment and print the values lines;
make a secret (43 characters, base64url); seal the realm's signing key;
export one consumer's credentials to a document; export all to CSV. The two
routes don't mix: a client in the sealed values survives a realm import, a
client from the script doesn't. An older copy of the create script sits next
to the rate limit chart.
The realm administrator runs them.

**New design.** Not changed ([parity §12](parity.md)). The scripts assign
only old-form roles, which the tenant gateway accepts through
`migration.legacyRoles`.

**What changes.** Nothing.

## 11. End-to-end checks

### UC-51 End-to-end runner per API

**Status:** Stays with the platform. It is pointed at the tenant gateway at
the move.

**Today.** The end-to-end chart runs one check per API as a runner Job in one
namespace. It gets a real client-credentials token through the public front
door, and calls the API through the front door: anonymous must give `403`,
authenticated `200`. Then it calls in bursts until `429` (it assumes a
bronze client, at most 60 calls), and expects `200` again after the window.
It runs again when a watched workload rolls out (istiod, ztunnel, CNI, the
rate limit service, Redis, Keycloak, the API's gateway and backend); a patch
puts the watch label on those workloads. It prints a likely cause for each
status. It doesn't check the lock, the header removal, the correlation ID,
telemetry, gold or silver tiers, legacy gateways or TLS to an external
backend. 6 values files (defaults, test, production, and three APIs in
test).
The owner of the end-to-end checks sets it.

**New design.** Not changed; the extension's acceptance suite covers what
it doesn't check ([acceptance.md](acceptance.md)). The runner uses the same
front door, so its host and path stay. At the move, its label targets go to
`mto-api-gateway-istio` and to `ratelimit` in `mto-api-gateways`, and a
client whose tier rises needs a longer burst. Its `403` and `200` contract
holds. Sources: [migration §3.e](migration.md), [parity §13](parity.md).

**What changes.** Callers: nothing. API team: nothing. Platform team: changes
the watch groups and label targets, and keeps the runner's client on a
bronze role or makes the burst longer.

## 12. Mesh

### UC-52 Mesh installation and version

**Status:** Stays with the platform, with three new install requirements.

**Today.** The mesh chart installs the Service Mesh 3 operator and the Kiali
operator through OLM (channel `stable`, `Automatic` approval, a first
CSV); Istio in ambient mode (`profile: openshift-ambient`), IstioCNI and
ZTunnel, at one version (empty means the operator's latest); the discovery
selector `istio-discovery: enabled`; automatic mTLS; JSON logs for the mesh
components; resources for istiod, proxies, waypoints, CNI and ztunnel; no
mesh agents on control-plane and storage nodes; an optional trusted CA
bundle for istiod; and Argo CD sync waves. Two older charts (a pinned
operator with manual approval, and an Istio with the sidecar profile) look
superseded. OVN-Kubernetes `routingViaHost` is a cluster prerequisite.
The platform team sets it.

**New design.** Not changed; the mesh is the platform's
([design §10](design.md), [support-matrix.md](support-matrix.md)). New
requirements: the key reload interval of 3 minutes (UC-49); pinned mesh
upgrades (`Manual` approval or a pinned version), so the mesh never passes a
tested minor; and the revision-based update strategy when the platform moves
one tenant at a time (`gateway.meshRevision`). The preflight checks the
floors, the reload interval and the highest tested minor.

**What changes.** Callers: nothing. API team: nothing. Platform team: pins
the operator and the version, and sets the reload interval. A cluster below
OpenShift 4.20 upgrades first ([migration §1](migration.md)).

### UC-53 Mesh logs traces and metrics

**Status:** Stays with the platform.

**Today.** The mesh defines the access log providers (a shared JSON format
with the caller from the token, and one API's format with its business
headers), the OpenTelemetry tracing provider, a mesh-wide `Telemetry`
(Prometheus metrics, a text access log, 1 % tracing), and monitors for
istiod, CNI and ztunnel.
The platform team sets it.

**New design.** Not changed: the extension renders no access log provider
([design §2](design.md)). `telemetry.accessLogProviders` lists the names that
a team may choose, and the preflight checks that they exist. Observability
per tenant is story G.14.

**What changes.** Nothing. The platform team keeps the API's own provider in
the mesh, as today.

### UC-54 Kiali

**Status:** Stays with the platform.

**Today.** The Kiali server and its console plugin, pinned to a version that
the cluster's OpenShift console can load; OpenShift login; Grafana and the
cluster's Thanos as data sources; read access to cluster monitoring.
The platform team sets it.

**New design.** Not changed. Kiali sees the tenant gateways and waypoints
through their `PodMonitor`s (UC-05).

**What changes.** Nothing.

## 13. Across the charts

### UC-55 GitOps with Argo CD

**Status:** Same. Teams keep `TemplateInstance`s in Git.

**Today.** Everything is GitOps; nobody runs Helm by hand. The platform
charts sync from one Argo CD instance, with values for each cluster. Each
gateway is one Argo CD app in the teams' instance, pinned to a commit.
Renders must be the same under `helm template`, so secrets are sealed and no
chart uses `lookup`. The mesh chart orders objects with sync waves.

**New design.** The bootstrap chart syncs like today's platform charts. It
uses no `lookup`, and its preflight runs as a `PreSync` hook. A team keeps
its `api-gateway` and `api` instances in its own repository and syncs them
with its Argo CD app. Admission lets Argo CD and platform service accounts
through, so today's releases keep their objects during a move. Sources:
[design §9](design.md),
[ADR-0008](adr/0008-tenants-never-create-gateways-or-policies.md),
[gateway-baseline H1 to H3](gateway-baseline.md).

**What changes.** Callers: nothing. API team: its app syncs
`TemplateInstance`s instead of a chart. Platform team: one chart release.

### UC-56 Unsafe values fail at render

**Status:** Better.

**Today.** The gateway chart has 34 `fail` and `required` rules: for example,
audiences are required with the token check, an allowed-API pattern is
required, a lock choice is required, there is exactly one backend kind, and
legacy mode excludes the platform realm. Several unsafe combinations have no
rule: the token check off, the pattern `*`, an empty public host, a rewrite
with an exact match, both lock flags, two releases that create one waypoint,
and tier names that differ across the charts.

**New design.** Most switches are gone. The `api` Template checks every
parameter and writes `refused` with the reason. The tenant's child lists
conflicts, invalid backends and refused knobs. The values schema and the
render check guard the platform values and the rendered security. The
extension fails closed. Sources: [design §4, §7 and §9](design.md).

**What changes.** Callers: nothing. API team: reads a status ConfigMap
instead of a Helm error. Platform team: nothing.

### UC-57 Team copies of the chart

**Status:** Better. One platform chart, one upgrade.

**Today.** Each team keeps its own renamed copy of the base gateway chart in
its repository; the versions drift, and a fix is copied by hand. The
platform team, the realm administrator and the API team each own one part
of a new API.

**New design.** One bootstrap chart that the platform team owns; each team
chooses its version and moves when it is ready (UC-63). Sources:
[ADR-0001](adr/0001-template-operator-renders-everything.md),
[ADR-0015](adr/0015-teams-choose-their-gateway-version.md),
[raci.md](raci.md).

**What changes.** Callers: nothing. API team: no chart to keep. Platform
team: owns every upgrade (UC-63).

## 14. Day-2 operations

### UC-58 Onboard a new API

**Status:** Better. The API team writes one `api` instance; the platform team
still sets the roles and the labels.

**Today.** The runbook's steps:

1. The platform team adds the gateway namespace to the `Tenant`, with the
   mesh labels, and puts `istio.io/use-waypoint` on the application
   namespace.
1. The platform team adds the API client and the role
   `api-<name>-consumer-*` in the realm chart; the name must match
   `allowedApis`.
1. The API team writes the values (backend, path, host, allowed APIs, rate
   limit, waypoint) and an Argo CD app.
1. Both teams verify: no token gives `403`, a token gives `200` with the
   headers, a fast loop gives `429`, and a call from another pod is refused.

**New design.** The steps:

1. The platform team sets the namespace labels in the `Tenant` (UC-40), as
   today.
1. The platform team adds the API to `realm.apis` and maps it in
   `migration.legacyRoles` (UC-46), until story G.11 makes the roles from
   the `api` instance. It grants a shared-host prefix or an internal host
   when the API needs one.
1. The API team writes one `api` instance in the backend's namespace. The
   tenant needs its gateway request first, once.
1. Both teams verify with the API's status ConfigMap and the same four calls
   (UC-65).

Sources: [design §3.4 and §7](design.md),
[ADR-0005](adr/0005-an-api-is-a-templateinstance-checked-by-host-and-path.md),
[roadmap G.11](roadmap.md).

**What changes.** Callers: nothing. API team: one object, with no security
values. Platform team: one mapping per API until story G.11.

### UC-59 Change an API

**Status:** Same.

**Today.** The API team changes the host, the path, the backend or the
allowed APIs in its values, and commits; Argo CD syncs.

**New design.** The API team changes the `api` instance's parameters, and
commits. The route, the rule, the rate limit entry and the lock render
again. A host or a prefix that the tenant doesn't have yet needs a platform
grant. A new instance name is a new API, with a new rule. Source:
[ADR-0005](adr/0005-an-api-is-a-templateinstance-checked-by-host-and-path.md).

**What changes.** Callers: nothing. API team: parameters instead of values.
Platform team: grants hosts and prefixes.

### UC-60 Onboard a consumer

**Status:** Stays with the platform.

**Today.** The realm administrator seals a secret for the client, adds its
`<client>:<api>:<tier>` lines to the environment's realm values, and commits;
the realm is imported again. For one-off work, the create script makes the
client directly. The administrator then exports the credentials for the
consumer.

**New design.** Not changed. The gateway needs no change: the client's role
(old form, mapped) gives the access and the tier.

**What changes.** Nothing. Each realm import makes new signing keys, so
tokens can fail for up to 3 minutes (UC-49).

### UC-61 Change a tier or a rate

**Status:** Same. One tier list for the filter and the service.

**Today.** A consumer's tier: change its realm entry. A tier's rate: change
`tiers.<name>` in the rate limit chart; the pods roll. A new tier: change the
rate limit chart, the realm's `realm.tiers`, and each gateway's
`rateLimit.tierPrecedence`.
The realm administrator, the platform team and each API team each change one part.

**New design.** A consumer's tier: not changed (realm). A rate:
`rateLimit.tiers`; the pods roll with no failed request (AC-RL-8). A new
tier: `rateLimit.tiers` and the realm's `realm.tiers`. The rates give the
order, highest first, so there is no precedence list. A role with a tier
that the platform doesn't define is refused (UC-21). Sources:
[design §3.1](design.md),
[ADR-0003](adr/0003-istio-native-policies-and-platform-owned-envoyfilters.md).

**What changes.** Callers: nothing. API team: nothing. Platform team: no
precedence value per gateway.

### UC-62 Rotate keys and secrets

**Status:** Same, with a shorter key gap and an explicit Redis step.

**Today.** A client secret: the create script rotates it, or the
administrator seals a new value. The realm signing key: changes on each
import, unless the optional pinned key is on. The Redis password: a new
sealed value, whose checksum rolls the rate limit pods. The gateway's TLS
certificate: the service CA rotates it.

**New design.** Client secrets: not changed. Signing keys: the 3-minute
reload (UC-49), and story G.27 later. The Redis password: the platform team
changes the Secret in `mto-api-gateways` and
`rateLimit.redis.passwordRevision`. Gateway certificates: the service CA for
the `entry` listener, and the platform's issuer or Secret for the others.
Sources: [parameters §2](parameters.md), [design §3.2 and §12](design.md).

**What changes.** Callers: nothing. API team: nothing. Platform team: one
more value when it rotates the Redis password.

### UC-63 Upgrade the gateway chart and the mesh

**Status:** Better. The platform team installs once, and each team moves
when it is ready.

**Today.** Each team changes the version of its own chart copy. For Istio,
the platform team changes the version in the mesh values; the operator
upgrades in place, and istiod rolls the gateway and waypoint pods. OLM
upgrades the operators automatically. A hand-written `EnvoyFilter` can break
after an Istio upgrade, and nothing reports it.

**New design.** Stakater releases the bootstrap chart with a new semantic
version, tested first, with the versions of Stakater's support window. The platform
team installs it, which changes no tenant. Each team moves by changing
`version` on its gateway request, on the test cluster first and then in
production, and moves back the same way. Before a mesh minor upgrade, the upgrade suite runs on it
(story G.10); the platform can move one tenant's gateway at a time
(`gateway.meshRevision`). Pods restart one at a time. Sources:
[design §13](design.md),
[ADR-0015](adr/0015-teams-choose-their-gateway-version.md),
[support-matrix.md](support-matrix.md).

**What changes.** Callers: nothing. API team: one line per cluster for each
upgrade, when it is ready; no chart copy to upgrade. Platform team: installs
each release, and tells the teams about security fixes, with a deadline.

### UC-64 Offboard an API a consumer or a gateway

**Status:** Same. A delete removes what the instance rendered.

**Today.** The team removes the Argo CD app or the release: the gateway, the
routes and the policies go, and for the release that created it, the
namespace's waypoint goes too. A consumer: the administrator removes its
realm entry. Legacy support: remove its one release.

**New design.** Delete the `api` instance: its route, rule, rate limit entry
and lock go (AC-LIFE-2). The waypoint stays while the namespace's label
names it. Delete the gateway request: the tenant's gateway goes. Delete the
tenant: its gateway and child go (AC-LIFE-3). A consumer: not changed. After
a move, the platform uninstalls the per-API release
([migration §3.h](migration.md)).

**What changes.** Callers: nothing. API team: deletes one object. Platform
team: one API's removal no longer takes the namespace's waypoint with it.

### UC-65 Verify and troubleshoot an API

**Status:** Better. Status ConfigMaps say why an API doesn't serve.

**Today.** The release's notes print the hosts, the backend, the issuer and
the label commands. The runbook checks the discovery label on both
namespaces, the role name against `allowedApis` (`403` with a valid token),
`istio.io/use-waypoint` on the application namespace, and the gateway's
`Programmed` condition. The API team does first-line troubleshooting
(`401`, `403`, `429`, routing).

**New design.** The request's status `mto-api-gateway-status.<request>`, the
API's status `api.<api>`, and the tenant's `mto-api-gateway-apis` (for
example `outside-mesh`, `path-conflicts`, `lock-bypass`, `unlocked`,
`external`, `unattached`, and refused knobs); the gateway's `Programmed`
condition in the outputs (story G.6). The same four calls verify an API.
Sources: [design §7 and §9](design.md), AC-OPS-2.

**What changes.** Callers: nothing. API team: reads three ConfigMaps first.
Platform team: nothing.

### UC-66 Promote from test to production

**Status:** Same. The process is still to define.

**Today.** The same chart versions and layout run on both clusters, with
platform values for each cluster. How teams promote their apps is not
visible from the cluster.

**New design.** Between clusters, an `api` instance changes only its
namespace and its host. Each cluster runs a bootstrap chart version from the
support matrix. The process is still to define. Sources:
[parameters §3](parameters.md), [raci.md](raci.md),
[support-matrix.md](support-matrix.md).

**What changes.** Nothing yet.
