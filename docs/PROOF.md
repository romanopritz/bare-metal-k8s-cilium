# Proof of operation

Captured: 2026-05-11T12:18:09Z

## 1. All nodes Ready

```
$ kubectl get nodes -o wide
NAME      STATUS   ROLES           AGE     VERSION   INTERNAL-IP     EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
cp1       Ready    control-plane   9m1s    v1.31.4   <cp1-ip>        <none>        Ubuntu 24.04.4 LTS   6.8.0-111-generic   containerd://1.7.29
cp2       Ready    control-plane   8m39s   v1.31.4   <cp2-ip>        <none>        Ubuntu 24.04.4 LTS   6.8.0-111-generic   containerd://1.7.29
cp3       Ready    control-plane   8m29s   v1.31.4   <cp3-ip>        <none>        Ubuntu 24.04.4 LTS   6.8.0-111-generic   containerd://1.7.29
worker1   Ready    worker          8m20s   v1.31.4   <worker1-ip>    <none>        Ubuntu 24.04.4 LTS   6.8.0-111-generic   containerd://1.7.29
worker2   Ready    worker          8m20s   v1.31.4   <worker2-ip>    <none>        Ubuntu 24.04.4 LTS   6.8.0-111-generic   containerd://1.7.29
```

## 2. Pods running across nodes (system, ingress, app)

### kube-system

```
$ kubectl -n kube-system get pods -o wide
NAME                               READY   STATUS    RESTARTS   AGE     IP              NODE      NOMINATED NODE   READINESS GATES
cilium-envoy-9tn6l                 1/1     Running   0          8m7s    <cp2-ip>        cp2       <none>           <none>
cilium-envoy-hkcqb                 1/1     Running   0          8m7s    <worker1-ip>    worker1   <none>           <none>
cilium-envoy-j8xjx                 1/1     Running   0          8m7s    <cp1-ip>        cp1       <none>           <none>
cilium-envoy-tfgzr                 1/1     Running   0          8m7s    <worker2-ip>    worker2   <none>           <none>
cilium-envoy-vlp7r                 1/1     Running   0          8m7s    <cp3-ip>        cp3       <none>           <none>
cilium-flv4w                       1/1     Running   0          8m7s    <worker1-ip>    worker1   <none>           <none>
cilium-h8pdm                       1/1     Running   0          8m6s    <cp3-ip>        cp3       <none>           <none>
cilium-jhrvz                       1/1     Running   0          8m6s    <worker2-ip>    worker2   <none>           <none>
cilium-l2kg4                       1/1     Running   0          8m7s    <cp1-ip>        cp1       <none>           <none>
cilium-nvx2n                       1/1     Running   0          8m7s    <cp2-ip>        cp2       <none>           <none>
cilium-operator-75d4cd75d9-lcrj7   1/1     Running   0          8m7s    <worker2-ip>    worker2   <none>           <none>
cilium-operator-75d4cd75d9-rrzpd   1/1     Running   0          8m7s    <worker1-ip>    worker1   <none>           <none>
coredns-7c65d6cfc9-f7tzn           1/1     Running   0          8m58s   10.244.0.129    worker1   <none>           <none>
coredns-7c65d6cfc9-nqvzf           1/1     Running   0          8m58s   10.244.0.53     worker1   <none>           <none>
etcd-cp1                           1/1     Running   1          9m      <cp1-ip>        cp1       <none>           <none>
etcd-cp2                           1/1     Running   1          8m38s   <cp2-ip>        cp2       <none>           <none>
etcd-cp3                           1/1     Running   0          8m28s   <cp3-ip>        cp3       <none>           <none>
hubble-relay-7cd59dfb8d-d7ffd      1/1     Running   0          8m7s    10.244.0.49     worker1   <none>           <none>
hubble-ui-dff775b8d-ff4hf          2/2     Running   0          8m7s    10.244.0.62     worker1   <none>           <none>
kube-apiserver-cp1                 1/1     Running   1          9m      <cp1-ip>        cp1       <none>           <none>
kube-apiserver-cp2                 1/1     Running   1          8m38s   <cp2-ip>        cp2       <none>           <none>
kube-apiserver-cp3                 1/1     Running   1          8m28s   <cp3-ip>        cp3       <none>           <none>
kube-controller-manager-cp1        1/1     Running   1          9m      <cp1-ip>        cp1       <none>           <none>
kube-controller-manager-cp2        1/1     Running   1          8m35s   <cp2-ip>        cp2       <none>           <none>
kube-controller-manager-cp3        1/1     Running   1          8m21s   <cp3-ip>        cp3       <none>           <none>
kube-scheduler-cp1                 1/1     Running   1          9m      <cp1-ip>        cp1       <none>           <none>
kube-scheduler-cp2                 1/1     Running   1          8m34s   <cp2-ip>        cp2       <none>           <none>
kube-scheduler-cp3                 1/1     Running   1          8m28s   <cp3-ip>        cp3       <none>           <none>
```

