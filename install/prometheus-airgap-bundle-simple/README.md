# Prometheus Airgap Bundle Simple

Prometheus 폐쇄망 설치를 위한 스크립트 모음입니다.

## 디렉토리 구조

```
prometheus-airgap-bundle-simple/
├── 01_download_images.sh        # Docker 이미지 다운로드
├── 02_load_images.sh           # Docker 이미지 로드
├── 03_install_prometheus.sh    # Prometheus 설치
├── 04_push_to_ecr.sh          # ECR에 이미지 푸시
├── charts/                    # Helm 차트 저장소
├── images/                    # Docker 이미지 tar 파일
├── values/                    # Helm values 파일
│   └── prometheus.yaml        # Prometheus 설정
├── meta/                      # 메타데이터 파일
└── pvc/                       # PVC 설정 파일
```

## 사용 방법

### 1. 이미지 다운로드 (인터넷 연결 환경)
```bash
./01_download_images.sh
```

### 2. 이미지 로드 (폐쇄망 환경)
```bash
./02_load_images.sh
```

### 3. ECR에 이미지 푸시 (선택사항)
```bash
./04_push_to_ecr.sh
```

### 4. Prometheus 설치
```bash
./03_install_prometheus.sh
```

## 포함된 구성 요소

- **Prometheus Server**: v2.37.0
- **Grafana**: 9.1.0
- **AlertManager**: v0.24.0
- **Node Exporter**: v1.3.1
- **Kube State Metrics**: v2.5.0
- **Prometheus Operator**: v0.58.0

## 접속 정보

### Grafana
- URL: https://grafana-dev.samsungena.io (Ingress)
- Port-forward: `kubectl port-forward -n devops-prometheus svc/prometheus-grafana 3000:80`
- 계정: admin / admin123!

### Prometheus
- Port-forward: `kubectl port-forward -n devops-prometheus svc/prometheus-kube-prometheus-prometheus 9090:9090`
- URL: http://localhost:9090

### AlertManager
- Port-forward: `kubectl port-forward -n devops-prometheus svc/prometheus-kube-prometheus-alertmanager 9093:9093`
- URL: http://localhost:9093

## 설정 파일

`values/prometheus.yaml` 파일에서 다음 설정을 수정할 수 있습니다:

- ECR 레지스트리 주소
- 스토리지 클래스 및 용량
- Ingress 설정
- 보안 설정

## 요구사항

- Kubernetes 클러스터
- Helm 3.x
- Docker (이미지 작업용)
- AWS CLI (ECR 사용 시)