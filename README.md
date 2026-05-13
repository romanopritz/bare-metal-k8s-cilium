# Bare-metal Kubernetes with Cilium

A reproducible 5-node Kubernetes cluster on dedicated Ubuntu 24.04 hosts.
Bootstrap with **kubeadm** orchestrated by **Ansible**, CNI is **Cilium**
in kube-proxy-replacement mode with VXLAN tunnels over WireGuard.
External traffic enters through **ingress-nginx** running as a DaemonSet
on the workers with `hostNetwork: true`; no cloud load balancer is used.

- [docs/DESIGN.md](docs/DESIGN.md) - 1-2 page design note (tooling choices, networking, tradeoffs)
- [docs/RUNBOOKS.md](docs/RUNBOOKS.md) - day-2 operations (add node, node failure, debugging)
- [docs/PROOF.md](docs/PROOF.md) - captured command output proving each requirement

## Topology

```
                                            Public Internet
                                                   |
              +-----------+-----------+-----------+-----------+-----------+
              |           |           |           |                       |
              v           v           v           v                       v
        +-----------+ +-----------+ +-----------+ +---------------+ +---------------+
        |   cp1     | |   cp2     | |   cp3     | |    worker1    | |    worker2    |
        | apiserver | | apiserver | | apiserver | | ingress-nginx | | ingress-nginx |
        |   etcd    | |   etcd    | |   etcd    | |   app pods    | |   app pods    |
        | HAProxy   | | HAProxy   | | HAProxy   | +---------------+ +---------------+
        | :16443    | | :16443    | | :16443    |        ^                  ^
        +-----------+ +-----------+ +-----------+        |                  |
                                                  DNS round-robin -> worker public IPs
                                  VXLAN over WireGuard (pod CIDR 10.244.0.0/16)
```

- **3 control-plane** nodes, stacked etcd HA (tolerates 1 CP outage).
- **2 worker** nodes for ingress + workloads.
- **HAProxy** on every node fronting the three apiservers on `127.0.0.1:16443`;
  kubelet and all in-cluster components hit their local HAProxy, so any
  single apiserver outage is masked.
- **Cilium 1.16** with `kubeProxyReplacement=true`, VXLAN tunneling, and
  WireGuard transparent node encryption (the overlay traverses the public
  Internet, so encryption is mandatory).
- **ingress-nginx** as a DaemonSet on workers, `hostNetwork: true`, on
  ports 80/443. External clients reach it via DNS round-robin to the
  worker public IPs; on a node outage they retry the next A record.

## One-shot setup

Prereqs on the operator workstation: `ansible-core >= 2.16`, `kubectl`,
`helm`, `make`, `ssh` key-based access as `root` to all five hosts.

```bash
# 1. Provide your inventory (file is gitignored)
cp ansible/inventory.example.ini ansible/inventory.ini
# edit ansible/inventory.ini and set ansible_host to your real SSH targets

# 2. Bring up the cluster
make deps        # install Ansible collections
make bootstrap   # full cluster install (host prep, kubeadm, Cilium); ~5 min
make ingress     # install ingress-nginx as DaemonSet (uses fetched admin.conf)
make app         # deploy the demo nginx app
make policies    # apply default-deny + L7 CiliumNetworkPolicy
make verify      # quick sanity checks
```

`node_ip` and `node_name` are not written into the inventory; the
`common` role discovers them at runtime from each host's
`ansible_default_ipv4.address` and inventory name. That keeps real IPs
out of the repo.

After `make bootstrap`, an admin kubeconfig is at `ansible/admin.conf`.
To use it from the operator workstation, open an SSH tunnel that routes
through the local HAProxy on cp1 (which itself load-balances across all
three apiservers):

```bash
eval "$(./scripts/operator-tunnel.sh)"   # reads CP host from inventory
kubectl get nodes
```

The tunnel pattern keeps the firewall strict (port 6443 is blocked from
the world) and still gives the operator workstation apiserver HA.

## Repository layout

```
ansible/
  inventory.example.ini   - template; cp to inventory.ini and edit (gitignored)
  group_vars/all.yml      - versions, CIDRs, ports, tunable knobs
  site.yml                - top-level playbook (prep -> init -> join -> Cilium)
  join-workers.yml        - add a new worker without re-running everything
  reset.yml               - DANGEROUS - tear down and start over
  roles/
    common/               - facts (node_ip, node_name), apt upgrade + reboot,
                            swap off, sysctl, kernel modules, nftables, chrony
    containerd/           - install containerd.io, SystemdCgroup, sandbox image
    kube/                 - pinned kubeadm/kubelet/kubectl, kubelet --node-ip
    haproxy/              - localhost:16443 LB for apiserver HA
    controlplane-init/    - first kubeadm init, harvest join material
    controlplane-join/    - join the other two CPs
    workers-join/         - worker kubeadm join
    cilium/               - Helm install of Cilium with values
manifests/
  cilium/values.yaml      - Cilium Helm values
  ingress-nginx/values.yaml
  app/                    - demo nginx Deployment + Service + Ingress + curl debug
  policies/               - default-deny NetworkPolicy + L7 CiliumNetworkPolicy
scripts/
  install-ingress.sh
  operator-tunnel.sh      - SSH local-forward to local HAProxy on cp1
  verify.sh
docs/
  DESIGN.md
  RUNBOOKS.md
  PROOF.md
```

## How external traffic reaches the app

1. Client resolves `app.k8s.local` (or whatever you wire up in DNS) to
   the two worker public IPs. DNS round-robin.
2. Client TCP-connects to `worker:80` or `worker:443`.
3. ingress-nginx (DaemonSet, `hostNetwork: true`) is listening on those
   ports on the host; it parses the HTTP `Host:` header and matches the
   `Ingress` resource for `app.k8s.local`.
4. ingress-nginx forwards to the `web` ClusterIP Service. Cilium's eBPF
   service load-balancer (kube-proxy replacement) DNATs to one of the
   three `web` pods.
5. If the chosen pod is on another node, the packet leaves the worker
   inside a VXLAN tunnel that is itself encapsulated in WireGuard
   between the two nodes' public IPs.
6. The pod replies; the reverse path is symmetric.

## How the apiserver stays HA without a cloud LB

Every node runs a tiny HAProxy listening on `127.0.0.1:16443`. The
backend is the three real apiservers on their public IPs, each behind a
`/livez` health check.

- `kubeadm`'s `controlPlaneEndpoint` is set to `127.0.0.1:16443`, so
  every kubelet, kube-proxy-less Cilium agent, controller-manager and
  scheduler talks to its local HAProxy.
- If a single apiserver crashes, HAProxy ejects it within ~6 s and
  traffic flows to the remaining two. No VIP, no DNS games, no L2
  required.
- For operator access we use an SSH local-forward to the same HAProxy
  on cp1, so the operator workstation also benefits from the same
  fan-out and health checks.

## How to validate (quick)

```bash
eval "$(./scripts/operator-tunnel.sh)"
kubectl get nodes -o wide                       # 5 Ready
kubectl -n kube-system exec ds/cilium -- cilium status --brief

# Exercise the external-reach path (set to your real worker IPs):
WORKER1_IP=<worker1-ip>
WORKER2_IP=<worker2-ip>
curl --resolve app.k8s.local:80:$WORKER1_IP http://app.k8s.local/             # 200
curl --resolve app.k8s.local:80:$WORKER2_IP http://app.k8s.local/             # 200
curl --resolve app.k8s.local:80:$WORKER1_IP -X POST http://app.k8s.local/     # 403 (L7 policy)
```

See [docs/PROOF.md](docs/PROOF.md) for full captured output (IPs redacted).
