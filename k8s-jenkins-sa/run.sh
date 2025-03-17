kubectl apply -f serviceaccount.yaml
kubectl apply -f rolebinding.yaml
kubectl apply -f secret.yaml
kubectl -n kube-system get secret jenkins-sa-token -o jsonpath="{.data.token}" | base64 --decode


