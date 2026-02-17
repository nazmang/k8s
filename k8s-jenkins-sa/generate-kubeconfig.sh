#!/usr/bin/env bash

set -e

# ========= Settings =========
SA_NAME="jenkins"
SA_NAMESPACE="kube-system"
CONTEXT_NAME="jenkins-context"
CLUSTER_NAME="jenkins-cluster"
OUTPUT_FILE="kubeconfig-${CLUSTER_NAME}.yaml"

# Token TTL can be set as needed. Default is 1 year (8760 hours). Adjust as necessary for your use case.
TOKEN_DURATION="8760h"
# ==============================

echo ">> Checking ServiceAccount..."

kubectl get sa ${SA_NAME} -n ${SA_NAMESPACE} >/dev/null

echo ">> Getting cluster endpoint..."
SERVER=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.server}')

echo ">> Getting CA data..."
CA_DATA=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

echo ">> Creating token via TokenRequest API..."
TOKEN=$(kubectl -n ${SA_NAMESPACE} create token ${SA_NAME} --duration=${TOKEN_DURATION})

echo ">> Generating kubeconfig..."

cat <<EOF > ${OUTPUT_FILE}
apiVersion: v1
kind: Config
clusters:
- name: ${CLUSTER_NAME}
  cluster:
    server: ${SERVER}
    certificate-authority-data: ${CA_DATA}

users:
- name: ${SA_NAME}
  user:
    token: ${TOKEN}

contexts:
- name: ${CONTEXT_NAME}
  context:
    cluster: ${CLUSTER_NAME}
    user: ${SA_NAME}
    namespace: default

current-context: ${CONTEXT_NAME}
EOF

echo ">> Kubeconfig generated: ${OUTPUT_FILE}"
echo ">> Test with:"
echo "   KUBECONFIG=${OUTPUT_FILE} kubectl get pods"
