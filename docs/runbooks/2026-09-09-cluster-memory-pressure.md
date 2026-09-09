# Runbook — cluster memory pressure: resize VMs, fix scheduler accounting

**Status:** COMPLETE, 2026-09-09. All five steps applied and verified.
**Blast radius:** every stateful workload in the cluster. Read the whole file first.

> **The provider reports failure on success. Read "Provider behaviour" below
> before running any `apply`, and never re-run one that failed.**

## Symptom

`uptime-kuma` emitted false `Down` alerts for services that were never down, with a
Node.js stack trace as the failure reason:

```
[psvc.duckdns.org] [Down] Knex: Timeout acquiring a connection.
The pool is probably full. Are you missing a .transacting(trx) call?
```

Alongside them, occasional `[Down] ping: <host>: Name or service not known`, and
`kubectl` intermittently returning `connection refused` or — mid-restart — RBAC
errors from a not-yet-ready apiserver.

## Cause

Three layers, outermost first.

**1. The alerts are self-inflicted.** Kuma keeps its SQLite database on the
`nfs-client` storage class. An NFS stall blocks the Node event loop, `beat()`
throws `KnexTimeoutError` before it can record a heartbeat, and Kuma reports the
exception text as the monitor's failure reason. The monitored services were fine.
Restarts also stop the container's `nscd`, which is where the DNS-shaped alerts
come from.

**2. The restarts were caused by a probe that was too tight for NFS.** The
liveness probe (`timeout 5s`, `period 10s`, `threshold 3`) killed the container
after ~45s of unresponsiveness: 413 restarts in 129 days. Fixed separately —
see `helm-uptime-kuma/chart/values.yaml`, commit `fea9df1`. That change treats
the symptom only.

**3. The stalls come from node memory pressure, and the pressure is a scheduler
accounting bug.** Measured 2026-09-09:

| node | requests | actual | ratio |
|---|---|---|---|
| k8s01 | 871Mi | 4564Mi | 5.2× |
| k8s02 | 1319Mi | 6263Mi | 4.7× |
| k8s03 | 2787Mi | 4449Mi | 1.6× |
| k8s04 | 2036Mi | 2909Mi | 1.4× |

Two consumers are invisible to the scheduler on the control-plane nodes:

- **etcd** — `etcd_deployment_type: host`, so it is a systemd unit in
  `system.slice`, not a pod. Nothing accounts for it.
- **kube-apiserver** — a static pod declaring a CPU request and no memory
  request, while resident at ~2Gi.

Stock reservations were 256Mi (kube) + 512Mi (system). Confirmed against the
live nodes: capacity `8131780Ki` − allocatable `7242948Ki` = 868Mi, i.e. 768Mi
of reservations plus the 100Mi default eviction threshold.

So the scheduler saw the two fullest nodes in the cluster as its emptiest and
kept packing pods onto them. That is a feedback loop, not a one-off. On
2026-09-09 k8s02 took a kernel `SystemOOM` (victim:
`argocd-application-controller`) and the control plane flapped.

The kubelet default hard eviction of `memory.available<100Mi` is why the kernel
OOM killer acted before kubelet could evict anything in an orderly way.

## Facts established before writing this

Hypervisor `pve01` (`10.164.1.1`), verified on the host:

- **125Gi total, 74Gi used, 50Gi available.** ZFS is not in use, so there is no
  ARC quietly holding the free half.
- **Memory hotplug is not available.** Every VM has `hotplug: network,disk,usb`
  (no `memory`) and `numa: 0`; hotplug requires both. Enabling them is itself a
  reboot, so there is no shortcut — **the resizes require reboots.**
- **`balloon: 0` everywhere.** Ballooning is off, so `memory` is a fixed grant
  and the guest will receive exactly what is configured.
- **No VMs outside Terraform.** Nine running VMs match `terraform.tfstate`
  exactly. VM 9000 (`ubuntu-24.04-cloudinit`) is a stopped template, unmanaged,
  and consumes nothing.

