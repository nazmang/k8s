# Monitoring audit, 2026-09-10

## Summary

There are **four** monitoring systems running. The one watching the Kubernetes
cluster collects metrics diligently and then throws every alert away, keeps its
data where a restart destroys it, and is not plugged into any dashboard. The one
that actually alerts watches only Docker Swarm.

| system | where | what it watches | alerts reach | state |
|---|---|---|---|---|
| kube-prometheus-stack 82.0.0 | k8s `monitoring` | the cluster, 42 targets | **nowhere** | restarts constantly |
| Prometheus 2.53 + Alertmanager 0.26 | Swarm | Swarm only, 9 targets | telegram, webhook | 7 months uptime |
| Zabbix 6.4 | Swarm | agents on 3 Swarm hosts | — | web UI down 2 months |
| Uptime Kuma | k8s | 7 external endpoints | ntfy, via apprise | working |

## Findings, worst first

### 1. Alerts from the cluster reach nobody

`GET /api/v2/receivers` on the cluster's Alertmanager returns exactly
`['null']` — the stack's default placeholder. There are **15 active alerts**
sitting there, none silenced or inhibited, including three `CertificateExpired`
at `critical`.

Everything that arrives in ntfy today comes from Uptime Kuma, which is a
separate system doing black-box checks from outside. Prometheus is not part of
that path. So: a node filling up, a pod crash-looping, etcd unhealthy — none of
it is delivered anywhere.

Note also that `Watchdog` is firing, as it is designed to. It exists to be
routed somewhere that complains when it *stops* arriving. Pointed at `null`, the
dead-man's switch has no one holding the other end.

### 2. Prometheus and Alertmanager store their data in `emptyDir`

```
prometheus-...-db:   emptyDir={}   4.7 GB of TSDB
alertmanager-...-db: emptyDir={}
retention: 10d, storage: (unset), no PVCs in the namespace
```

The Prometheus pod has restarted **54 times**, so the metric history has been
destroyed 54 times. `retention: 10d` describes nothing. Alertmanager loses its
silences and notification state the same way.

Secondary effect: those 4.7 GB are ephemeral storage on k8s01, a node that had
6.8 GB free — monitoring was quietly eating the disk it monitors.

### 3. Grafana cannot reach the cluster's Prometheus

Grafana's datasources:

```
prometheus     Prometheus       http://prometheus:9090        Swarm, works
alertmanager   alertmanager     alertmanager:9093             Swarm, works
prometheus-k8s prometheus-k8s   http://10.0.55.2:9090/        DEAD
opensearch     ...              https://opensearch...:9200
```

`10.0.55.2` answers nothing, and it belongs to no network here: VMs are
`10.163.11.0/24`, pods `10.233.0.0/16`, and the MetalLB pool is
`10.164.12.1-100` with only two LoadBalancers allocated (ingress-nginx at
`.1`, portainer-agent at `.50`). It is a leftover from an earlier arrangement.

So cluster metrics are collected, alerted on by nobody, and displayed nowhere.

### 4. kube-proxy has never been scraped

All four `kube-proxy` targets are down with `connection refused` on `:10249`.
kube-proxy binds its metrics to `127.0.0.1` by default; kubespray exposes
`kube_proxy_metrics_bind_address` for this. `TargetDown` fires for it — into
`null`.

### 5. Certificates: one missing issuer, one collision

Four `Certificate` objects are not Ready, and have not been for 167-171 days:

- `minio-operator/minio-api-tls`, `minio-operator/minio-console-tls`,
  `redis/redis-tls` — all reference `ClusterIssuer/selfsigned-issuer`, **which
  does not exist**. The only ClusterIssuer in the cluster is `letsencrypt-dns`.
  There are no pending CertificateRequests, because nothing can be requested.
- `monitoring/srv-cc-wildcard` — `IncorrectCertificate: Secret was issued for
  "srvxapp-com-wildcard"`. Two Certificates target the same Secret
  (`srvxapp-com-tls`) and fight over it; `monitoring/srvxapp-com-wildcard` is
  the one currently holding it.

These are what raise the three `critical` alerts nobody receives.

### 6. The cluster stack is unstable; the Swarm one is not

| | restarts |
|---|---|
| prometheus-operator | 145 |
| node-exporter (k8s02) | 117 |
| prometheus | 54 |
| kube-state-metrics | 21 |
| alertmanager | 4 |

Against Swarm's monitoring services, all showing **7 months** of uptime (Zabbix
server, 5 months). Some of the cluster restarts came from yesterday's memory
pressure, now fixed, but 145 is not explained by that alone.

### 7. Smaller, still real

- **`zabbix_zabbix-web` has been down two months** and nobody noticed. The task
  exited cleanly (`exit status 0`, "exiting, bye-bye!"), desired replicas 1,
  running 0. Its being unmissed for two months is the more useful signal.
- **fluentd cannot ship logs.** `[401] Unauthorized` against OpenSearch since at
  least 2026-08-23. The k8s03 replica crash-loops; the k8s04 one still reads
  `Running` with zero restarts but is not delivering either — it merely started
  back when the credentials worked. Needs the OpenSearch credentials.
- **`vault-internal` target is down (503)** because Vault is sealed. Expected,
  but it means `TargetDown` and `KubeStatefulSetReplicasMismatch` are permanent
  background noise — which is how alert fatigue starts, if anyone were receiving
  them.

## Direction

Decided 2026-09-10: **alerting consolidates on ntfy; Telegram goes away.** That
touches both Alertmanagers — the cluster's (currently `null`) and Swarm's
(currently `telegram` + `webhook`).

Ordering suggestion, cheapest and highest-value first:

1. Point the cluster's Alertmanager at ntfy. Nothing else on this list matters
   while alerts are discarded.
2. Give Prometheus and Alertmanager real volumes. `local-path` exists now.
3. Silence or fix the permanent firers (certificates, vault, kube-proxy) before
   turning delivery on, or the first thing ntfy receives is a wall of noise.
4. Repoint Grafana's `prometheus-k8s` datasource at something that exists.
5. Decide what Zabbix is for. Four systems is at least one too many, and the
   one whose UI can be down for two months unnoticed is the obvious candidate.
