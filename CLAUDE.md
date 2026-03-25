# k8s Deployments — Project Guide

## Overview

This repository manages all Kubernetes deployments across `cloud` and `onprem` clusters. Deployments are orchestrated by Jenkins using the [platform-deploy-lib](https://github.com/nazmang/platform-deploy-lib) shared library. Each subdirectory is an independent deployable project.

## How Deployments Work

The root `Jenkinsfile` loads `platform-deploy-lib@main` and calls `platformDeploy()`. Jenkins detects which projects changed (by git diff) and deploys only those, unless `FORCE_DEPLOY=true` or a specific `PROJECT` is set.

### Pipeline Parameters

| Parameter | Description |
|---|---|
| `CLUSTER` | Target cluster: `cloud` or `onprem` |
| `DEPLOY_TARGET` | `single` (one cluster) or `all` (both clusters) |
| `PROJECT` | Deploy a specific project directory by name |
| `FORCE_DEPLOY` | Skip change detection and deploy everything |
| `SKIP_PROJECT_INPUT` | Skip manual project selection; auto-deploy changed projects |

## deploy.yaml — the Deployment Descriptor

Every deployable project **must** have a `deploy.yaml` at its root. This file defines one or more steps and which environments they apply to.

### Supported Step Types

- **`helm`** — Install/upgrade a Helm chart from a remote repo
- **`kustomize`** — Apply a Kustomize overlay via `kubectl apply -k`
- **`manifest`** — Apply raw manifests via `kubectl apply -f`
- **`decrypt-sops`** — Decrypt a SOPS-encrypted file before use (stores result as env var or file)
- **`wait`** — Wait for a Kubernetes resource to become ready (useful after CRD installs)
- **`shell`** — Run an arbitrary shell command

### Environments

Steps are scoped per environment. Use `cloud`, `onprem`, or `default` as keys under `environments:`.

### Examples

**Helm project (multi-environment):**
```yaml
steps:
  - type: helm
    environments:
      cloud:
        config:
          repoName: ingress-nginx
          repoUrl: https://kubernetes.github.io/ingress-nginx
          chartName: ingress-nginx/ingress-nginx
          version: 4.13.2
          releaseName: ingress-nginx
          namespace: ingress-nginx
          values:
            - environments/cloud/ingress.values.yaml
      onprem:
        config:
          repoName: ingress-nginx
          repoUrl: https://kubernetes.github.io/ingress-nginx
          chartName: ingress-nginx/ingress-nginx
          version: 4.13.2
          releaseName: ingress-nginx
          namespace: ingress-nginx
          values:
            - environments/onprem/ingress.values.yaml
```

**Kustomize project:**
```yaml
steps:
  - type: kustomize
    environments:
      cloud:
        config:
          overlay: overlays/cloud
      onprem:
        config:
          overlay: overlays/onprem
```

**Kustomize project (single environment):**
```yaml
steps:
  - type: kustomize
    environments:
      default:
        config:
          overlay: overlays/default
```

**Multi-step with SOPS decryption:**
```yaml
steps:
  - type: helm
    environments:
      cloud:
        config:
          repoName: jetstack
          repoUrl: https://charts.jetstack.io
          chartName: jetstack/cert-manager
          version: v1.20.0
          releaseName: cert-manager
          namespace: cert-manager
          values:
            - environments/cloud/cert-manager.values.yaml
  - type: decrypt-sops
    environments:
      cloud:
        config:
          keyParameter: SOPS_AGE_KEY
          files:
            - environments/overlays/cloud/certmanager-config.yaml
  - type: manifest
    environments:
      cloud:
        config:
          file:
            - environments/overlays/cloud/certmanager-config.yaml
```

## Project Structure Conventions

```
project-name/
├── deploy.yaml                        # Required — deployment descriptor
├── environments/
│   ├── cloud/
│   │   └── values.yaml                # Helm values for cloud
│   └── onprem/
│       └── values.yaml                # Helm values for onprem
└── overlays/                          # For kustomize projects
    ├── cloud/
    │   └── kustomization.yaml
    └── onprem/
        └── kustomization.yaml
```

## Projects in This Repo

| Directory | Type | Description |
|---|---|---|
| `helm-ansible-semaphore/` | helm | Ansible Semaphore |
| `helm-argocd/` | helm+kustomize | ArgoCD GitOps |
| `helm-certmanager/` | helm+manifest | TLS certificate management |
| `helm-cloudflared/` | helm | Cloudflare tunnel |
| `helm-external-dns/` | helm | DNS record automation |
| `helm-ingress-nginx/` | helm | Ingress-NGINX controller |
| `helm-mailhog/` | helm | Test SMTP server |
| `helm-metallb/` | helm | L2/L3 load balancing |
| `helm-minio/` | helm | Object storage (operator + tenant) |
| `helm-nfs-client-provisioner/` | helm | Dynamic NFS PersistentVolumes |
| `helm-prometheus/` | helm | Prometheus monitoring stack |
| `helm-redis/` | helm | Redis |
| `helm-reloader/` | helm | Restart workloads on config changes |
| `helm-trustmanager/` | helm | Trusted certificate management |
| `helm-vault/` | helm | HashiCorp Vault + auto-unseal |
| `k8s-gateway/` | manifest | Gateway resources |
| `k8s-jenkins/` | manifest | Jenkins deployment |
| `k8s-jenkins-sa/` | manifest | Jenkins ServiceAccount |
| `k8s-logging/` | kustomize | Fluentd + FluentBit logging stack |
| `k8s-metrics-server/` | kustomize | Kubernetes Metrics Server |
| `k8s-portainer-agent/` | kustomize | Portainer agent |
| `k8s-postgres/` | manifest | PostgreSQL StatefulSet |

## Adding a New Project

1. Create a directory: `mkdir my-project`
2. Add a `deploy.yaml` with the appropriate step type and environment config
3. Add values files or overlays under `environments/` or `overlays/`
4. Commit — Jenkins will detect the new `deploy.yaml` and include it in project selection

## Deploy Image

Jenkins runs deployments inside the `nazman/k8s-deployer:latest` container (via pod template), which provides `kubectl` and `helm` binaries. The pod uses the `jenkins` ServiceAccount in the cluster.