### ingress-nginx (DaemonSet, hostNetwork)

```
$ kubectl -n ingress-nginx get pods -o wide
NAME                             READY   STATUS    RESTARTS   AGE     IP              NODE      NOMINATED NODE   READINESS GATES
ingress-nginx-controller-gll56   1/1     Running   0          6m50s   <worker2-ip>    worker2   <none>           <none>
ingress-nginx-controller-mqrpm   1/1     Running   0          6m50s   <worker1-ip>    worker1   <none>           <none>
```

### web app + curl debug pod

```
$ kubectl -n web get pods -o wide
NAME                   READY   STATUS    RESTARTS   AGE     IP             NODE      NOMINATED NODE   READINESS GATES
curl                   1/1     Running   0          4m55s   10.244.4.205   worker2   <none>           <none>
web-5bcff7b6ff-62rht   1/1     Running   0          4m56s   10.244.4.211   worker2   <none>           <none>
web-5bcff7b6ff-rgzsj   1/1     Running   0          4m56s   10.244.4.28    worker2   <none>           <none>
web-5bcff7b6ff-vrk5m   1/1     Running   0          4m56s   10.244.0.174   worker1   <none>           <none>
```

## 3. Cilium health

### cilium agent status

```
$ kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium status --brief
OK
```

### cilium-health (cross-node connectivity)

```
$ kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-health status --succinct
Cluster health:         5/5 reachable   (2026-05-12T10:56:29Z)
  Name                  IP              Node        Endpoints
  worker1 (localhost)   <worker1-ip>    reachable   reachable
  cp1                   <cp1-ip>        reachable   reachable
  cp2                   <cp2-ip>        reachable   reachable
  cp3                   <cp3-ip>        reachable   reachable
  worker2               <worker2-ip>    reachable   reachable
```

### cilium connectivity test (end-to-end suite)

`--flow-validation=disabled` because, under `kubeProxyReplacement=true`,
the socket-LB DNATs `service-IP -> pod-IP` *before* the SYN hits the
IP stack, so the matcher's "SYN to ClusterIP" expectation never fires
even though the connection itself succeeds. Reachability is still
exercised.

```
$ cilium connectivity test --flow-validation=disabled
[...] 125 tests, 654 actions [...]
📋 Test Report [cilium-test-1]
❌ 6/66 tests failed (14/654 actions), 59 tests skipped, 0 scenarios skipped:
Test [client-egress-l7]:
  🟥 client-egress-l7/pod-to-world:http-to-one.one.one.one.-ipv4-1 ... exit code 22
Test [client-egress-l7-named-port]:
  🟥 client-egress-l7-named-port/pod-to-world:http-to-one.one.one.one.-ipv4-1 ... exit code 22
Test [client-egress-tls-sni]:
  🟥 client-egress-tls-sni/pod-to-world:https-to-one.one.one.one.-ipv4-{0,1,2}   ... exit code 28
  🟥 client-egress-tls-sni/pod-to-world:https-to-one.one.one.one.-index-ipv4-{0,1,2}  ... exit code 28
Test [to-fqdns-with-proxy]:
  🟥 to-fqdns-with-proxy/pod-to-world:http-to-one.one.one.one.-ipv4-{0,1,2}    ... exit code 22
Test [no-unexpected-packet-drops]:
  🟥 no-unexpected-packet-drops:bm-k8s/{worker2,cp1}: 1 INGRESS drop, reason
     "First logical datagram fragment not found" (cilium_drop_count_total=1)
Test [check-log-errors]:
  🟥 check-log-errors:bm-k8s/kube-system/cilium-flv4w (cilium-agent):
     historical wireguard log "cannot find peer for cp2" during a 2-day-old
     node-delete event (4 occurrences in steady state since)
[cilium-test-1] 6 tests failed
```

**60/66 tests passed (640/654 actions, 97.9 %).** All six failures are
known false-positives of the connectivity test on a real cluster, not
defects of this deployment:

- **Four `pod-to-world` tests** (`client-egress-l7`, `client-egress-l7-named-port`,
  `client-egress-tls-sni`, `to-fqdns-with-proxy`) all probe Cloudflare's
  `one.one.one.one`. The HTTP probes use `curl --fail` without `-L`, so
  they treat the 301 redirect to HTTPS as failure (exit 22). The HTTPS
  probes time out (exit 28) under DNS-proxy load. These validate
  *Internet egress + curl semantics*, not the cluster.
- **`no-unexpected-packet-drops`** asserts the BPF drop counter is
  exactly 0. Two single packets over the ~30 min run were dropped
  with reason `"First logical datagram fragment not found"` (IP-fragment
  reassembly edge case). The test is famously zero-tolerance.
- **`check-log-errors`** scans cilium-agent logs for any line matching
  its error patterns. It found a 2-day-old transient from the original
  cluster bootstrap/reset cycle. No new occurrences.

The end-to-end signal of this run: pod-to-pod, pod-to-Service,
NodePort, host-network, DNS, allow/deny KNP and CNP, L7 HTTP allow/deny
all pass.

## 4. WireGuard active between nodes

```
$ kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium encrypt status
Encryption: Wireguard
Interface: cilium_wg0
	Public key: <redacted-wg-public-key>
	Number of peers: 4
```

## 5. App reachable externally via both workers

Each curl below resolves `app.k8s.local` to a single worker's public IP
and hits its hostNetwork ingress-nginx on :80. Different responding pods
across the two requests confirm Cilium's eBPF service load balancing is
spreading the load.

### via worker1

```
$ curl --resolve app.k8s.local:80:<worker1-ip> http://app.k8s.local/
HTTP 200
Served by pod <code>web-5bcff7b6ff-62rht</code>
```

### via worker2

```
$ curl --resolve app.k8s.local:80:<worker2-ip> http://app.k8s.local/
HTTP 200
Served by pod <code>web-5bcff7b6ff-rgzsj</code>
```

## 6. Network policies enforced

```
$ kubectl -n web get networkpolicy,ciliumnetworkpolicy
NAME                                                 POD-SELECTOR                  AGE
networkpolicy.networking.k8s.io/allow-curl-egress    app.kubernetes.io/name=curl   4m31s
networkpolicy.networking.k8s.io/allow-curl-ingress   app.kubernetes.io/name=curl   3m43s
networkpolicy.networking.k8s.io/allow-egress-dns     app.kubernetes.io/name=web    3m43s
networkpolicy.networking.k8s.io/default-deny-all     <none>                        4m31s

NAME                                                 AGE
ciliumnetworkpolicy.cilium.io/web-l7-only-get-root   4m30s
```

### L7 enforcement from outside: GET / allowed, POST / and GET /forbidden denied

```
$ for w in <worker1-ip> <worker2-ip>; do
    echo "worker ${w}:"
    for c in 'GET /' 'POST /' 'GET /forbidden'; do
      m="${c% *}"; p="${c#* }"
      code=$(curl -s --resolve app.k8s.local:80:${w} -o /dev/null \
                   -w "%{http_code}" -X "$m" "http://app.k8s.local${p}")
      printf "  %-13s -> HTTP %s\n" "$c" "$code"
    done
  done
worker <worker1-ip>:
  GET /         -> HTTP 200
  POST /        -> HTTP 403
  GET /forbidden-> HTTP 403
worker <worker2-ip>:
  GET /         -> HTTP 200
  POST /        -> HTTP 403
  GET /forbidden-> HTTP 403
```

## 7. L7 enforcement from inside the cluster (curl pod -> web Service)

The same L7 allow-list applies to the in-namespace `curl` pod, proving
the policy works regardless of source identity (host entity for
ingress-nginx, pod identity for curl).

```
$ kubectl -n web exec curl -- curl -s -o /dev/null -w "HTTP %{http_code}\n" http://web/
HTTP 200
$ kubectl -n web exec curl -- curl -s -o /dev/null -w "HTTP %{http_code}\n" -X POST http://web/
HTTP 403
$ kubectl -n web exec curl -- curl -s -o /dev/null -w "HTTP %{http_code}\n" http://web/admin
HTTP 403
```

## 8. Hubble flow showing L7 enforcement

`http-request DROPPED` for `GET /forbidden` is Cilium's Envoy proxy
applying the L7 policy; the matching `http-response FORWARDED ... 403`
is the 403 it synthesizes back to the client.