### VMID ↔ name — they do not line up

```
100 = nas01      103 = k8s02
101 = k8s03      104 = k8s04
102 = k8s01      9000 = template (stopped)
```

`101` is **k8s03**, not k8s01. Check the name, never the number alone.

## Changes to apply

Both are already written and validated; neither has been applied.

**1. `terraform/infra/proxmox/dev_vms.tf`** — `terraform validate` passes,
`terraform fmt -check` clean.

| VM | from | to | why |
|---|---|---|---|
| `nas01` | 4 GB | 8 GB | NFS page cache; the direct cure for the stalls |
| `k8s01` | 8 GB | 16 GB | control-plane + etcd |
| `k8s02` | 8 GB | 16 GB | the node that hit SystemOOM |
| `k8s03` | 8 GB | 16 GB | etcd + vault + trivy + a minio pool; tightest node |

`k8s04` is left at 8 GB (2.9Gi of 8 in use). Total **+28 GB of the 50 available**,
leaving 22 GB of headroom on the host.

**2. `kubespray/inventory/hetzner1/group_vars/k8s_cluster/node-resources.yml`**
(new file)

```yaml
kube_memory_reserved:   "1Gi"    # was 256Mi
system_memory_reserved: "2Gi"    # was 512Mi — this is where host-deployed etcd lands
eviction_hard:
  memory.available: "500Mi"      # was the 100Mi kubelet default
  nodefs.available: "10%"
kubeadm_patches: [ kube-apiserver → requests.memory 2Gi ]
```

`kube_reserved` / `system_reserved` stay `false` **on purpose**: in
`kubelet-config.v1beta1.yaml.j2` the `kubeReserved` / `systemReserved` blocks are
emitted unconditionally, and the booleans only add the `*ReservedCgroup`
enforcement lines, which require those cgroups to exist and can stop kubelet from
starting. Raising the values is what moves allocatable.

Resulting allocatable: ~12.8 GB on the 16 GB nodes (against requests of
0.9–2.8 GB) and ~4.3 GB on k8s04 (against 2.0 GB). Nothing becomes unschedulable.

## Gates — read before running anything

**etcd quorum.** All three etcd members (k8s01, k8s02, k8s03) are being resized,
and `locals.tf` sets `automatic_reboot = true`, so Terraform reboots the VM
itself. Quorum is 2 of 3. **Resize one node at a time and confirm etcd health
between each.** Two simultaneous reboots take the API server down.

**nas01 is a single point of failure for all persistent state.** 27 PVCs live on
`nfs-client`, including all 16 MinIO volumes, Vault's data and audit volumes,
n8n, openclaw, semaphore, apprise, fluentd, uptime-kuma — and `ntfy`, which is
how alerts get delivered. Rebooting it stalls every one of them. With `hard`
NFS mounts (the default) clients block and resume once the server returns, but
MinIO may mark drives offline and enter recovery. Do it in a quiet window.

**Your kubeconfig dies with k8s01.** `~/.kube/hetzner` points straight at
`https://10.163.11.101:6443`, which is k8s01 itself — there is no VIP and no
external load balancer. (The `nginx-proxy` pods on k8s03/k8s04 are kubespray's
node-local balancers, bound to 127.0.0.1 on those hosts, and are no use from a
workstation.) So the moment step 2 reboots k8s01, every `kubectl` in this
runbook stops working, including the health gates.

Prepare a fallback pointing at the other control-plane node, and **test it while
both are still up**:

```bash
sed 's|10.163.11.101:6443|10.163.11.102:6443|' ~/.kube/hetzner > ~/.kube/hetzner-k8s02
chmod 600 ~/.kube/hetzner-k8s02
KUBECONFIG=~/.kube/hetzner-k8s02 kubectl get nodes     # verified working 2026-09-09
```

Use it for the gates around step 2, and switch back to the k8s01 one before
step 3 reboots k8s02.

