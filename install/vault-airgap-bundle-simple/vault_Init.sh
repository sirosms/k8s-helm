kubectl --namespace devops-vault exec -it pod/vault-0 -- vault status
kubectl --namespace devops-vault exec -it pod/vault-0 -- vault operator init