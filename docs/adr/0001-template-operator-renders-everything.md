# ADR-0001: Template Operator renders everything; no new operator

- **Status:** Proposed
- **Date:** 2026-11-16 (the guards against a takeover added on 2026-11-26)

## Context

Every object this extension needs already has a supported API: the Gateway API
`Gateway` and `HTTPRoute`, Service Mesh's gateway deployment (M3), Istio's
`RequestAuthentication` and `AuthorizationPolicy` (M6), and the few
platform-owned `EnvoyFilter`s of ADR-0003. None of them needs a controller of ours to
reconcile it. The other Multi-Tenant Operator extensions
(`mto-extension-vault-enterprise`, `mto-extension-openbao`) use one pattern
for this: a bootstrap chart, installed once, renders a parent
`TemplateInstance` that fans out one render of a per-tenant chart per `Tenant`
(T2).

The first proposal for this extension was a Template Operator `Template` that
an API team instantiates once per API.

## Decision

- **One Helm chart, rendering Template Operator v2 objects**, in the shape of
  the other extensions: `mto-extension-api-gateway-bootstrap`, installed once
  per cluster by Helm. It renders:
    - the parent `Template` and `TemplateInstance`; the parent publishes the
      team-facing `api-gateway` and `api` Templates and emits one child
      `TemplateInstance` per tenant that has a gateway (ADR-0013);
    - the child Template `api-gateway-policy`, which renders the tenant's
      gateway policy, one rule per API and the backend locks;
    - the cluster-wide parts: the token floor and default deny in the Istio
      root namespace (ADR-0004), the rate limit service, and the admission
      policy (ADR-0008).

  A team's `TemplateInstance` of `api-gateway`, with no security parameter, renders
  the tenant's `Gateway`, its scaling config and its certificates in the
  team's namespace (ADR-0002). A team's `TemplateInstance` of `api` renders
  one API's `HTTPRoute` in its namespace (ADR-0005).
- **No custom resource and no controller.** The developer contract is one
  `TemplateInstance` per tenant for the gateway (ADR-0002) and one
  `TemplateInstance` of `api` per API (ADR-0005).
- **Templates never use sync mode `off`**, so a version a team chooses,
  or a tenant change, reaches every object it should (T3, ADR-0015). The parent uses `revert`; `api-gateway`,
  `api` and `api-gateway-policy` use `strict`, so a team can't edit or delete what
  it got.
- **The extension never takes over an object that it didn't create** (issue
  #11). Template Operator applies with server-side apply and forced
  ownership: a rendered object whose name matches a live object takes that
  object over, changes it, and deletes it with the instance (T4). Three
  guards, none of which needs a change in Template Operator:
    1. **Reserved names.** Every object the extension renders outside its own
       namespace `mto-api-gateways` has a name that starts with `mto-api-` or
       `api.`; the gateway is always `mto-api-gateway` (ADR-0002). Today's
       charts use neither form.
    1. **No takeover at admission.** Every rendered object carries the label
       `api-gateway.stakater.com/managed: "true"`. A
       `ValidatingAdmissionPolicy` of the bootstrap chart,
       `mto-api-gateway-no-adoption`, refuses an update that adds this label
       to an object without it. Template Operator's dry run fails, so it
       applies nothing for that instance, and its status names the object.
       It never applied the object, so it never deletes it (T4, T10).
    1. **Preflight.** The preflight `Job` fails when an object with a
       reserved name exists without the label, and names it (design §9).

## Consequences

- Nothing new to run, upgrade or secure besides Template Operator, which the
  other extensions already need.
- An upgrade is one chart version bump; Template Operator renders every tenant
  again.
- What Template Operator can't do, this extension can't do: a decision that
  needs a loop over live traffic, or an external system (RHBK), needs another
  tool (story G.11).
- Template Operator's service account needs RBAC on Gateway API, Istio and
  `EnvoyFilter` kinds. The chart lists exactly those (Q6).
- A taken name stops one instance, visibly, and changes nothing that runs.
  The migration needs no takeover: the tenant gateway's objects are new,
  next to the old gateway's (docs/migration.md).
- Another extension's takeover is not affected: the policy matches only
  objects with this extension's label, so the Argo CD extension, whose
  migration takes over each live `AppProject` in place, works as before
  (observed on kind, T10).
- The extension doesn't rely on `deletion-policy: Orphan`, whose behaviour
  depends on the Template Operator version.
- The policy must exist before Template Operator renders anything of ours:
  the bootstrap chart applies it before the parent `TemplateInstance` (an
  Argo CD sync wave); under Helm, the preflight covers the first install.
- The label is also in the gateway's `infrastructure.labels`, so the
  Deployment, Service and ServiceAccount that Istio creates for the gateway
  carry it, and the preflight doesn't take them for another owner's objects
  (observed on kind, G.19). Every object carries the label from the first
  release: the policy refuses to add it to a live object later, also when
  Istio's controller does it.
- A cluster admin who puts the label on a live object by hand makes it
  open to a takeover; the label is a platform label, like the tenant label
  (T5).

## Alternatives

- **A `Template` that the API team instantiates per API, with parameters
  (the first proposal).** Rejected as the API contract: its parameters
  re-create a values file, and an instance renders with the operator's rights
  and can read through `valueFrom`. Kept in a safer form for the gateway
  itself: one `TemplateInstance` per tenant, with no security parameter (ADR-0002).
  Its goals (one chart, no switch for the token check, the API rule or the
  headers, a derived allowed-API rule, one upgrade) are kept — see
  ADR-0004..0006.
- **A new operator with an `ApiGateway` CRD.** Rejected: one more component to
  build and run, for objects that already have standard APIs.
- **A chart per team (today).** Rejected: copies drift, and every team owns the
  security switches.
- **A Template Operator setting that refuses a takeover, per Template.** Not
  needed now; a second check if Template Operator adds it. Refusing every
  takeover in Template Operator would break the Argo CD extension's
  migration.
- **A platform namespace for each tenant gateway**, where no old object
  exists. Rejected: it reverses ADR-0002.
- **`deletion-policy: Orphan` on every rendered object.** Rejected: it doesn't
  stop the takeover, and it leaves the extension's own objects behind when a
  tenant leaves.
- **A render that LISTs each kind to find a taken name.** Rejected: a LIST of
  every kind in every namespace, and a template can't see who created an
  object.
- **A second, per-tenant Helm chart pulled by Template Operator** (the Vault
  Enterprise shape, the first version of this ADR). Rejected for now: it
  needs a published chart and pull credentials (ADR-0013).
