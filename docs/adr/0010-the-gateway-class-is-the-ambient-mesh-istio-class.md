# ADR-0010: The gateway class is `istio`, from the ambient mesh's control plane

- **Status:** Proposed
- **Date:** 2026-11-17

## Context

Two Gateway API classes can run a gateway on OpenShift with Service Mesh 3:

- `istio`, from the Service Mesh control plane that also runs the ambient
  mesh of the tenant workloads;
- `openshift-default`, which the Ingress Operator provides on OpenShift 4.19
  and later (controller `openshift.io/gateway-controller/v1`), with a separate
  control plane and certificate authority (K1).

The backend lock (ADR-0007) lets only the tenant gateway's mesh identity call
an API backend. ztunnel checks that identity on the mTLS connection, so the
gateway must have a workload certificate that the ambient mesh trusts (M4,
M9). Connectivity Link 1.4 is supported with Service Mesh 3.4 as the Gateway
API provider (K1).

## Decision

- **Every tenant gateway uses the class `istio`** of the ambient mesh's
  control plane.
- `gateway.className` is a bootstrap value with one allowed value; the values
  schema refuses any other (design §9).

## Consequences

- The gateway has an identity in the mesh's trust domain,
  `cluster.local/ns/<namespace>/sa/<request>-istio`, so the backend lock can
  name it.
- The platform runs the Service Mesh control plane in a way that provides the
  `istio` class. The cluster's own ingress gateway class stays separate.
- If a later product version lets `openshift-default` share the mesh's trust,
  a new ADR can widen the enum.

## Alternatives

- **`openshift-default`.** Rejected: its certificate authority is not the
  ambient mesh's, so ztunnel can't trust the gateway's identity, and the
  backend lock can't work.
- **A second Istio control plane only for gateways.** Rejected: one more
  control plane to run, and the same trust problem unless it shares the root
  of trust.
- **Another Gateway API implementation (for example Envoy Gateway).**
  Rejected: not part of the Red Hat stack this extension targets, and not in
  the mesh.
