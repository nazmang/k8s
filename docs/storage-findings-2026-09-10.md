# Storage findings, 2026-09-10 — open items

Written down after the SQLite-off-NFS migration so the rest is not lost. Nothing
here is urgent; all of it is worth deciding on deliberately.

## Measured, not assumed

**NFS on this cluster is not slow.** Measured on k8s02, on the access pattern
that was hurting SQLite:

| | local disk | NFS |
|---|---|---|
| 200 × 4K synchronous writes | 0.68 ms each | 0.90 ms each |
| 500 `flock` cycles | 2.11 ms | 2.22 ms |

A third slower on writes, five percent on locking. These numbers carry
process-startup noise and do not isolate the locking path cleanly, so treat them
as an upper bound rather than a measurement.

The consequence matters more than the numbers: **uptime-kuma's problem was
availability, not throughput.** When nas01 hiccups, `hard` mounts block, the
Node event loop stops, and Knex times out inside `beat()`. In steady state NFS
was fine. So the value of moving a workload to `local-path` is that one storage
hiccup stops taking 27 volumes down at once — not that it gets faster.

**What actually occupies `/srv/data`** (40 GB, 8.2 GB used):

```
jenkins_home         4.3G   Docker Swarm
n8n PVC              3.9G
prometheus_data      553M   Docker Swarm
grafana / opensearch ~200M  Docker Swarm
MinIO volumes        ~13M each, ~200M for all 16
```

More than half is Docker Swarm, not the cluster.

## The real single point of failure is the host, not nas01

`pve01` carries all nine VMs. Its disks are already four Samsung PM983 NVMe in
**RAID10, healthy `[4/4] [UUUU]`**, and an external Hetzner Storage Box (1 TB,
680 GB used) is mounted as a backup target. So the likely hardware failure — one
disk — is already survivable.

Any NFS HA pair built from two VMs on that same host would only cover a software
failure of nas01. Board, PSU or CPU failure takes everything regardless. Until
there is a second machine, DRBD/pacemaker or ZFS replication is a lot of work
aimed at a narrow gap.

## MinIO's redundancy is fictitious

The tenant declares `servers: 4, volumesPerServer: 4`, so MinIO believes it has
sixteen independent disks. They are sixteen directories in one tree on one VM.
**Erasure coding protects against losing some disks; here they are all lost at
once.** It holds roughly 200 MB and accounts for 16 of the cluster's 27 PVs.

Two honest options:

- **Fix it** — one pool member per node on `local-path`. The redundancy becomes
  real and the network hop disappears.
- **Retire it** — 16 volumes for 200 MB is a poor trade. S3 makes sense for
  artefacts, backups and renderd, but not as the substrate for PVCs.

## Not verified — close this before trusting node-local storage

`sudo` on the hypervisor prompts for a password, so two things stayed unchecked:

- **`vmdata_thin` pool utilisation** — decides whether node disks can grow.
- **PVE backup schedule, retention and restore testing.** `/etc/pve/jobs.cfg`
  and `vzdump.cron` were empty or unreadable. 680 GB on the Storage Box says
  backups happen; it does not say how often, how far back, or whether a restore
  has ever been exercised.

That last point is load-bearing. Both `uptime-kuma` and `ntfy` now keep their
databases on node-local disks, and the argument that this is safe rests entirely
on PVE backing the VMs up and being restorable. **ntfy's `auth.db` holds the
access tokens.** Verify it, or the safety net is assumed rather than known.
