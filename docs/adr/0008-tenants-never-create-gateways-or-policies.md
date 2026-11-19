# ADR-0008: Tenants never create gateways, gateway policies or filters directly

- **Status:** Proposed
- **Date:** 2026-11-16

## Context

A tenant that can create a `Gateway`, an `EnvoyFilter`, a `WasmPlugin`, or an
Istio policy on a gateway can open a new entry point or change what a gateway
does. The Service Mesh extension (in design) refuses tenant-created
`Gateway`s, `EnvoyFilter`s and `WasmPlugin`s at admission, and allows tenants
`HTTPRoute`s. The tenant gateway runs in a tenant namespace (ADR-0002), and an
Istio policy that targets it must be in that namespace (M6). Istio has no
overrides: an extra `ALLOW` policy adds access, and an extra
`RequestAuthentication` adds an issuer (ADR-0004).

## Decision

- **Only the platform and Template Operator create** `Gateway`s, the
  gateway's `RequestAuthentication` and `AuthorizationPolicy` objects, its
  `EnvoyFilter`s, the backend locks for this extension, and the `HTTPRoute`s
  of APIs. Tenants create only `TemplateInstance`s: one parameterless
  `api-gateway` for the gateway (ADR-0002) and one `api` per API
  (ADR-0005). Template Operator renders both in strict mode, so the tenant
  can't edit or delete what they render.
- **Defence in depth, in this order:**
    1. RBAC: the tenant roles grant no write on those kinds (Q9 checks what the
       Multi-Tenant Operator's roles and the products' aggregated roles give
       today).
    1. Admission: a `ValidatingAdmissionPolicy` refuses a tenant's
       `Gateway`, `EnvoyFilter`, `WasmPlugin` and `TrafficExtension`; a
       `RequestAuthentication`, `AuthorizationPolicy` or `Telemetry` that
       targets a `Gateway` or selects a gateway's pods; a pod that uses a
       gateway's service account; `exec`, `attach` and `port-forward` into a
       gateway's pods; an `HTTPRoute` in a tenant namespace (ADR-0005); a
       `valueFrom` parameter on an `api` or `api-gateway` instance (T9); the label
       `istio.io/dataplane-mode` on a tenant pod (M8); and a tenant's OpenShift
       `Route` for a host under the base domain or for a shared host (ADR-0009). The policy matches requests
       from tenant users only. It lets through Template Operator, which renders
       the gateway and its policies in the tenant's namespace (ADR-0002).
       When the Service Mesh extension is
       installed, its policies cover the shared kinds and this extension adds
       only its own.
    1. The token floor: even an `ALLOW` policy that got through can't let in
       a request without a valid platform token; `DENY` wins (ADR-0004).

## Consequences

- The platform owns every object that decides security; tenants say what to
  route through their `api` instances (ADR-0005).
- The two extensions must agree on one list of refused kinds (G.23).
- The gateway runs in a tenant namespace (ADR-0002), so this minimum is built
  before any API is served (G.8), not after.
- A tenant that needs a custom filter asks the platform, which may add it for
  all tenants.

## Alternatives

- **Trust RBAC alone.** Rejected: aggregated roles change when a product is
  installed; one missed rule opens a write.
- **Let tenants write route-level policies.** Rejected: Istio has no
  overrides, so a tenant's `ALLOW` would widen the allowed-API rule, and a
  tenant-written rule is free text again (ADR-0006).
