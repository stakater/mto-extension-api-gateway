# Support matrix

Which version of each component a release of the extension is tested with
and supports. A gateway depends on several parts that each have their own
version; this page is the one place that pins them together (issues #7
and #9).

Nothing is released yet. The first row is the **target** for release 0.1.0;
each cell turns from "to test" into a version when the story named in it
passes.

## Release 0.1.0 (target, not released)

| Component | Floor | Tested on kind (G.19) | Tested on OpenShift (G.0, G.10) | Why it matters |
|---|---|---|---|---|
| OpenShift | 4.20 | — | to test | Template Operator v2 needs Kubernetes 1.33 (#9); Service Mesh 3.4 supports 4.20 and later (M1) |
| Kubernetes (kind lab) | 1.33 | to test | — | the same floor, for the lab |
| OpenShift Service Mesh, ambient mode | 3.3 | — | 3.3 and 3.4: to test | ambient mode and waypoints (M1); the backend lock uses a waypoint (ADR-0007) |
| Istio (upstream, lab only) | 1.27 | 1.27.9 and 1.30.8: to test | — | the Istio versions behind Service Mesh 3.3 and 3.4; the three platform `EnvoyFilter`s are tested on both (ADR-0003) |
| Envoy expression rate limit descriptor | present in the mesh's proxy | in Istio 1.27 and 1.30 builds (M20) | to test | the tier comes from the caller's role (ADR-0003); without it, the tier claim fallback |
| Gateway API CRDs | v1.5.1 | v1.5.1: to test | as shipped with Service Mesh: to test | `Gateway`, `HTTPRoute` and `spec.infrastructure` (A1–A6) |
| Template Operator v2 (`v2alpha1`) | v0.0.5 | to test | to test | child `namespaceSelector` needs v0.0.5 (T2); the API is alpha, so each release pins the exact version (#9) |
| Multi-Tenant Operator | to confirm | stub `Tenant` CRD | to test | the tenant label on namespaces (T1) |
| cert-manager (optional) | 1.19 | — | to test | listener certificates, when the platform uses an issuer and not its own Secret |
| Identity provider | any OIDC issuer with the token contract (ADR-0004) | the lab issuer | RHBK: to test | `azp`, and the allowed-APIs claim with one role per API and tier |
| Rate limit service (`envoyproxy/ratelimit`) | pinned in G.5 | to test | to test | deployed by the bootstrap chart (ADR-0003) |
| Redis | provided by the platform | to test | to test | the rate limit counters |

## Rules

1. **A release supports only what it was tested with.** A component version
   gets a row entry only after the live suite passed on it (G.19 on kind,
   G.0 and G.10 on OpenShift). The entry names the exact version.
1. **Floors are enforced.** The bootstrap chart's preflight refuses an install
   or an upgrade below a floor and names the component (design §9, G.6).
1. **Mesh upgrades come after the suite.** Before the platform moves to a new
   Service Mesh minor, the upgrade suite runs on it (G.10) and adds it here.
   The platform upgrades the mesh only to a version on this page.
1. **The mesh is pinned too.** Service Mesh upgrades need a `Manual` install
   plan approval or a pinned version, so the mesh never moves past a minor
   this extension was tested on; the preflight refuses a newer minor than the
   highest tested one.
1. **Template Operator is pinned.** Its API is alpha (`v2alpha1`), so each
   release names the exact Template Operator version it was tested with, and
   a new Template Operator version is supported only after the suite.
1. **One chart version, one row.** A rollback goes back to the previous row's
   chart version, which G.10 tests on a cluster that serves traffic.
