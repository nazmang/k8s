# k8s Deployments Overview

Below is a table of subdirectories containing deployment manifests and charts, with a short description and a status badge.

| Directory | Short description | Status |
|---|---|---:|
| [apps/](apps/) | ArgoCD Application manifests and app-specific configurations. | [![status](https://img.shields.io/badge/status-unknown-lightgrey)](apps/) |
| [charts/](charts/) | Helm charts (shared/local charts). | [![status](https://img.shields.io/badge/status-unknown-lightgrey)](charts/) |
| [helm-argocd/](helm-argocd/) | ArgoCD Helm chart for GitOps management. | [![status](https://jenkins.srvxapp.com/buildStatus/icon?job=k8s+Deployments%2Finitial%2Fargocd-deploy)](http://jenkins.srvxapp.com/job/k8s%20Deployments/job/initial/job/argocd-deploy/) |
| [helm-certmanager/](helm-certmanager/) | Cert-Manager Helm chart for TLS certificate management. | [![status](https://img.shields.io/badge/status-unknown-lightgrey)](helm-certmanager/) |
| [helm-external-dns/](helm-external-dns/) | ExternalDNS Helm chart for DNS record management. | [![status](https://img.shields.io/badge/status-unknown-lightgrey)](helm-external-dns/) |
| [helm-ingress-nginx/](helm-ingress-nginx/) | Ingress-NGINX controller and related configs. | [![status](https://img.shields.io/badge/status-unknown-lightgrey)](helm-ingress-nginx/) |
| [helm-mailhog/](helm-mailhog/) | MailHog test SMTP server Helm chart. | [![status](https://img.shields.io/badge/status-unknown-lightgrey)](helm-mailhog/) |
| [helm-metallb/](helm-metallb/) | MetalLB for providing network load balancing (L2/L3). | [![status](https://img.shields.io/badge/status-unknown-lightgrey)](helm-metallb/) |
| [helm-nfs-client-provisioner/](helm-nfs-client-provisioner/) | NFS client provisioner for dynamic PersistentVolumes. | [![status](https://img.shields.io/badge/status-unknown-lightgrey)](helm-nfs-client-provisioner/) |
| [helm-prometheus/](helm-prometheus/) | Prometheus and exporters for monitoring. | [![status](https://img.shields.io/badge/status-unknown-lightgrey)](helm-prometheus/) |
| [helm-redis/](helm-redis/) | Redis Helm chart (standalone or cluster). | [![status](https://img.shields.io/badge/status-unknown-lightgrey)](helm-redis/) |
| [helm-reloader/](helm-reloader/) | Reloader to restart workloads on config/secret changes. | [![status](https://img.shields.io/badge/status-unknown-lightgrey)](helm-reloader/) |
| [helm-trustmanager/](helm-trustmanager/) | Trust manager for managing trusted certificates. | [![status](https://img.shields.io/badge/status-unknown-lightgrey)](helm-trustmanager/) |
| [helm-vault/](helm-vault/) | HashiCorp Vault Helm chart and auto-unseal setup. | [![status](https://img.shields.io/badge/status-unknown-lightgrey)](helm-vault/) |
| [k8s-external-dns/](k8s-external-dns/) | Kubernetes manifests/configs for external-dns. | [![status](https://img.shields.io/badge/status-unknown-lightgrey)](k8s-external-dns/) |
| [k8s-gateway/](k8s-gateway/) | Gateway and network-related Kubernetes resources. | [![status](https://img.shields.io/badge/status-unknown-lightgrey)](k8s-gateway/) |
| [k8s-jenkins/](k8s-jenkins/) | Jenkins deployment, PVCs and related manifests. | [![status](https://img.shields.io/badge/status-unknown-lightgrey)](k8s-jenkins/) |
| [k8s-jenkins-sa/](k8s-jenkins-sa/) | ServiceAccount and secrets for Jenkins (see run.sh). | [![status](https://img.shields.io/badge/status-unknown-lightgrey)](k8s-jenkins-sa/) |
| [k8s-logging/](k8s-logging/) | Logging stack (Fluentd/FluentBit configurations). | [![status](https://img.shields.io/badge/status-unknown-lightgrey)](k8s-logging/) |
| [k8s-metrics-server/](k8s-metrics-server/) | Metrics Server manifests for Kubernetes metrics. | [![status](https://img.shields.io/badge/status-unknown-lightgrey)](k8s-metrics-server/) |
| [k8s-portainer-agent/](k8s-portainer-agent/) | Portainer agent manifests for remote management. | [![status](https://img.shields.io/badge/status-unknown-lightgrey)](k8s-portainer-agent/) |
| [k8s-postgres/](k8s-postgres/) | Postgres StatefulSet, PVCs and configs. | [![status](https://img.shields.io/badge/status-unknown-lightgrey)](k8s-postgres/) |