**A node reboot used to wipe all NFS storage on that node. Fixed 2026-09-09 —
verify before rebooting anything.** All 27 PVs name the server by hostname
(`spec.nfs.server: nas01`, 27 of 27), and nothing in the cluster's DNS resolves
that name. Resolution depended entirely on a hand-added line in `/etc/hosts` —
which cloud-init rewrites on every boot, because `manage_etc_hosts` is `True`
and the entry was never added to `/etc/cloud/templates/hosts.debian.tmpl`.

The landmine sat unarmed for 222 days simply because no node had rebooted. Step
2 rebooted k8s01 and it went off: `nas01` stopped resolving there, and
`minio-comintern-pool-0-2` could not mount any of its four volumes —
`mount.nfs: Resource temporarily unavailable`, which reads like a server fault
and is not one. The other three MinIO pods stayed up only because their mounts
predated the reboot and `hard` mounts recover; nothing new could mount.

Fixed on all four nodes by adding the entry to the cloud-init template as well
as to the live file, so it now survives a reboot:

```bash
grep -q nas01 /etc/cloud/templates/hosts.debian.tmpl \
  || printf '\n10.163.11.100\tnas01\n' | sudo tee -a /etc/cloud/templates/hosts.debian.tmpl
grep -q nas01 /etc/hosts || printf '10.163.11.100\tnas01\n' | sudo tee -a /etc/hosts
getent hosts nas01        # must answer on every node before you reboot it
```

Had step 3 run without this, k8s02's MinIO pod would have broken the same way,
leaving the tenant on two of four. **Re-check `getent hosts nas01` on the target
node before each remaining reboot.** The durable fix is to stop naming the
server by hostname in the PVs, or to serve `nas01` from CoreDNS — neither is in
scope here.

**The Terraform state is four months old** (serial 101, last written
2026-05-18). Run a full `plan` first and confirm it contains exactly the four
memory changes and nothing else.

## Provider behaviour — established on nas01, 2026-09-09

`Telmate/proxmox 3.0.2-rc03` **does the work and then reports it as an error.**
Observed on the `nas01` apply:

```
module.dev_proxmox_vms["nas01"].proxmox_vm_qemu.this: Modifying...
module.dev_proxmox_vms["nas01"].proxmox_vm_qemu.this: Still modifying... [00m10s elapsed]
│ Error: VM 100 already running
```

What actually happened: the provider stopped the VM, started it with the new
memory, then issued a second, redundant start against the now-running VM and
failed on it. Verified after the fact — the QEMU PID changed from `3321316` to
`2763173`, `qm list` showed `MEM(MB) 8192`, and the live process carried
`-m 8192`. The change was fully applied.

Three consequences, and the third is the dangerous one:

1. **`apply` will exit non-zero on every one of these VMs.** Expect it. A failed
   apply here is not evidence that anything is wrong.
2. **The reboot is real.** The provider performs a genuine stop/start, so
   `automatic_reboot` is doing its job even though the run ends in an error. Do
   not add a manual `qm shutdown` on top — that would be a second outage.
3. **Terraform records the change as applied anyway.** After the `nas01` failure,
   state held `memory: 8192` and the serial had advanced 101 → 103. A subsequent
   `terraform plan` therefore reports *no changes pending* for that VM whether or
   not the guest really got the memory. **`plan` is no longer a valid check after
   a failed apply, and re-running `apply` is the worst move available** — it would
   act on a resource Terraform already believes is converged. Verify against the
   hypervisor instead, using the checks below.

### Verifying an apply that "failed"

```bash
# On the hypervisor. PID must differ from before the apply; MEM(MB) must be new.
sudo qm list | grep -E 'NAME|<vm-name>'

# Authoritative: what the running QEMU process was actually started with.
sudo ps -eo args | grep -- '-id <vmid>' | grep -oE ' -m [0-9]+'
```

If `-m` shows the new value, the step succeeded — move on. If it shows the old
one, the VM was never restarted: the config is staged and a clean
`sudo qm shutdown <vmid> && sudo qm start <vmid>` will apply it.

