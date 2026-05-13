#!/usr/bin/env bash
set -euo pipefail
KUBECONFIG="${KUBECONFIG:-$(dirname "$0")/../ansible/admin.conf}"
export KUBECONFIG

# Set WORKER_IPS to a space-separated list of your worker public IPs to
# exercise the "DNS round-robin -> ingress on hostNetwork" path. If
# left empty the external-reach checks are skipped.
WORKER_IPS=(${WORKER_IPS:-})
APP_HOST="${APP_HOST:-app.k8s.local}"

bold(){ printf "\n\033[1m== %s ==\033[0m\n" "$*"; }

bold "nodes"
kubectl get nodes -o wide

bold "system pods"
kubectl -n kube-system get pods -o wide

bold "cilium status (one of the agents)"
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium status --brief

bold "wireguard encryption"
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium encrypt status | head -5

bold "ingress-nginx"
kubectl -n ingress-nginx get pods,ds,svc

bold "web app"
kubectl -n web get pods,svc,ingress

bold "policies"
kubectl -n web get networkpolicy,ciliumnetworkpolicy

if [[ ${#WORKER_IPS[@]} -gt 0 ]]; then
  bold "demo: app reachable via worker public IPs (DNS round-robin path)"
  for ip in "${WORKER_IPS[@]}"; do
    code=$(curl -s --resolve "${APP_HOST}:80:${ip}" -o /dev/null -w "%{http_code}" --max-time 5 "http://${APP_HOST}/" || echo "ERR")
    echo "  GET  http://${APP_HOST}/ via ${ip}  -> HTTP ${code}"
  done

  bold "demo: L7 policy enforcement (POST denied, GET /forbidden denied)"
  for ip in "${WORKER_IPS[@]}"; do
    code=$(curl -s --resolve "${APP_HOST}:80:${ip}" -o /dev/null -w "%{http_code}" --max-time 5 -X POST "http://${APP_HOST}/" || echo "ERR")
    echo "  POST http://${APP_HOST}/ via ${ip}  -> HTTP ${code}"
    code=$(curl -s --resolve "${APP_HOST}:80:${ip}" -o /dev/null -w "%{http_code}" --max-time 5 "http://${APP_HOST}/forbidden" || echo "ERR")
    echo "  GET  http://${APP_HOST}/forbidden via ${ip}  -> HTTP ${code}"
  done
else
  bold "external-reach checks skipped (set WORKER_IPS=\"<w1> <w2> ...\" to enable)"
fi

bold "demo: in-cluster curl pod hits the web Service directly (L7 policy applies)"
echo "  GET  http://web/         ->"
kubectl -n web exec curl -- curl -s -o /dev/null -w "HTTP %{http_code}\n" --max-time 5 http://web/
echo "  POST http://web/         ->"
kubectl -n web exec curl -- curl -s -o /dev/null -w "HTTP %{http_code}\n" --max-time 5 -X POST http://web/
echo "  GET  http://web/admin    ->"
kubectl -n web exec curl -- curl -s -o /dev/null -w "HTTP %{http_code}\n" --max-time 5 http://web/admin
