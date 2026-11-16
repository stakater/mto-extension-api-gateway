# ADR-0008: Tenants never create gateways, gateway policies or filters

- **Status:** Proposed
- **Date:** 2026-11-16

## Context

A tenant that can create a `Gateway`, an `EnvoyFilter`, a `WasmPlugin`, or a
Connectivity Link policy can open a new entry point or change what a gateway
does. The Service Mesh extension (in design) refuses tenant-created
`Gateway`s, `EnvoyFilter`s and `WasmPlugin`s at admission, and allows tenants
`HTTPRoute`s. Connectivity Link policies must be in the same namespace as their
target (K8), so a route-level policy lives in a tenant namespace.

## Decision

- **Only the platform and Template Operator create** `Gateway`s, `AuthPolicy`,
  `RateLimitPolicy` and Istio `AuthorizationPolicy` objects for this
  extension. Tenants create `HTTPRoute`s only.
- **Defence in depth, in this order:**
    1. RBAC: the tenant roles grant no write on those kinds (Q9 checks what the
       Multi-Tenant Operator's roles and the products' aggregated roles give
       today).
    1. Admission: a `ValidatingAdmissionPolicy` refuses a tenant's
       `AuthPolicy`, `RateLimitPolicy`, `Gateway`, `EnvoyFilter`,
       `WasmPlugin` and `TrafficExtension`, and an `HTTPRoute` with a
       `parentRef` to another tenant's gateway. The policy applies to tenant
       namespaces only: Connectivity Link's own `EnvoyFilter`s in the gateway
       namespace (K7) are not touched. When the Service Mesh extension is installed, its policies
       cover the shared kinds and this extension adds only its own.
    1. Overrides: even a policy that got through can't weaken the baseline
       (ADR-0004).

## Consequences

- The platform owns every object that decides security; tenants own routing.
- The two extensions must agree on one list of refused kinds (G.8).
- A tenant that needs a custom filter asks the platform, which may add it for
  all tenants.

## Alternatives

- **Trust RBAC alone.** Rejected: aggregated roles change when a product is
  installed; one missed rule opens a write.
- **Let tenants write route-level policies.** Rejected for now: overrides make
  it safe for the baseline, but a tenant-written allowed-API rule is free text
  again (ADR-0006).
