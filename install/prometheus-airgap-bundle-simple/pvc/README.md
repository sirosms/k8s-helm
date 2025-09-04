# Prometheus PVC 사전 생성 가이드

## 개요
폐쇄망 환경에서 Prometheus 설치 전에 필요한 PVC를 미리 생성하여 스토리지 문제를 방지합니다.

## 생성되는 PVC 목록

### 1. Grafana PVC
- **파일**: `prometheus-grafana-pvc.yaml`
- **크기**: 5Gi
- **용도**: Grafana 대시보드, 설정, 플러그인 데이터
- **StorageClass**: gp2

### 2. Prometheus Server PVC
- **파일**: `prometheus-server-pvc.yaml`
- **크기**: 20Gi
- **용도**: Prometheus 메트릭 데이터 저장 (TSDB)
- **StorageClass**: gp2
- **보존 기간**: 15일 (values.yaml 설정)

### 3. AlertManager PVC
- **파일**: `alertmanager-pvc.yaml`
- **크기**: 5Gi
- **용도**: AlertManager 설정, 알람 상태, 실행 이력
- **StorageClass**: gp2

## 사용 방법

### 1. 개별 PVC 생성
```bash
# 네임스페이스 생성 (필요시)
kubectl create namespace devops-prometheus

# 개별 PVC 생성
kubectl apply -f pvc/prometheus-grafana-pvc.yaml
kubectl apply -f pvc/prometheus-server-pvc.yaml
kubectl apply -f pvc/alertmanager-pvc.yaml
```

### 2. 일괄 PVC 생성 (권장)
```bash
# 스크립트 실행
./pvc/create-all-pvcs.sh
```

### 3. PVC 상태 확인
```bash
kubectl get pvc -n devops-prometheus
```

## 예상 결과
```
NAME                                                                                                               STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS
alertmanager-prometheus-kube-prometheus-alertmanager-db-alertmanager-prometheus-kube-prometheus-alertmanager-0   Bound    pvc-xxx-xxx-xxx                           5Gi        RWO            gp2
prometheus-grafana                                                                                                 Bound    pvc-xxx-xxx-xxx                           5Gi        RWO            gp2
prometheus-prometheus-kube-prometheus-prometheus-db-prometheus-prometheus-kube-prometheus-prometheus-0           Bound    pvc-xxx-xxx-xxx                           20Gi       RWO            gp2
```

## 주의사항

### 1. PVC 이름 정확성
- Prometheus Operator가 생성하는 StatefulSet PVC 이름과 정확히 일치해야 함
- 이름이 다르면 새로운 PVC가 생성됨

### 2. StorageClass 호환성
- `gp2` StorageClass가 클러스터에 존재해야 함
- 다른 StorageClass 사용 시 yaml 파일 수정 필요

### 3. 네임스페이스
- 반드시 `devops-prometheus` 네임스페이스에 생성
- 다른 네임스페이스 사용 시 values.yaml과 일치시킬 것

## 스토리지 용량 조정

### 용량 변경이 필요한 경우:
1. **Prometheus**: 메트릭 보존 기간에 따라 20Gi → 50Gi 등 조정
2. **Grafana**: 대시보드 수에 따라 5Gi → 10Gi 등 조정
3. **AlertManager**: 일반적으로 5Gi면 충분

### 변경 방법:
```yaml
# prometheus-server-pvc.yaml
resources:
  requests:
    storage: 50Gi  # 20Gi에서 50Gi로 변경
```

## 트러블슈팅

### PVC가 Pending 상태인 경우:
```bash
kubectl describe pvc <pvc-name> -n devops-prometheus
```

### 일반적인 해결 방법:
1. **StorageClass 확인**: `kubectl get storageclass`
2. **노드 용량 확인**: 디스크 용량 부족 여부
3. **권한 확인**: PVC 생성 권한 여부

## 설치 후 확인

PVC 사전 생성 후 Prometheus 설치 시:
1. 기존 PVC를 재사용함
2. 데이터 손실 없이 업그레이드 가능
3. 스토리지 관련 오류 방지