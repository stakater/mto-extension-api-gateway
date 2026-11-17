# Vendored CRDs

The CRDs the render tests validate against (`hack/crd-validate`). Each file is
one `CustomResourceDefinition`, copied unchanged from its upstream release.

| File | Source | Version |
|---|---|---|
| `gateway.networking.k8s.io_gateways.yaml` | [Gateway API standard-install.yaml](https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml) | v1.5.1, the version Service Mesh 3.4 supports (`../../docs/gateway-baseline.md`) |
| `cert-manager.io_certificates.yaml` | [cert-manager.crds.yaml](https://github.com/cert-manager/cert-manager/releases/download/v1.19.1/cert-manager.crds.yaml) | v1.19.1, as in the cert-manager Operator 1.19 for OpenShift |

To update one, download the release file and extract the CRD with
`yq 'select(.kind == "CustomResourceDefinition" and .metadata.name == "<name>")'`,
then update this table and the baseline.
