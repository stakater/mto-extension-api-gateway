# Charts

> **Not released.** The chart is render-tested only. Story G.0, the live spike,
> proves it on a cluster before the first release (`../docs/roadmap.md`).

| Chart | Installed | What it does |
|---|---|---|
| [mto-extension-api-gateway-bootstrap](mto-extension-api-gateway-bootstrap/) | once per cluster, by hand | Publishes the `api-gateway` Template. A team asks for its tenant's gateway with a `TemplateInstance` of it. |

The per-tenant chart (route-level policies and the backend lock) comes with
stories G.3 and G.4. The security baseline policies come with G.2.

## Requirements

- OpenShift with OpenShift Service Mesh 3 in ambient mode and its `istio`
  GatewayClass. The OpenShift-provided `openshift-default` class is not
  supported (`../docs/design.md` §9).
- Template Operator v2 ≥ 0.0.5, with its admission webhook (sync mode
  `strict` depends on it).
- The Multi-Tenant Operator. It labels each tenant namespace
  `stakater.com/tenant: <tenant>`; the charts key on that label.
- cert-manager, only if `gateway.tls.certManager.issuerRef.name` is set.

## How it fits together

```text
platform namespace mto-api-gateways
  parent TemplateInstance (mto-extension-api-gateway-parent)
    reads every Tenant, Namespace and TemplateInstance
    publishes Template api-gateway        sync strict; tenant namespaces only;
                                          every parameter disableOverride:
                                            tenantOf  namespace -> tenant
                                            owner     tenant -> the request that owns its gateway
                                            extraHostnames, gateway settings
    ConfigMap mto-extension-api-gateway-skipped-tenants   what was skipped or refused, and why

a tenant namespace, e.g. team-a-dev
  TemplateInstance api-gateway            the team's request: no parameters
    renders, here only:
      Gateway api-gateway                 listener "tenant": *.<tenant>.<baseDomain>
                                          listener "extra-<n>": each granted host name
                                          routes only from namespaces labelled with the tenant
      ConfigMap api-gateway-infra         autoscaler and disruption budget (parametersRef)
      Certificate api-gateway-tls…        one per listener, when cert-manager is on
      ConfigMap api-gateway-status        ok, or refused and why
```

Service Mesh deploys the gateway's pods, Service and ServiceAccount as
`<request>-istio`, in the request's namespace. The pods count against the
tenant's quota.

**One gateway per tenant.** The oldest valid request in a tenant's namespaces
owns it. Every other request renders only its status ConfigMap, which names
the owner. A request is refused when its namespace belongs to no tenant that
may request a gateway, or when its name is not a DNS label of at most 48
characters.

**The team can't change what it got.** The request has no parameters, its
tenant comes from the platform's `tenantOf`, and the Template syncs `strict`:
Template Operator's admission webhook refuses an edit or delete of anything it
rendered. Deleting the request removes the gateway.

A tenant is **skipped** and listed with the reason when its name is not a DNS
label or is longer than 63 characters. An extra host name is **refused** and
listed under `<tenant>.hostnames` when it is not a valid host name, overlaps
the base domain, or overlaps another tenant's extra host name.

## Install (platform)

```sh
helm install mto-extension-api-gateway \
  charts/mto-extension-api-gateway-bootstrap \
  -n mto-api-gateways --create-namespace \
  --set gateway.baseDomain=apis.example.com
```

## Request a gateway (team)

```yaml
apiVersion: templates.v2.stakater.com/v2alpha1
kind: TemplateInstance
metadata:
  name: api-gateway          # names the Gateway; a DNS label, at most 48 characters
  namespace: team-a-dev      # where the gateway runs: any of the tenant's namespaces
spec:
  templateRef:
    name: api-gateway
    namespace: mto-api-gateways
```

Then read `api-gateway-status` in the same namespace.

## Values

| Value | Default | Meaning |
|---|---|---|
| `gateway.baseDomain` | `""` | **Required.** Each tenant's gateway serves `*.<tenant>.<baseDomain>`. |
| `gateway.className` | `istio` | The only accepted value. |
| `gateway.port` | `443` | Listener port. |
| `gateway.extraHostnames` | `{}` | Extra host names per tenant, `{team-a: [api.team-a.example.org]}`; each gets its own listener. |
| `gateway.autoscaling` | 2 to 5 replicas at 80 % CPU | Applied by Service Mesh to the gateway Deployment. `minReplicas` is at least 2. |
| `gateway.podDisruptionBudget.minAvailable` | `1` | Must be below `minReplicas`, so a node drain can evict a gateway pod. |
| `gateway.tls.certManager.issuerRef` | `ClusterIssuer`, no name | With a name, cert-manager issues one Certificate per listener. Without one, provide the Secrets `<request>-tls` and `<request>-tls-extra-<n>` in the request's namespace. |
| `tenants.mode` / `tenants.list` | `all` / `[]` | `list` lets only the listed tenants request a gateway. |
| `tenantLabelKey` | `stakater.com/tenant` | The Multi-Tenant Operator's namespace label. |
| `templateOperator.serviceAccountName` / `.namespace` | `template-operator-template-operator-v2` / `stakater-template-operator` | The identity the chart grants RBAC to. |
| `templateSync.mode` | `revert` | The parent's sync mode: `revert` or `strict`; never `off`. The team-facing Template is always `strict`. |

## Trust boundary

- **The `stakater.com/tenant` label on a namespace decides its tenant**: which
  tenant's gateway a request in it gets, and which gateway its routes can
  attach to. Only the Multi-Tenant Operator and cluster admins may set it.
- **Template Operator writes Gateways, ConfigMaps and Certificates in tenant
  namespaces** (a cluster-wide grant, as tenant namespaces come and go). Its
  admission webhook must be running: without it, `strict` can't refuse a
  team's edit.

## Testing

`make charts` runs `hack/chart-render-tests.sh`: fifteen checks over the
parent render and every fixture request (structure, parameters, sync modes,
golden, emission, requests, trust, listeners, extra host names, forbidden
kinds, namespaces, certificates, schema, RBAC coverage) and a validation of
every rendered `Gateway` and `Certificate` against the vendored CRDs in
`hack/crds`. After an intended change, review the render, then run
`make golden`.
