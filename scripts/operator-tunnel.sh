#!/usr/bin/env bash
# Open an SSH local-forward from the operator workstation to the local
# HAProxy on the first control plane. With this, your laptop's
# 127.0.0.1:6443 is load-balanced across all 3 apiservers (HAProxy's
# health checks eject any apiserver that's down), and the cluster
# firewall stays strict (no public 6443 needed).
#
# Usage:
#   eval "$(CP_HOST=cp1.example.com ./scripts/operator-tunnel.sh)"
#   kubectl get nodes
#
# If CP_HOST is unset, the script tries to read the first ansible_host
# from the [controlplane] group of ansible/inventory.ini.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KUBECONFIG_FILE="${REPO_ROOT}/ansible/admin.conf"
INVENTORY_FILE="${INVENTORY_FILE:-${REPO_ROOT}/ansible/inventory.ini}"
LOCAL_LB_PORT="${LOCAL_LB_PORT:-16443}"
LOCAL_PORT="${LOCAL_PORT:-6443}"

if [[ -z "${CP_HOST:-}" ]]; then
  if [[ -r "${INVENTORY_FILE}" ]]; then
    CP_HOST="$(awk '
      /^\[controlplane\]/ {in_cp=1; next}
      /^\[/              {in_cp=0}
      in_cp && /ansible_host=/ {
        match($0, /ansible_host=[^ ]+/);
        v = substr($0, RSTART+13, RLENGTH-13);
        print v; exit
      }
      in_cp && NF > 0 && $1 !~ /^[#;]/ {print $1; exit}
    ' "${INVENTORY_FILE}")"
  fi
fi

if [[ -z "${CP_HOST:-}" ]]; then
  echo "operator-tunnel.sh: set CP_HOST=<ssh-target-for-cp1> or create ansible/inventory.ini from inventory.example.ini" >&2
  exit 2
fi

if ! pgrep -f "ssh.*-L ${LOCAL_PORT}:127.0.0.1:${LOCAL_LB_PORT}" >/dev/null 2>&1; then
  ssh -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -fN \
      -L "${LOCAL_PORT}:127.0.0.1:${LOCAL_LB_PORT}" "root@${CP_HOST}"
fi

# Rewrite kubeconfig server URL to point at the tunnel.
if [[ -r "${KUBECONFIG_FILE}" ]]; then
  sed -i.bak "s|server: https://.*|server: https://127.0.0.1:${LOCAL_PORT}|" "${KUBECONFIG_FILE}"
  rm -f "${KUBECONFIG_FILE}.bak"
fi

echo "export KUBECONFIG=${KUBECONFIG_FILE}"