## Execution

Every command below carries `-chdir`, so it is safe to paste from any
directory. A bare `terraform apply` run from the wrong place fails with
`No configuration files` -- harmless, but it wastes a step in the middle of
a maintenance window.

```bash
TF=/home/nazman/Документы/terraform/infra/proxmox

# 0. Confirm the blast radius before touching anything.
terraform -chdir=$TF plan     # expect exactly 4 memory changes, no replacements
```

Run `plan` **before the first apply only.** Once an apply has failed-but-applied,
state is ahead of what the plan can tell you.

Then, **one VM per step**:

```bash
# 1. nas01 (VMID 100) — quiet window; all 27 PVCs stall for the reboot
terraform -chdir=$TF apply -target='module.dev_proxmox_vms["nas01"]'
```

**DONE 2026-09-09.** Ended in `Error: VM 100 already running`; the change had
applied regardless (PID 3321316 → 2763173, `-m 8192`). The outage was short
enough that nothing in the cluster noticed: MinIO's four pods stayed up with
zero restarts on a 21-day uptime, every PVC stayed `Bound`, and no pod left
`Running`. The `hard` NFS mounts blocked and resumed exactly as intended. The
one `Pending` PVC (`trivy-dashboard`, storage class `managed-csi-premium`) has
been pending for 84 days and is unrelated.

Gate before continuing — on any cluster node:

```bash
export KUBECONFIG=~/.kube/hetzner
kubectl get pods -A | grep -vE 'Running|Completed'   # expect empty-ish
kubectl get pvc -A | grep -v Bound                   # expect none
```

```bash
# 2. k8s01 (VMID 102) — expect the "already running" error; verify, do not retry
terraform -chdir=$TF apply -target='module.dev_proxmox_vms["k8s01"]'
sudo ps -eo args | grep -- '-id 102' | grep -oE ' -m [0-9]+'    # expect -m 16384
```

**DONE 2026-09-09.** Same `already running` error, change applied: the node
came back `Ready` with capacity `16376996Ki`. It also detonated the
`/etc/hosts` landmine described above — `minio-comintern-pool-0-2` sat in
`Unknown` for ~15 minutes, unable to mount, until the entry was restored. The
pod then came up on its own with no intervention beyond that. All four nodes
have since been inoculated, so steps 3 and 4 should not repeat it.

From here on each apply reboots a control-plane node that is also an etcd
member. The node will be gone for the length of a stop/start, so treat the
gate below as mandatory rather than advisory.

Before each remaining reboot, on the node about to go down:

```bash
getent hosts nas01        # must answer 10.163.11.100
```

Gate — **etcd must be healthy on all three members before the next step**:

```bash
sudo systemctl is-active etcd                        # on k8s01, k8s02, k8s03
sudo etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cert=/etc/ssl/etcd/ssl/admin-$(hostname).pem \
  --key=/etc/ssl/etcd/ssl/admin-$(hostname)-key.pem \
  endpoint health --cluster
# All three endpoints must report healthy. Verified 2026-09-09 after step 3:
# commits took 10-13ms and `member list` showed etcd1/2/3 all started.
kubectl get nodes                                    # all Ready
```

```bash
# 3. k8s02 (VMID 103)
terraform -chdir=$TF apply -target='module.dev_proxmox_vms["k8s02"]'
sudo ps -eo args | grep -- '-id 103' | grep -oE ' -m [0-9]+'    # expect -m 16384
```

**DONE 2026-09-09.** This one exited `Apply complete! Resources: 0 added, 1
changed, 0 destroyed` -- no error, 1m54s instead of 30s. So the "already
running" failure is a race, not a certainty: expect it, but do not treat a
clean run as suspicious. The node came back with capacity `16377004Ki`.

