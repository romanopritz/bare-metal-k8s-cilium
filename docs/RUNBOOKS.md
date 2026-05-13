# Runbooks

All commands assume the operator tunnel is open:

```bash
eval "$(./scripts/operator-tunnel.sh)"
```

## Add a new worker node

1. Provision the host (Ubuntu 24.04, root SSH from operator, public NIC).
2. Add to `ansible/inventory.ini` under `[workers]`, e.g.:
   ```
   worker3 ansible_host=A.B.C.D node_ip=A.B.C.D node_name=worker3
   ```
3. Run the worker-only play:
   ```bash
   cd ansible
   ansible-playbook join-workers.yml -l worker3
   ```
   This applies `common`, `containerd`, `kube`, `haproxy` to the new
   host, mints a fresh bootstrap token on cp1, and runs `kubeadm join`.
4. Verify:
   ```bash
   kubectl get nodes -o wide
   ```

## Add a new control-plane node

1. Provision the host (Ubuntu 24.04, root SSH from operator, public NIC).
2. Add it to `ansible/inventory.ini` under `[controlplane]`, e.g.:
   ```
   cp4 ansible_host=A.B.C.D
   ```
3. Run the control-plane join play **without** `-l`:
   ```bash
   cd ansible
   ansible-playbook join-controlplane.yml
   ```
   This:
   - preps the new host (`common`, `containerd`, `kube`) one CP at a
     time, so no etcd-quorum risk from a stray kernel reboot;
   - re-renders `/etc/haproxy/haproxy.cfg` on **every** cluster node so
     they all start health-checking the new apiserver as a backend;
   - mints a fresh bootstrap token and a 2-hour certificate-key on
     `cp1`;
   - runs `kubeadm join --control-plane` on the new host. Existing CPs
     are no-ops here -- the `controlplane-join` role guards on
     `creates: /etc/kubernetes/kubelet.conf`.
4. Verify:
   ```bash
   kubectl get nodes -o wide
   kubectl -n kube-system get pods -l component=kube-apiserver -o wide
   ```

## Handle a node failure

### Worker hard failure

1. `kubectl get nodes` shows the worker `NotReady`.
2. After the node-controller eviction grace period, pods on it are
   replaced on healthy workers automatically (we use
   `topologySpreadConstraints` so they spread out).
3. While that worker is down, **client traffic continues** through the
   remaining worker (DNS round-robin to the worker IPs; resolvers
   typically try the next A record on connection error).
4. To force re-scheduling immediately instead of waiting for the
   timeout:
   ```bash
   kubectl drain <worker> --ignore-daemonsets --delete-emptydir-data --force
   ```
5. When the host is back, `kubectl uncordon <worker>`. If it was
   reinstalled, run `make bootstrap` (or the targeted worker-join play)
   to re-join it.

### Worker graceful drain (for maintenance)

```bash
kubectl cordon <worker>
kubectl drain <worker> --ignore-daemonsets --delete-emptydir-data --grace-period=30
# maintenance work
kubectl uncordon <worker>
```

### Control-plane node failure

1. `kubectl` keeps working: HAProxy on every node ejects the failing
   apiserver within ~6 s (`/livez` check, `inter 2s fall 3 rise 2`).
2. With 3 CPs, etcd retains quorum on the surviving two. The cluster
   stays writable.
3. Recovery on a returning node: kubeadm static pods come back when
   the manifests are intact. If etcd state on the host is gone, treat
   the host as a fresh CP: `kubeadm reset -f`, then run the
   `controlplane-join` role again (after minting fresh join material on
   cp1; see "Add a new control-plane node").
4. If two CPs are lost, etcd loses quorum and the API is read-only.
   Restore from an etcd snapshot or rebuild from cp1.

## Verify cluster health

```bash
kubectl get nodes -o wide
kubectl -n kube-system get pods -o wide
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium status --brief
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-health status --succinct
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium encrypt status
```

