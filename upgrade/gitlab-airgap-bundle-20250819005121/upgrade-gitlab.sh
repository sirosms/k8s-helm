helm upgrade --install --create-namespace -n devops gitlab ./charts/gitlab-6.8.0.tgz -f ./values/gitlab.yaml \
      --set certmanager-issuer.email=myeongs.seo@partner.samsung.com \
      --set certmanager.install=false \
      --timeout 600s \

