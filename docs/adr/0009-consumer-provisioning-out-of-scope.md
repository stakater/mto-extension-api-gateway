# ADR-0009: Identity-provider consumer provisioning is a prerequisite in v1; a Keycloak-extension seam later

- **Status:** Proposed
- **Date:** 2026-11-16

## Context

A consumer is a machine client in the identity provider whose token carries a
claim entitling it to an API (**I1**). In the reference architecture the client
and its role are created by a separate chart against the identity provider, by
the platform (**I2**). Provisioning them is a REST-API act against the identity
provider, not a rendered Kubernetes object — the domain of a config operator,
which `mto-extension-keycloak` already is for Red Hat build of Keycloak.

## Decision

v1 does **not** provision consumer clients or roles. The identity provider,
with the realm and the consumer clients/roles, is an install prerequisite
(design §13). The derived consumer role name (`api-<apiName>-consumer-*`,
ADR-0003) is chosen so a later seam can generate it.

Later (M.12): derive the consumer client and its `allowed_apis` role from the
gateway request through `mto-extension-keycloak`, so a new API is one object
end to end.

## Consequences

- v1 is purely rendered objects; no REST calls, no identity-provider
  credentials in this extension.
- A new API still needs a platform step to create its consumer client until
  M.12 — honestly a seam, not a gap hidden.
- The derived naming (ADR-0003) is the contract between the two extensions.

## Alternatives

- **Provision the client here in v1.** Rejected: it drags an identity-provider
  REST client and its credentials into an otherwise component-free extension
  (ADR-0001), and duplicates `keycloak-config-operator`.
- **Never provision; always a prerequisite.** Rejected as the end state: "one
  object for a new API" is the point of the platform; M.12 keeps it on the
  roadmap.