For an end-to-end test of pod-to-pod, node-to-node, NodePort, and DNS:

```bash
# Disable flow validation -- with kubeProxyReplacement=true the socket-LB
# DNATs service-IP -> pod-IP before the SYN hits the IP stack, so the
# matcher's "SYN to ClusterIP" expectation never fires even though the
# connection itself succeeds. Reachability is still tested.
cilium connectivity test --flow-validation=disabled
```

The full set runs 125 cases and takes ~15-20 min. Limit with `--test`
when iterating, e.g.:

```bash
cilium connectivity test --flow-validation=disabled --test 'no-policies|allow-all'
```

## Observe live flows with Hubble (cilium-cli)

Hubble Relay's gRPC endpoint is `kube-system/hubble-relay:80` (ClusterIP
only). To reach it from the operator workstation, port-forward it to
`localhost:4245` (cilium-cli's default):

```bash
eval "$(./scripts/operator-tunnel.sh)"   # ensures KUBECONFIG + apiserver tunnel
cilium hubble port-forward &             # backgrounded; runs kubectl port-forward
cilium hubble observe --protocol http --last 20
cilium hubble ui                         # opens browser to Hubble UI
```

Stop the background forward when done with `kill %1` (or `pkill -f 'hubble-relay 4245'`).

## Debug networking

### "Why can't pod A reach pod B?"

```bash
# Quick L3/L4 view:
kubectl -n kube-system exec ds/cilium -c cilium-agent -- hubble observe \
  --from-pod web/curl --to-pod web/web --last 20 -o compact

# L7 view (HTTP method/path, status):
kubectl -n kube-system exec ds/cilium -c cilium-agent -- hubble observe \
  --protocol http --last 20 -o compact

# Identity / labels for an endpoint:
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium endpoint list | head

# Show enforced policies on an endpoint:
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium endpoint get <ep-id>
```

### "Is the overlay/encryption healthy?"

```bash
# WireGuard peers and rx/tx counters:
ssh root@cp1 'wg show'

# Cilium overlay liveness across all nodes:
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-health status --succinct
```

### "DNS broken?"

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
kubectl -n web exec curl -- nslookup kubernetes.default
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=50
```

### "Service VIP unreachable?"

```bash
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium service list
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium bpf lb list
```

### "Ingress returning 5xx?"

```bash
kubectl -n ingress-nginx logs ds/ingress-nginx-controller --tail=50
kubectl -n ingress-nginx get endpoints ingress-nginx-controller
kubectl -n web describe ingress web
```

### Packet capture inside the Cilium agent

```bash
NODE=worker1
POD=$(kubectl -n kube-system get pods -l k8s-app=cilium -o jsonpath='{range .items[?(@.spec.nodeName=="'$NODE'")]}{.metadata.name}{end}')
kubectl -n kube-system exec -it $POD -c cilium-agent -- tcpdump -i any -nn -c 50 'host 10.244.0.5'
```

## Cluster reset / rebuild

```bash
make reset       # runs ansible/reset.yml -- DANGEROUS
make bootstrap   # rebuild from scratch
make ingress app policies
```

## Upgrade Kubernetes

1. Bump `kubernetes_version` and `kubernetes_apt_series` in
   `ansible/group_vars/all.yml`.
2. Drain each CP in sequence, `apt-get install kubeadm=<v>`, run
   `kubeadm upgrade apply <v>` on cp1, `kubeadm upgrade node` on the
   others, then `apt-get install kubelet=<v> kubectl=<v>` and restart.
3. Repeat for workers (`kubeadm upgrade node`).
4. Bump `cilium_version` and run `make cilium` to upgrade Cilium via
   Helm. Roll one node at a time using `--wait`.

## Upgrade Cilium

```bash
# bump cilium_version in ansible/group_vars/all.yml
cd ansible
ansible-playbook site.yml --tags cilium -l cp1
```
