#!/usr/bin/env bash
# The G.19 kind lab (docs/planning/G19-kind-spike.md, hack/lab/README.md).
#
#   lab.sh up      kind cluster, Gateway API, Istio (ambient), the fixture; with TO_SRC, Template Operator
#   lab.sh test    every check; results in hack/lab/.state/results-<ISTIO_VERSION>.md
#   lab.sh down    delete the cluster
#
# Settings (environment): ISTIO_VERSION (1.30.8), CLUSTER (api-gw-lab), TO_SRC (a Template Operator source
# tree; builds TO_IMAGE from it when the image is missing), TO_IMAGE (local/template-operator-v2:lab),
# LAB_OFFLINE (set: skip the check that needs internet).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
STATE=$HERE/.state
CLUSTER=${CLUSTER:-api-gw-lab}
ISTIO_VERSION=${ISTIO_VERSION:-1.30.8}
NODE_IMAGE=${NODE_IMAGE:-kindest/node:v1.33.12}
GATEWAY_API_VERSION=v1.5.1
CERT_MANAGER_VERSION=v1.20.0
ISTIO_CHARTS=https://istio-release.storage.googleapis.com/charts
TO_IMAGE=${TO_IMAGE:-local/template-operator-v2:lab}
export KUBECONFIG=$STATE/kubeconfig

say() { printf '\n== %s\n' "$*"; }

istio() {
  say "Istio $ISTIO_VERSION, ambient, key reload 3 minutes"
  helm upgrade --install istio-base base --repo "$ISTIO_CHARTS" --version "$ISTIO_VERSION" \
    -n istio-system --create-namespace --wait >/dev/null
  helm upgrade --install istiod istiod --repo "$ISTIO_CHARTS" --version "$ISTIO_VERSION" -n istio-system \
    --set profile=ambient --set pilot.env.PILOT_JWT_PUB_KEY_REFRESH_INTERVAL=3m --wait >/dev/null
  helm upgrade --install istio-cni cni --repo "$ISTIO_CHARTS" --version "$ISTIO_VERSION" -n istio-system \
    --set profile=ambient --wait >/dev/null
  helm upgrade --install ztunnel ztunnel --repo "$ISTIO_CHARTS" --version "$ISTIO_VERSION" -n istio-system --wait >/dev/null
}

fixture() {
  say "fixture (docs/acceptance.md)"
  python3 "$HERE/lib/tokens.py" keys
  local m=$HERE/manifests
  kubectl apply -f "$m/00-namespaces.yaml" -f "$m/10-root.yaml" >/dev/null
  sed "s|__JWKS_A__|$(python3 "$HERE/lib/tokens.py" jwks a)|" "$m/20-gateway.yaml" | kubectl apply -f - >/dev/null
  kubectl apply -f "$m/30-backends.yaml" -f "$m/40-rules.yaml" -f "$m/50-ratelimit.yaml" >/dev/null
  python3 "$HERE/lib/ratelimit_filter.py" | kubectl apply -f - >/dev/null
  kubectl apply -f "$m/60-lock.yaml" -f "$m/70-external.yaml" >/dev/null
  for ns in team-a-test team-a-outside; do
    kubectl create configmap lab-client -n "$ns" --from-file=client.py="$HERE/lib/client.py" \
      --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  done
  kubectl apply -f "$m/80-clients.yaml" >/dev/null
  say "waiting for the gateway, the waypoint and the pods"
  kubectl wait --for=condition=Programmed gateway/mto-api-gateway gateway/mto-api-gateway-waypoint -n team-a-dev --timeout=300s
  for ns in team-a-dev team-a-test mto-api-gateways; do
    kubectl rollout status deploy -n "$ns" --timeout=300s >/dev/null
  done
  kubectl wait --for=condition=Ready pod/intruder -n team-a-test --timeout=180s
  kubectl wait --for=condition=Ready pod/outsider -n team-a-outside --timeout=180s
}

load_image() {
  kind load docker-image "$1" --name "$CLUSTER" >/dev/null 2>&1 && return
  # Docker Desktop's containerd image store breaks `kind load` ("failed to detect containerd snapshotter").
  docker save "$1" | docker exec -i "$CLUSTER-control-plane" ctr -n k8s.io images import --snapshotter=overlayfs - >/dev/null
}

template_operator() {
  [ -n "${TO_SRC:-}" ] || { say "Template Operator skipped (set TO_SRC to a Template Operator source tree)"; return; }
  say "cert-manager $CERT_MANAGER_VERSION and Template Operator ($TO_IMAGE)"
  kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/$CERT_MANAGER_VERSION/cert-manager.yaml" >/dev/null
  kubectl -n cert-manager wait deploy --all --for=condition=Available --timeout=300s >/dev/null
  docker image inspect "$TO_IMAGE" >/dev/null 2>&1 || docker build -q -t "$TO_IMAGE" "$TO_SRC" >/dev/null
  load_image "$TO_IMAGE"
  kubectl kustomize "$TO_SRC/config/default" \
    | sed -E "s#image: [^ ]*template-operator-v2[^ ]*#image: $TO_IMAGE#" \
    | kubectl apply --server-side --force-conflicts -f - >/dev/null
  kubectl -n template-operator-v2-system rollout status deploy --timeout=300s >/dev/null
  kubectl apply -f "$HERE/to/rbac.yaml" >/dev/null
}

up() {
  mkdir -p "$STATE"
  if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
    say "kind cluster $CLUSTER ($NODE_IMAGE)"
    kind create cluster --name "$CLUSTER" --image "$NODE_IMAGE" --kubeconfig "$KUBECONFIG" --wait 120s
  fi
  kind get kubeconfig --name "$CLUSTER" >"$KUBECONFIG"
  say "Gateway API $GATEWAY_API_VERSION"
  kubectl apply --server-side -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/$GATEWAY_API_VERSION/standard-install.yaml" >/dev/null
  istio
  fixture
  template_operator
  say "ready: hack/lab/lab.sh test"
}

case "${1:-}" in
  up) up ;;
  test) python3 "$HERE/lib/checks.py" --istio "$ISTIO_VERSION" "${@:2}" ;;
  down) kind delete cluster --name "$CLUSTER" ;;
  *) sed -n '2,12p' "$0"; exit 2 ;;
esac