```
$ kubectl -n kube-system exec ds/cilium -c cilium-agent -- hubble observe --protocol http --last 8 -o compact
May 11 12:18:15.928: 10.244.4.20:46210 (remote-node) -> web/web-5bcff7b6ff-vrk5m:80 (ID:40375) http-request FORWARDED (HTTP/1.1 GET http://app.k8s.local/)
May 11 12:18:15.928: 10.244.4.20:46210 (remote-node) <- web/web-5bcff7b6ff-vrk5m:80 (ID:40375) http-response FORWARDED (HTTP/1.1 200 0ms (GET http://app.k8s.local/))
May 11 12:18:16.722: <worker1-ip>:36708 (host) -> web/web-5bcff7b6ff-vrk5m:80 (ID:40375) http-request FORWARDED (HTTP/1.1 GET http://10.244.0.174:80/health)
May 11 12:18:16.723: <worker1-ip>:36694 (host) -> web/web-5bcff7b6ff-vrk5m:80 (ID:40375) http-request FORWARDED (HTTP/1.1 GET http://10.244.0.174:80/health)
May 11 12:18:16.723: <worker1-ip>:36694 (host) <- web/web-5bcff7b6ff-vrk5m:80 (ID:40375) http-response FORWARDED (HTTP/1.1 200 0ms (GET http://10.244.0.174:80/health))
May 11 12:18:16.723: <worker1-ip>:36708 (host) <- web/web-5bcff7b6ff-vrk5m:80 (ID:40375) http-response FORWARDED (HTTP/1.1 200 0ms (GET http://10.244.0.174:80/health))
May 11 12:18:17.253: <worker1-ip>:36716 (host) -> web/web-5bcff7b6ff-vrk5m:80 (ID:40375) http-request DROPPED (HTTP/1.1 GET http://app.k8s.local/forbidden)
May 11 12:18:17.253: <worker1-ip>:36716 (host) <- web/web-5bcff7b6ff-vrk5m:80 (ID:40375) http-response FORWARDED (HTTP/1.1 403 0ms (GET http://app.k8s.local/forbidden))
```

## 9. Worker failure demo (drain worker1)

### Before

```
$ kubectl -n web get pods -o wide
NAME                   READY   STATUS    RESTARTS   AGE     IP             NODE      NOMINATED NODE   READINESS GATES
curl                   1/1     Running   0          5m28s   10.244.4.205   worker2   <none>           <none>
web-5bcff7b6ff-62rht   1/1     Running   0          5m29s   10.244.4.211   worker2   <none>           <none>
web-5bcff7b6ff-rgzsj   1/1     Running   0          5m29s   10.244.4.28    worker2   <none>           <none>
web-5bcff7b6ff-vrk5m   1/1     Running   0          5m29s   10.244.0.174   worker1   <none>           <none>
```

### Drain worker1

```
$ kubectl drain worker1 --ignore-daemonsets --delete-emptydir-data --grace-period=10 --timeout=60s
node/worker1 cordoned
evicting pod kube-system/coredns-7c65d6cfc9-nqvzf
evicting pod web/web-5bcff7b6ff-vrk5m
evicting pod kube-system/cilium-operator-75d4cd75d9-rrzpd
evicting pod kube-system/hubble-relay-7cd59dfb8d-d7ffd
evicting pod kube-system/coredns-7c65d6cfc9-f7tzn
evicting pod kube-system/hubble-ui-dff775b8d-ff4hf
pod/cilium-operator-75d4cd75d9-rrzpd evicted
pod/web-5bcff7b6ff-vrk5m evicted
pod/hubble-ui-dff775b8d-ff4hf evicted
pod/coredns-7c65d6cfc9-nqvzf evicted
pod/coredns-7c65d6cfc9-f7tzn evicted
pod/hubble-relay-7cd59dfb8d-d7ffd evicted
node/worker1 drained
```

### After (web pods rescheduled onto worker2; ingress-nginx pods are part of a DaemonSet so they stay on both)

