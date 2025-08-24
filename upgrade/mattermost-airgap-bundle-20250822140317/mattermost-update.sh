helm repo add mattermost https://helm.mattermost.com
helm repo add incubator https://charts.helm.sh/incubator
helm repo update

helm upgrade --install --create-namespace -n devops-mattermost mattermost -f ./values.yaml mattermost/mattermost-team-edition