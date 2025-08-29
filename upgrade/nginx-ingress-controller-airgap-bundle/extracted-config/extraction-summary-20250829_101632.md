# Nginx Ingress Controller Configuration Extraction Summary

**Extraction Date:** Fri Aug 29 10:16:33 AM KST 2025
**Namespace:** devops-nginx-ingress
**Deployment:** dev-sds-ingress-ingress-controller

## Current Configuration
- **Image:** sscr.comm.scp-in.com/score-scpapps/nginx-ingress-controller:v1.12.4
- **Replicas:** 1
- **Service Type:** Unknown
- **Helm Managed:** No

## Extracted Files
- `deployment-20250829_101632.yaml` - Kubernetes Deployment
- `configmap-20250829_101632.yaml` - ConfigMaps
- `service-20250829_101632.yaml` - Services
- `serviceaccount-20250829_101632.yaml` - ServiceAccount
- `clusterrole-20250829_101632.yaml` - ClusterRole
- `clusterrolebinding-20250829_101632.yaml` - ClusterRoleBinding
- `generated-values-20250829_101632.yaml` - Generated Helm values



## Next Steps
1. Review generated-values-20250829_101632.yaml
2. Compare with new v1.3.0 values.yaml
3. Run validate-upgrade.sh to check compatibility
4. Execute upgrade-nginx-controller.sh for upgrade

## Backup Created
All current configurations have been backed up to: `./extracted-config/`
