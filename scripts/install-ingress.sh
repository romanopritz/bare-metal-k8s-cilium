#!/usr/bin/env bash
# Install ingress-nginx using the values in manifests/ingress-nginx/values.yaml
# Run from the operator machine using the admin.conf fetched by the playbook.
set -euo pipefail

KUBECONFIG="${KUBECONFIG:-$(dirname "$0")/../ansible/admin.conf}"
export KUBECONFIG

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHART_VERSION="${INGRESS_NGINX_CHART_VERSION:-4.11.3}"

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo update ingress-nginx

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --version "${CHART_VERSION}" \
  -f "${REPO_ROOT}/manifests/ingress-nginx/values.yaml" \
  --wait --timeout 5m

kubectl -n ingress-nginx rollout status ds/ingress-nginx-controller --timeout=3m
kubectl -n ingress-nginx get pods -o wide
