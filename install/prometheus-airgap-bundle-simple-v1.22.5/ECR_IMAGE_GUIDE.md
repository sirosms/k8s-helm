# Prometheus Airgap Installation - ECR Image Guide

## Overview
Docker save는 현재 manifest 이슈로 인해 실패하고 있습니다. 
대신 폐쇄망 환경에서는 다음의 ECR 이미지들을 사용하시기 바랍니다.

## Required ECR Images for Airgap Installation

### ECR Registry: 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com

다음 이미지들을 ECR에 미리 푸시해야 합니다:

```bash
# Main Prometheus Stack Images
866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/prometheus:v3.5.0
866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/alertmanager:v0.28.1  
866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/grafana:11.1.0
866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/node-exporter:v1.8.2
866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/kube-state-metrics:v2.13.0
866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/prometheus-operator:v0.85.0
866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/prometheus-config-reloader:v0.85.0

# Optional Components  
866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/thanos:v0.39.2
866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/configmap-reload:v0.8.0

# Additional Images for Airgap
866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/busybox:1.31.1
866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/kube-webhook-certgen:v1.6.2
866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/k8s-sidecar:1.30.10
```

## Image Tagging Commands

인터넷이 연결된 환경에서 다음 명령어로 이미지를 태그하고 ECR에 푸시하세요:

```bash
# ECR Login
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com

# Tag and Push Images
# Prometheus
docker tag quay.io/prometheus/prometheus:v3.5.0 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/prometheus:v3.5.0
docker push 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/prometheus:v3.5.0

# AlertManager  
docker tag quay.io/prometheus/alertmanager:v0.28.1 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/alertmanager:v0.28.1
docker push 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/alertmanager:v0.28.1

# Grafana
docker tag grafana/grafana:11.1.0 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/grafana:11.1.0
docker push 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/grafana:11.1.0

# Node Exporter
docker tag quay.io/prometheus/node-exporter:v1.8.2 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/node-exporter:v1.8.2  
docker push 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/node-exporter:v1.8.2

# Kube State Metrics
docker tag registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.13.0 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/kube-state-metrics:v2.13.0
docker push 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/kube-state-metrics:v2.13.0

# Prometheus Operator
docker tag quay.io/prometheus-operator/prometheus-operator:v0.85.0 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/prometheus-operator:v0.85.0
docker push 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/prometheus-operator:v0.85.0

# Config Reloader  
docker tag quay.io/prometheus-operator/prometheus-config-reloader:v0.85.0 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/prometheus-config-reloader:v0.85.0
docker push 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/prometheus-config-reloader:v0.85.0

# Thanos (Optional)
docker tag quay.io/thanos/thanos:v0.39.2 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/thanos:v0.39.2
docker push 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/thanos:v0.39.2

# ConfigMap Reload
docker tag jimmidyson/configmap-reload:v0.8.0 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/configmap-reload:v0.8.0
docker push 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/configmap-reload:v0.8.0

# Busybox
docker tag busybox:1.31.1 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/busybox:1.31.1
docker push 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/busybox:1.31.1

# Webhook CertGen
docker tag registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.2 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/kube-webhook-certgen:v1.6.2
docker push 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/kube-webhook-certgen:v1.6.2

# K8s Sidecar
docker tag quay.io/kiwigrid/k8s-sidecar:1.30.10 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/k8s-sidecar:1.30.10
docker push 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/k8s-sidecar:1.30.10
```

## Current Status

- ✅ values/prometheus.yaml 파일은 이미 ECR 레지스트리를 사용하도록 구성됨
- ✅ install 스크립트는 ECR credential secret을 자동으로 생성함  
- ✅ Helm 차트는 registry prefix 문제가 해결된 상태임
- ❌ Docker save가 manifest 이슈로 실패 (workaround: ECR 사용)

## Installation Flow for Airgap

1. **인터넷 연결 환경에서**: 위의 태깅/푸시 명령어로 모든 이미지를 ECR에 업로드
2. **폐쇄망 환경에서**: 
   - ECR 접근이 가능한지 확인
   - `./03_install_prometheus.sh` 실행
   - 스크립트가 ECR credential을 자동 생성하고 설치 진행