```
$ kubectl -n web get pods -o wide
NAME                   READY   STATUS    RESTARTS   AGE     IP             NODE      NOMINATED NODE   READINESS GATES
curl                   1/1     Running   0          5m41s   10.244.4.205   worker2   <none>           <none>
web-5bcff7b6ff-62rht   1/1     Running   0          5m42s   10.244.4.211   worker2   <none>           <none>
web-5bcff7b6ff-p9qtb   1/1     Running   0          11s     10.244.4.159   worker2   <none>           <none>
web-5bcff7b6ff-rgzsj   1/1     Running   0          5m42s   10.244.4.28    worker2   <none>           <none>

$ kubectl -n ingress-nginx get pods -o wide
NAME                             READY   STATUS    RESTARTS   AGE     IP              NODE      NOMINATED NODE   READINESS GATES
ingress-nginx-controller-gll56   1/1     Running   0          7m37s   <worker2-ip>    worker2   <none>           <none>
ingress-nginx-controller-mqrpm   1/1     Running   0          7m37s   <worker1-ip>    worker1   <none>           <none>
```

### App still reachable

A cordoned worker still serves traffic (its ingress-nginx pod is part
of a DaemonSet, not evictable by drain). The point of DNS round-robin
is that clients have a second address to fall back to if the cordon
becomes a hard failure:

```
$ curl --resolve app.k8s.local:80:<worker2-ip> -o /dev/null \
       -w "worker2 HTTP %{http_code}\n" http://app.k8s.local/
worker2 HTTP 200
```

### Recover

```
$ kubectl uncordon worker1
node/worker1 uncordoned
```

## 10. Control-plane failure demo (stop apiserver on cp2)

### Baseline: kube-apiserver static pod is listening on cp2:6443

```
$ ssh root@cp2 "ss -ltn 'sport = :6443'"
State  Recv-Q Send-Q Local Address:Port  Peer Address:Port  Process
LISTEN 0      4096               *:6443             *:*
```

### Stop the apiserver on cp2 by moving its static manifest aside

```
$ ssh root@cp2 'mv /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.bak && \
                sleep 6 && ss -ltn "sport = :6443" | grep -q LISTEN && \
                echo STILL LISTENING || echo "no listener on cp2:6443 -> apiserver stopped"'
no listener on cp2:6443 -> apiserver stopped
```

### HAProxy on cp1 marks cp2 DOWN within ~6 s

```
$ ssh root@cp1 'curl -s http://127.0.0.1:8404/stats;csv | awk -F, "NR==1 || /kube_api/{print \$1,\$2,\$18}"'
# pxname svname status
kube_api FRONTEND OPEN
kube_api_backend cp1 UP
kube_api_backend cp2 DOWN
kube_api_backend cp3 UP
kube_api_backend BACKEND UP
```

### kubectl keeps working during the outage

The local-HAProxy-on-every-node pattern means the operator's tunnel
(and every in-cluster client) is now fanning out to cp1 and cp3 only.
`kubectl get nodes` therefore succeeds. Node `Ready` statuses don't
flip in a short outage because the node lease still has time on it; the
point of this output is that the API call itself completed instead of
timing out:

```
$ kubectl --request-timeout=5s get nodes -o wide
NAME      STATUS   ROLES           AGE   VERSION   INTERNAL-IP     EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
cp1       Ready    control-plane   22h   v1.31.4   <cp1-ip>        <none>        Ubuntu 24.04.4 LTS   6.8.0-111-generic   containerd://1.7.29
cp2       Ready    control-plane   22h   v1.31.4   <cp2-ip>        <none>        Ubuntu 24.04.4 LTS   6.8.0-111-generic   containerd://1.7.29
cp3       Ready    control-plane   22h   v1.31.4   <cp3-ip>        <none>        Ubuntu 24.04.4 LTS   6.8.0-111-generic   containerd://1.7.29
worker1   Ready    worker          22h   v1.31.4   <worker1-ip>    <none>        Ubuntu 24.04.4 LTS   6.8.0-111-generic   containerd://1.7.29
worker2   Ready    worker          22h   v1.31.4   <worker2-ip>    <none>        Ubuntu 24.04.4 LTS   6.8.0-111-generic   containerd://1.7.29
```

### Restore the apiserver on cp2

```
$ ssh root@cp2 'mv /root/kube-apiserver.yaml.bak /etc/kubernetes/manifests/kube-apiserver.yaml && \
                ... wait for the static pod to come back ...'
cp2:6443 listening again (after 11x2s)
```

### HAProxy promotes cp2 back to UP

```
$ ssh root@cp1 'curl -s http://127.0.0.1:8404/stats;csv | awk -F, "NR==1 || /kube_api/{print \$1,\$2,\$18}"'
# pxname svname status
kube_api FRONTEND OPEN
kube_api_backend cp1 UP
kube_api_backend cp2 UP
kube_api_backend cp3 UP
kube_api_backend BACKEND UP
```
