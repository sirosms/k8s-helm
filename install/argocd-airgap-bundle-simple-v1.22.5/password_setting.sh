kubectl -n devops-argocd patch secret argocd-secret -p '{"stringData": {"accounts.pmwp.password": "'$(htpasswd -bnBC 10 "" pmwp123! | tr -d ':\n' | sed │
│ 's/$2y/$2a/')'"}}

kubectl rollout restart deployment/argocd-server -n devops-argocd