This step was also the first real test of the `/etc/hosts` fix, and it held:
`getent hosts nas01` answered on k8s02 after the reboot, and
`minio-comintern-pool-0-1` remounted and returned to 2/2 on its own. Without
that fix this step would have taken the tenant to two of four. `openclaw`,
also on k8s02, sat in `Unknown` for about a minute and recovered unaided.

**Run the etcd gate again here.** Two of the three members have now been
restarted; starting k8s03 before k8s02 is back in the quorum leaves one member
of three and takes the API server down with it.

```bash
# 4. k8s03 (VMID 101 — NOT k8s01; the numbering does not match the names)
terraform -chdir=$TF apply -target='module.dev_proxmox_vms["k8s03"]'
sudo ps -eo args | grep -- '-id 101' | grep -oE ' -m [0-9]+'    # expect -m 16384
```

Run the etcd gate a third time before moving on to the kubelet step.

**Step 4 DONE 2026-09-09.** Clean `Apply complete` again, no error. k8s03 came
back at `16377000Ki`, `nas01` still resolved, and all three etcd endpoints
reported healthy (7-11ms commits). That ends the reboots.

Finally, the kubelet reservations -- the change the whole runbook exists for.

Use `--tags=kubelet`, not `--tags=node`. The task that writes
`/etc/kubernetes/kubelet-config.yaml` (`roles/kubernetes/node/tasks/kubelet.yml`)
carries the `kubelet` and `kubeadm` tags and notifies the restart handler, so
`kubelet` is the minimal scope that does the job. `node` is the whole role --
kubelet binary install, nginx-proxy, kube-vip -- none of which needs touching.

```bash
cd ~/Документы/kubespray
./bin/ansible-playbook -i inventory/hetzner1/hosts.ini cluster.yml \
  --become --tags=kubelet,download --limit=k8s04
./bin/ansible-playbook -i inventory/hetzner1/hosts.ini cluster.yml \
  --become --tags=kubelet,download --limit=k8s01,k8s02,k8s03
```

**Three flags, all three learned the hard way. None is optional:**

- **`--become`.** Nothing sets it -- not `ansible.cfg`, not the inventory -- so
  it must be on the command line. Without it the run dies at
  `chown failed: Operation not permitted: /tmp/releases`. Earlier tasks
  deceptively pass, because the directories they touch already exist and need
  no change.
- **`download` alongside `kubelet`.** `main.yml` imports `install.yml` under the
  `kubelet` tag, and import tags propagate to every task inside, so the binary
  copies run whether you want them or not. They read from `/tmp/releases`, which
  had been cleaned away, giving
  `Source /tmp/releases/kubeadm-1.34.3-amd64 not found`. The binaries in
  `/usr/local/bin` were already current; the download just re-supplies the
  source the copy expects.
- **Every etcd member in one `--limit`.** `--limit=k8s01` alone fails with
  `Unrecognized type AnsibleUndefined for ipwrap filter`: a control-plane task
  builds the etcd endpoint list from `hostvars[item]['main_access_ip']` across
  all of `etcd_hosts`, and hosts outside the limit have no facts. k8s03 got away
  with `--limit` only because it is not in `kube_control_plane` and skipped that
  task. Run the three etcd members together.

Each failure was clean -- the config was never written, kubelet stayed active,
nothing was left half-applied.

Consider `--limit` one node at a time. A kubelet restart does not kill running
pods (containerd keeps them), but the node goes briefly `NotReady`, and after
this particular day there is no prize for doing all four at once.

Before, on any node:

```yaml
kubeReserved:   {cpu: 100m, memory: 256Mi, ...}
systemReserved: {cpu: 500m, memory: 512Mi, ...}
# no evictionHard block at all -- which is why the kubelet default of
# memory.available<100Mi applied
```

After, expect `1Gi` / `2Gi` and an `evictionHard` block carrying
`memory.available: 500Mi` and `nodefs.available: 10%`.

**Result, measured 2026-09-09 after all five steps:**

