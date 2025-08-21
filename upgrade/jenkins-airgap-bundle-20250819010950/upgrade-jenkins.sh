helm upgrade --install --create-namespace -n devops jenkins ./charts/jenkins-4.3.3.tgz -f ./values/jenkins.yaml \
      --timeout 600s \

