# Mattermost Airgap Bundle Deployment

## 📋 Deployment Checklist

### Prerequisites
- [ ] AWS EKS cluster ready
- [ ] ECR repositories created and accessible
- [ ] RDS PostgreSQL instance available
- [ ] kubectl configured for target cluster
- [ ] Helm 3.x installed
- [ ] Docker installed (for image operations)

### Infrastructure Setup
- [ ] Create ECR repositories
  ```bash
  aws ecr create-repository --repository-name mattermost-team-edition --region ap-northeast-2
  aws ecr create-repository --repository-name curl --region ap-northeast-2
  ```

- [ ] Configure RDS PostgreSQL
  - [ ] Verify RDS instance: `gitlab-dev-postgres.c8thupqwxcj4.ap-northeast-2.rds.amazonaws.com`
  - [ ] Master user: `gitlab`
  - [ ] Reset password if needed: `./reset_rds_password.sh`
  - [ ] Test connection: `./test_rds_connection.sh`
  - [ ] Create Mattermost database and user: `./create_rds_user.sh`

### Image Management
- [ ] Download images for airgap deployment
  ```bash
  ./01_download_images.sh
  ```
- [ ] Push images to ECR
  ```bash
  ./04_push_to_ecr.sh
  ```

### Kubernetes Deployment
- [ ] Create namespace
  ```bash
  kubectl create namespace devops-mattermost
  ```
- [ ] Create PVCs
  ```bash
  kubectl apply -f pvc/mattermost-pvc.yaml
  ```
- [ ] Install Mattermost
  ```bash
  ./03_install_mattermost.sh
  ```

### Verification
- [ ] Check pod status
  ```bash
  kubectl get pods -n devops-mattermost
  ```
- [ ] Check service status
  ```bash
  kubectl get svc -n devops-mattermost
  ```
- [ ] Check ingress status
  ```bash
  kubectl get ingress -n devops-mattermost
  ```
- [ ] Test web access: https://mattermost-dev.samsungena.io
- [ ] Test port-forward access
  ```bash
  kubectl port-forward -n devops-mattermost svc/mattermost-team-edition 8065:8065
  ```

### Post-Deployment
- [ ] Complete Mattermost initial setup via web UI
- [ ] Configure admin user
- [ ] Test database connectivity
- [ ] Verify SSL certificate
- [ ] Check persistent storage functionality

## 🔧 Configuration Details

### Images Used
- `mattermost/mattermost-team-edition:7.2.0@sha256:4c888860392d800a6c3efabb26173ddc401bed46139007a4d116f1c91b5914a4`
- `appropriate/curl:latest`

### ECR Repositories
- `866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/mattermost-team-edition:7.2.0`
- `866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/curl:latest`

### Database Configuration
- Host: `gitlab-dev-postgres.c8thupqwxcj4.ap-northeast-2.rds.amazonaws.com:5432`
- Database: `mattermost`
- User: `mattermost`
- Connection String: `mattermost:epqmdhqtm1@@gitlab-dev-postgres.c8thupqwxcj4.ap-northeast-2.rds.amazonaws.com:5432/mattermost?sslmode=disable&connect_timeout=10`

### Storage Configuration
- Data PVC: `mattermost-data` (10Gi, gp2)
- Plugins PVC: `mattermost-plugins` (1Gi, gp2)

### Ingress Configuration
- URL: https://mattermost-dev.samsungena.io
- SSL Certificate: `samsungena.io-tls`
- Ingress Class: nginx

## 🐛 Troubleshooting

### Common Issues
1. **Pod stuck in ContainerCreating**
   - Check PVC binding status
   - Verify ECR image pull secrets
   
2. **Database connection failures**
   - Verify RDS connectivity
   - Check database user permissions
   - Test connection string

3. **Ingress not working**
   - Check nginx-ingress-controller installation
   - Verify SSL certificate existence
   - Check DNS resolution

### Useful Commands
```bash
# Check logs
kubectl logs -n devops-mattermost -l app.kubernetes.io/name=mattermost-team-edition

# Describe pod for events
kubectl describe pod -n devops-mattermost -l app.kubernetes.io/name=mattermost-team-edition

# Check PVC events
kubectl describe pvc -n devops-mattermost

# Test database connection from pod
kubectl exec -it -n devops-mattermost deployment/mattermost-mattermost-team-edition -- /bin/sh
```