| node | capacity | allocatable | requests |
|---|---|---|---|
| k8s01 | 16376996Ki | 12719268Ki | 891940Ki (7%) |
| k8s02 | 16377004Ki | 12719276Ki | 1350692Ki (10%) |
| k8s03 | 16377000Ki | 12719272Ki | 2854454Ki (22%) |
| k8s04 | 8131780Ki | 4474052Ki | 2085466Ki (46%) |

Capacity minus allocatable is now ~3.5Gi per node instead of 868Mi, so
host-deployed etcd and the OS are finally accounted for. All nodes `Ready`, all
three etcd endpoints healthy at 8-16ms, no pod evicted, MinIO 4/4.

kube-apiserver's ~2Gi is still unaccounted -- that waits on the dormant kubeadm
patch and the next `upgrade-cluster.yml`. The gap it leaves is now 2Gi out of
12.7Gi rather than 2Gi out of 7.2Gi on a node that was already full.

## Verification

```bash
export KUBECONFIG=~/.kube/hetzner

# Capacity grew and allocatable now reflects the reservations
kubectl get nodes -o custom-columns=\
'NAME:.metadata.name,CAP:.status.capacity.memory,ALLOC:.status.allocatable.memory'
# expect ~16Gi capacity on k8s01/02/03, and capacity-allocatable ≈ 3.5Gi

# The gap that started all this
kubectl describe node k8s02 | sed -n '/Allocated resources/,/Events/p'
kubectl top nodes

# Kuma stops restarting
kubectl get pod -n uptime-kuma -o wide
```

Leave it a few days and check that `ntfy` stops receiving Knex-shaped alerts.
That is the real acceptance test.

## Rollback

Revert the memory values in `dev_vms.tf` and re-apply per VM, same one-at-a-time
rule. For the kubelet side, delete `node-resources.yml` and re-run
`cluster.yml --tags=node`; the role defaults return (256Mi/512Mi, 100Mi
eviction). Nothing here is destructive — no volumes, no data paths are touched.

## What this does not fix

- **The kubeadm patch is dormant.** `--patches` is passed only from
  `roles/kubernetes/control-plane/tasks/kubeadm-upgrade.yml`, so a plain
  `cluster.yml` run against an initialised cluster writes the patch file but does
  not regenerate the static manifest. kube-apiserver gets its memory request on
  the next `upgrade-cluster.yml`. Until then the reservations carry it.
- **Kuma's database is still SQLite on NFS.** The probe change and this runbook
  both buy time; the cure is moving it off NFS. Note that Uptime Kuma 2.3.0
  supports only `sqlite`, `mariadb` and `embedded-mariadb` — verified in
  `/app/server/database.js` — so an external PostgreSQL cannot be used, despite
  the `pg` module being present in `node_modules` as a knex transitive
  dependency.
- **MinIO runs all 16 volumes over NFS to a single VM.** An object store built
  for direct-attached disks, with no redundancy against the loss of `nas01`.
  Structural; out of scope here.
- **Log shipping to OpenSearch has been broken since at least 2026-08-23.**
  Found while verifying step 5, and unrelated to any of this work. `fluentd` on
  k8s03 went `CrashLoopBackOff` after its reboot -- `[401] Unauthorized` against
  OpenSearch, killed at exit 137 before it could finish starting. Its twin on
  k8s04 reads `1/1 Running` with zero restarts in 169 days and looks perfectly
  healthy, but its log holds 48 `401`s, the most recent dated 2026-08-23: it is
  not delivering logs either. It merely started back when the credentials still
  worked, and it will present exactly as k8s03 does the moment it restarts.
  Fixing it needs the OpenSearch credentials and is a separate job.

  That was the third latent failure a reboot exposed today, after the NFS
  hostname and the provider's phantom error. They share a shape worth naming:
  **a process that started while things worked goes on looking healthy long
  after they stopped working, and a cluster that never restarts never finds
  out.**

- **The kubespray inventory is not version-controlled.** `inventory/` is covered
  by kubespray's own `.gitignore`, so the cluster's configuration — including
  the file this runbook adds — exists only on one laptop.
