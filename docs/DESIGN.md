# Design note

## Goal & environment

5 dedicated bare-metal servers (12 vCPU AMD Ryzen 5 3600, 64 GiB RAM,
2x NVMe), Ubuntu 24.04 LTS, **single public /32 NIC each, no private
network or vSwitch**, default route via the public gateway. Required: a
production-minded multi-node Kubernetes cluster on Cilium with at least
two enforced network policies, an externally reachable app, no cloud
load balancer, reproducible setup.

## Tooling choices

| Decision | Choice | Why |
| --- | --- | --- |
| Bootstrap | **kubeadm** (v1.31.4) | Standard, well-documented. Talos would mean re-imaging Ubuntu, Kubespray is overkill, k3s isn't quite production-minded. |
| Automation | **Ansible** | Idempotent, plain text. Roles + inventory keep host prep, kubeadm join, and Cilium install in one repo. |
| Topology | **3 control plane + 2 workers**, stacked etcd | Smallest etcd quorum that tolerates one CP outage. Demos for node failure are then meaningful. |
| API HA without cloud LB | **HAProxy on every node listening on `127.0.0.1:16443`**, fronting all 3 apiservers | No L2 / VIP / BGP feasible (single public NIC per node). Local HAProxy is the canonical kubeadm-HA workaround. Health checks eject failing apiservers in seconds. |
| CNI | **Cilium 1.16**, `kubeProxyReplacement=true`, VXLAN tunnel | Tunnel mode because nodes are not on a shared L2 (no native routing, no BGP). kube-proxy replacement is the recommended Cilium data path. |
| Transport encryption | **WireGuard** node encryption | Inter-node traffic crosses the public Internet between datacenters. Cilium's built-in WireGuard is the lowest-friction way to encrypt it. |
| External exposure | **ingress-nginx DaemonSet, `hostNetwork: true`**, ports 80/443 on workers; DNS round-robin | No cloud LB; no shared L2 means MetalLB/Cilium L2 announcements are not usable; no BGP peer means BGP advertisement is not usable. Multiple A records give client-side failover. |
| Observability | **Hubble + Hubble Relay + Hubble UI** | Cilium-native, eBPF-derived flow logs and L7 visibility. Used in the L7 policy demo (`hubble observe --protocol http` shows the DROPPED POST). |
| Firewall | **nftables** managed by Ansible | Each host is on the public Internet; default-deny input, SSH allowlist, only cluster-IP-sourced traffic allowed on apiserver/etcd/kubelet/VXLAN/WireGuard ports, plus 80/443 to the world. |

## How networking works end-to-end

```
client --DNS RR--> worker public IP:443
                        |
                        v
              ingress-nginx (hostNetwork)
                        |
                        v
              ClusterIP / Cilium eBPF DNAT to a backend pod
                        |
                  (if pod is on another node)
                        |
                        v
              VXLAN packet, wrapped in WireGuard, to remote node
                        |
                        v
              pod's veth -> response retraces the path
```

- **Pod CIDR**: 10.244.0.0/16 (Cilium IPAM `cluster-pool`, /24 per node).
- **Service CIDR**: 10.96.0.0/12. coredns at 10.96.0.10.
- **Tunnel**: VXLAN on UDP 8472 between node public IPs. Each VXLAN
  packet is encrypted with WireGuard on UDP 51871 by Cilium before it
  leaves the NIC.
- **kube-proxy is not installed**. Service load balancing,
  `hostPort`, `NodePort` semantics, and `externalIPs` are all served by
  Cilium's eBPF programs attached to the host's network devices.

## How API HA works

Every node has a local HAProxy:

```
                              +------------+
              +------------>  | apiserver  |
              |               |   on cp1   |
              |               +------------+
              |
+----------+  |             +------------+
| HAProxy  +--+-----------> | apiserver  |
| 127.0.0.1|                |   on cp2   |
|  :16443  +--+             +------------+
+----------+  |
              |             +------------+
              +-----------> | apiserver  |
                            |   on cp3   |
                            +------------+
```

kubeadm's `controlPlaneEndpoint` is `127.0.0.1:16443`. Every kubelet
(every controller-manager, every scheduler, every Cilium agent) talks
to its own HAProxy. The /livez health check ejects a dead apiserver in
~6 s; we verified this in `docs/PROOF.md` by stopping the apiserver on
cp2 and observing `cp2 DOWN` in the HAProxy stats while kubectl
continued working.

For the operator workstation we use an SSH local-forward to one of the
HAProxy instances. That way we don't need to punch port 6443 through
the firewall, and the operator still benefits from the same fan-out.

## Network policies

Two policies, both demonstrated end-to-end in `docs/PROOF.md`:

1. **Default-deny L3/L4** (`NetworkPolicy`): everything in namespace
   `web` is denied ingress and egress by default. Adds explicit egress
   to `kube-system/kube-dns` so apps can still resolve names. With this
   alone, the debug `curl` pod can't talk to the web pods.
2. **L7 HTTP allow-list** (`CiliumNetworkPolicy`): on top of the
   default-deny, allow `GET /` and `GET /health` only, from the host
   entity (= ingress-nginx, which runs on `hostNetwork`) and from the
   in-namespace `curl` pod. Anything else (`POST /`, `GET /admin`, ...)
   is returned `403` by Cilium's Envoy proxy. `hubble observe
   --protocol http` shows the `DROPPED` events with the actual method
   and path.

The "host entity" detail is important: hostNetwork pods don't carry a
pod identity in Cilium, so `namespaceSelector` doesn't match them. The
L7 policy uses `fromEntities: [host, remote-node]`, which is the
Cilium-idiomatic way to permit those flows precisely.

## Tradeoffs and limitations

- **Single public NIC, no shared L2.** Forces VXLAN-over-WireGuard
  rather than the cleaner native routing, and forces DNS round-robin
  rather than a real VIP. The simplest production fix is to ask the
  hoster for a private network / vSwitch and switch to Cilium native
  routing with kube-vip or Cilium L2 announcements for service IPs.
- **DNS round-robin is not a true LB.** Failover is client-side and
  depends on the client honoring the multi-record answer. Real
  production would put a hardware/software LB (or anycast) in front.
- **HAProxy on localhost** is a clever workaround, not a hardware LB.
  It survives single apiserver outages cleanly but not a host failure
  on the operator side; the operator must point at a different CP
  manually if cp1 is down. The README's `operator-tunnel.sh` documents
  this.
- **No persistent storage.** Out of scope. Drop in
  `local-path-provisioner` or Longhorn when needed.
- **No TLS for the demo ingress.** A real deployment would add
  cert-manager with Let's Encrypt HTTP-01.
- **Encryption between nodes.** WireGuard is on; it adds ~5-15% CPU at
  the data plane and slightly increases p50 latency. Acceptable given
  the cleartext alternative crosses the public Internet.
- **kubeadm v1beta3 config**. Still GA in 1.31. v1beta4 is the new
  preferred version but the config shape change wasn't worth the risk.

## How a fresh operator would reproduce this

```bash
git clone <repo>
cd <repo>
# fill ansible/inventory.ini with five Ubuntu 24.04 hosts, root SSH
make deps
make bootstrap   # ~5 min end-to-end
make ingress
make app
make policies
make verify
```

Out of the scope but worth noting: the same playbooks
include an `apt dist-upgrade` + reboot step in the `common` role, so
the cluster lands on the latest distro security patches at install
time.
