# API gateway baseline — what the platform gives, and where it stops

**Baseline:** Red Hat OpenShift Service Mesh **3.4** (Istio 1.30, Gateway API
GA) on OpenShift 4.20+, ambient mode; Red Hat build of Keycloak as the identity
provider; a shared Envoy global rate-limit service; the Multi-Tenant Operator
with Template Operator v2. Floor: OpenShift Service Mesh 3.3.

Every design decision cites a row here. Each row is marked **V** (verified in a
source read for this repo), **I** (inferred from verified facts) or **U**
(unknown — stated, not proven). **VERIFY** marks what a document could not
settle; each is a task in story **M.0**
(`docs/planning/M0-live-install-spike.md`). When the mesh, the gateway API or
the identity provider changes, update this file first, then the design.

> **Honesty note.** The Multi-Tenant Operator rows (T*) and the mesh
> authorization/ambient rows reuse what `mto-extension-service-mesh`'s baseline
> verified on 2026-10-11, cited here as `sm:<row>`. The gateway-specific rows
> (D*, J*, A*) describe the reference architecture and the Istio/Gateway-API
> model; several are marked **U**/**VERIFY** because they were not re-verified
> on a live install for this repo. Do not treat a **U** row as fact in a
> customer conversation until M.0 closes it.

Sources, short names:

- **inst-3.4** — `https://docs.redhat.com/en/documentation/red_hat_openshift_service_mesh/3.4/html-single/installing/`
- **rn-3.4** — `https://docs.redhat.com/en/documentation/red_hat_openshift_service_mesh/3.4/html-single/release_notes/`
- **i-gw** — `https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/`
- **i-ra** — `https://istio.io/latest/docs/reference/config/security/request_authentication/`
- **i-ap** — `https://istio.io/latest/docs/reference/config/security/authorization-policy/`
- **i-jwt** — `https://istio.io/latest/docs/tasks/security/authorization/authz-jwt/`
- **i-rl** — `https://istio.io/latest/docs/tasks/policy-enforcement/rate-limit/`
- **i-ef** — `https://istio.io/latest/docs/reference/config/networking/envoy-filter/`
- **i-wp** — `https://istio.io/latest/docs/ambient/usage/waypoint/`
- **i-l4** — `https://istio.io/latest/docs/ambient/usage/l4-policy/`
- **gw-api** — `https://gateway-api.sigs.k8s.io/` (Gateway, HTTPRoute, ReferenceGrant)
- **gw-rg** — `https://gateway-api.sigs.k8s.io/reference/api-types/referencegrant/`
- **gw-ns** — `https://gateway-api.sigs.k8s.io/guides/multiple-ns/`
- **ossm-gw** — `https://docs.redhat.com/en/documentation/red_hat_openshift_service_mesh/3.4/html-single/traffic_management/` (Gateway API, ingress)
- **rhbk** — `https://docs.redhat.com/en/documentation/red_hat_build_of_keycloak/` (realms, clients, client credentials, token claims)
- **ocp-route** — `https://docs.openshift.com/container-platform/latest/networking/routes/route-configuration.html` (re-encrypt)
- **sm-baseline** — `mto-extension-service-mesh/docs/service-mesh-baseline.md` (rows cited as `sm:<row>`)
- **to** — `stakater-ab/tenant-operator` (local `tenant-operator/`)
- **bao** — `mto-extension-openbao/charts/` (Template Operator v2 reference)
- **ref** — the reference architecture document this extension generalises (anonymised; on file with Rasheed, not in this repo)

---

## 1. Versions and lifecycle

| # | Fact | | Consequence | Source |
|---|---|---|---|---|
| V1 | OpenShift Service Mesh 3.4 (Istio 1.30) is the baseline; 3.3 the floor. Gateway API is GA for ingress (`Gateway` + `HTTPRoute`). | V | The extension writes only GA Gateway API and stable `security.istio.io/v1` objects. | sm:V1; rn-3.4 |
| V2 | A minor arrives roughly every four months; releases are supported ~18 months. | V | Prefer stable APIs; avoid Technology Preview so gateways ride upgrades. | sm:V2 |

## 2. Gateways (Gateway API)

| # | Fact | | Consequence | Source |
|---|---|---|---|---|
| J1 | A Gateway API `Gateway` with `gatewayClassName: istio` provisions its own Deployment and Service for the proxy; one per listener set. | V | One gateway per API per environment is one Deployment+Service each; cost scales with gateway count (ADR-0004, **Q10**). | i-gw; ossm-gw |
| J2 | A `Gateway` with `gatewayClassName: istio-waypoint` is a waypoint: an L7 proxy for a namespace or service, enrolled by the `istio.io/use-waypoint` label. | V | The backend side needs a waypoint per application namespace for L7 handling and mTLS termination to the backend (ADR-0005). | i-wp |
| J3 | A listener's `allowedRoutes.namespaces.from: Selector` limits which namespaces may attach routes; a cross-namespace `backendRef` needs a `ReferenceGrant` in the target namespace. | V | The gateway's `HTTPRoute` reaches a backend in the application namespace only with a rendered `ReferenceGrant` there (ADR-0005). | gw-ns; gw-rg |
| J4 | "It is recommended to restrict creation of `Gateway` resources to trusted cluster administrators." Each one is a new entry point. | V | Tenants must not hand-create gateways; the Template (a platform identity) renders them (ADR-0006; sm:R2). | i-gw; sm:R2 |
| J5 | The reference architecture fronts each gateway with an OpenShift `Route` (re-encrypt) for the external host; the `Route` forwards to the gateway Service. | V (ref) | The external host and TLS are an OpenShift `Route`; the gateway terminates and re-checks. **VERIFY** the re-encrypt/SNI handshake on the baseline (**Q7**). | ref; ocp-route |

## 3. Consumer authentication and authorization (north-south)

| # | Fact | | Consequence | Source |
|---|---|---|---|---|
| A1 | `RequestAuthentication` validates a JWT (issuer, JWKS, audiences) and populates `request.auth.claims`. With a `RequestAuthentication` present, a request **without** a token is **not** rejected by it alone — an `AuthorizationPolicy` must require the principal/claim. | V | Both objects are always rendered together; the `AuthorizationPolicy` requires a valid token (ADR-0002). A `RequestAuthentication` alone is the classic "forgot to deny" hole. | i-ra; i-jwt |
| A2 | An `AuthorizationPolicy` can require `request.auth.claims[<name>]` to match a value or prefix, and can match the request `host`. | V | Consumer authorization = the token carries a claim listing the APIs it may use; the policy requires the claim to match the derived `api-<apiName>-consumer-*` and the host to be this gateway's (ADR-0003). | i-ap; i-jwt |
| A3 | `RequestAuthentication`/`AuthorizationPolicy` attach to a workload by `selector`, or to a Gateway API `Gateway` by `targetRefs` (mutually exclusive). | V / U | The north-south policies must attach to the **gateway** (`targetRefs` → the `Gateway`), not a workload selector. **VERIFY** the exact `targetRefs` binding to an `istio` Gateway on 3.4 (**Q4**). | i-ap; sm:A7 |
| A4 | An inbound request can carry any header a caller sets, including identity headers the backend trusts (`x-sub`, `x-roles`). | V | The gateway must **strip** caller-supplied identity headers before it sets its own from the token, or a caller spoofs identity (ADR-0002). | i-ef; ref |
| A5 | The gateway sets backend-facing headers (`x-sub` from the token subject, `x-roles` from the consumer claim) and may rewrite the path (`/v2` → `/v1`). | V (ref) | Header-set and path-rewrite are gateway behaviour, baked in the Template; the backend trusts only what the gateway sets. | ref |

## 4. Rate limiting

| # | Fact | | Consequence | Source |
|---|---|---|---|---|
| D1 | Istio global rate limiting uses an external Envoy `ratelimit` service (+ Redis) that the proxy calls per request; it is configured today via `EnvoyFilter`. | V | The shared rate-limit service is a platform prerequisite; the gateway is wired to call it (ADR-0007). | i-rl |
| D2 | The reference architecture runs one shared rate-limit service with tiers (e.g. low/medium/high requests per second) selected per caller. | V (ref) | The tier is a parameter of the gateway (or of the consumer); enforcement is always on (ADR-0007). **VERIFY** whether the tier is chosen per gateway or per consumer token (**Q8**). | ref |
| D3 | Rate-limit wiring in the reference architecture is an `EnvoyFilter` on the gateway. | V (ref) | v1 may have to render an `EnvoyFilter` for the rate-limit hook and the header strip. | ref |
| D4 | `EnvoyFilter`: "incorrect configurations could potentially destabilize the entire mesh"; Istio discourages it and does not treat its schema as stable across versions. | V | An `EnvoyFilter` the extension owns is a maintenance and upgrade risk the platform carries. **VERIFY (Q1)** whether 3.4 offers a supported, non-`EnvoyFilter` rate-limit and header-strip path for a Gateway API gateway (e.g. a GA filter API or `HTTPRoute` filters). This is the biggest durability question. | i-ef; sm:R3 |

## 5. Ambient and mTLS to the backend

| # | Fact | | Consequence | Source |
|---|---|---|---|---|
| M1 | In ambient mode, traffic between meshed workloads is mTLS over HBONE (port 15008) via ztunnel; L7 handling needs a waypoint. | V | The gateway reaches the backend over mTLS through the backend namespace's waypoint; the backend never sees plaintext from the gateway. | sm:M1; i-wp |
| M2 | A `gw-only` `AuthorizationPolicy` in the backend namespace can admit only the gateway's identity (its ServiceAccount / namespace) and deny everything else. | V | Direct calls to the backend Service from other pods are refused; only the gateway gets through (ADR-0002, server-side; sm:S1). | i-ap; sm:S1 |
| M3 | A policy enforced by ztunnel with L7 attributes "fails safe by becoming a DENY". | V | The `gw-only` policy uses L4 identity (principals/namespaces), not L7, unless it is attached to the waypoint. | sm:M2; i-l4 |

## 6. The Multi-Tenant Operator today

| # | Fact | | Consequence | Source |
|---|---|---|---|---|
| T1 | Every tenant namespace carries `stakater.com/tenant: <tenant>`; a tenant can't change it. | V | The extension finds a tenant's namespaces (gateway and application) by this label. | sm:T1; to |
| T2 | `Tenant.spec.namespaces.metadata` labels are merged onto tenant namespaces; the Tenant can set `istio.io/dataplane-mode: ambient`, `istio-discovery: enabled` and `istio.io/use-waypoint` on named namespaces. | V | Mesh membership and the waypoint binding come from the reviewed `Tenant`, not from the gateway chart (ADR-0005). | sm:T2; to; ref |
| T3 | Template Operator v2 (`templates.v2.stakater.com`): a `Template` holds a Helm chart; a `TemplateInstance` renders it into its namespace with parameters; a `TemplateGroupInstance` renders across namespaces selected by label/tenant; `sync.mode: revert` reverts drift. | V | The gateway Template is a **library** a team instantiates (ADR-0001, 0004); the backend side is a platform `TemplateGroupInstance` (ADR-0005). | sm:T6; bao |
| T4 | Default tenant roles bind the `admin`/`edit` ClusterRoles in tenant namespaces; the Multi-Tenant Operator aggregation is cluster-wide. | V | A team could hold rights to create a raw `Gateway`; admission (not RBAC) must gate it (ADR-0006; sm:T5). | sm:T5 |
| T5 | No API-gateway, Istio-ingress or rate-limit integration exists in tenant-operator or any extension repo. | V | Greenfield; nothing legacy to migrate. | sm:T7; local search 2026-11-16 |

## 7. Identity provider

| # | Fact | | Consequence | Source |
|---|---|---|---|---|
| I1 | Red Hat build of Keycloak issues OIDC tokens; a confidential client with the client-credentials grant represents a machine consumer; claims (`azp`, and a custom claim such as `allowed_apis`) ride in the access token. | V | A consumer is a client; its entitlement is a claim; the gateway validates both (ADR-0002, 0003). | rhbk; ref |
| I2 | Creating the consumer client and its entitlement role is done today by a separate chart against the identity provider, by the platform. | V (ref) | v1 does **not** provision it; the client is a prerequisite and a later seam with `mto-extension-keycloak` (ADR-0009). | ref |
| I3 | The claim name, issuer URL, JWKS URI and audiences are identity-provider configuration, the same for every gateway on a cluster. | I | These are install-time (bootstrap) values of the extension, not per-gateway parameters. | i-ra; ref |

## 8. Relationship to the service-mesh extension

| # | Fact | | Consequence | Source |
|---|---|---|---|---|
| X1 | The service-mesh extension forbids tenants, at admission, from creating Gateway API `Gateway`s and waypoints and from setting `istio.io/use-waypoint`, but **exempts platform identities** (the Template Operator and GitOps service accounts). | V | A gateway rendered by the Template Operator identity is the sanctioned exception; a team's hand-written `Gateway` is refused. The two extensions compose (ADR-0006). | sm:§6 guardrails; sm:ADR-0005 |
| X2 | The service-mesh extension renders an east-west `tenant-boundary` DENY in every tenant namespace, and platform namespaces are on its allow list. | V | The gateway's own namespace and the backend call must be accounted for in the boundary (the gateway and backend are the same tenant, so same-tenant calls pass; sm:A1). No cross-tenant exception is needed for a gateway fronting its own tenant's backend. | sm:§4 |
| X3 | Neither extension requires the other at install time. | I | api-gateway works without the service-mesh extension (then the guardrail that stops a team routing around the gateway is this extension's own, optional admission policy); it works better with it. | ADR-0006 |

## 9. Prior art — tenant-scoped API gateways

| # | Fact | | Consequence | Source |
|---|---|---|---|---|
| E1 | 3scale, Kong and Gloo offer consumer management, API keys/JWT and rate limiting as products, with their own control planes. | V | The closest commercial equivalents; each is another product to buy and run. This extension turns the mesh ingress the customer already runs into the same capability, per team, without a new control plane. | general knowledge |
| E2 | No Red Hat product or community operator was found that renders a per-tenant, security-baked ingress gateway on OpenShift Service Mesh from the Multi-Tenant Operator Tenant. | U | Searched, not proven absent. Re-check each OpenShift Service Mesh release. | search 2026-11-16 |

## Open questions — VERIFY (all in M.0)

| # | Question | Rows |
|---|---|---|
| Q1 | **Rate limit and header strip without `EnvoyFilter`.** Does OpenShift Service Mesh 3.4 offer a supported, stable way to attach a shared rate-limit service and strip/set headers on a Gateway API gateway (a GA filter API, `HTTPRoute` filters, waypoint policy), or is an `EnvoyFilter` still required? This is the design's biggest durability risk. | D1, D3, D4 |
| Q2 | **Two-namespace rendering.** How are the gateway-side objects (gateway namespace) and the backend-side objects (application namespace) rendered and owned — a team `TemplateInstance` plus a platform `TemplateGroupInstance`, or a split Template? Can a `TemplateInstance` write cross-namespace at all? | T3, J3 |
| Q3 | **Waypoint ownership.** One waypoint per application namespace shared by several gateways: created idempotently by the backend-side render, bound by the `Tenant`'s `istio.io/use-waypoint` label; does enrolment work with the gateway's traffic? | J2, M1 |
| Q4 | **Policy binding to the gateway.** Do `RequestAuthentication` and `AuthorizationPolicy` attach to an `istio` Gateway API `Gateway` via `targetRefs` on 3.4, and is the token actually required (no-token → 403)? | A1, A3 |
| Q5 | **Derived claim match.** Does `request.auth.claims[allowed_apis]` prefix-matching `api-<apiName>-consumer-*` behave as intended, and does a wrong-API token get 403 with a valid token? | A2 |
| Q6 | **Header strip proven.** A caller-supplied `x-sub`/`x-roles` is removed before the gateway sets its own; the backend never sees the caller's value. | A4, A5 |
| Q7 | **Route → Gateway.** OpenShift `Route` (re-encrypt) in front of the `istio` Gateway: TLS/SNI handshake and path on the baseline. | J5 |
| Q8 | **Tier placement.** Is the rate-limit tier chosen per gateway (a parameter) or per consumer (from the token)? What does the reference run, and what generalises? | D2 |
| Q9 | **Guardrail interplay.** With the service-mesh extension installed, does the Template Operator identity render the gateway and waypoint without tripping its admission guardrails, and is a team's hand-written `Gateway` refused? | X1 |
| Q10 | **Scale and cost.** Dozens of gateways per cluster, each a Deployment+Service (N replicas) plus a waypoint per application namespace: istiod push time, resource cost, render time. | J1, J2 |
| Q11 | **Template Operator inputs.** Can the backend-side `TemplateGroupInstance` target the application namespaces of a tenant, and read the `Tenant`/`Namespace` it needs (shared with the service-mesh and Keycloak extensions' `objectFieldRef` question)? | T3 |
