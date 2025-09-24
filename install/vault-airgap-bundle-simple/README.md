# HashiCorp Vault 설치

이 스크립트는 Kubernetes 클러스터에 HashiCorp Vault를 설치합니다.

## 사전 요구사항

1. **Kubernetes 클러스터**
   - kubectl 명령어 설정 완료
   - Helm 3.x 설치

2. **Storage Class**
   - `gp2` Storage Class 설정 완료

3. **TLS 인증서**
   - `secl.samsung.co.kr-tls` Secret이 devops-vault 네임스페이스에 존재

## 설치 순서

### 1. 이미지 로드

먼저 Vault 이미지를 로드합니다:

```bash
./02_load_images.sh
```

### 2. Vault 설치

설치 스크립트를 실행합니다:

```bash
./03_install_vault.sh
```

스크립트 실행 중 다음 정보를 입력해야 합니다:
- Vault 외부 URL (기본값: https://vault-dev.secl.samsung.co.kr)

## 설치 확인

설치 완료 후 다음 명령으로 상태를 확인할 수 있습니다:

```bash
kubectl get pods -n devops-vault
kubectl get svc -n devops-vault
kubectl get ingress -n devops-vault
```

## 접속 방법

### 1. Ingress를 통한 접속

브라우저에서 설정한 URL로 접속:
- https://vault-dev.secl.samsung.co.kr

### 2. Port Forward를 통한 접속

```bash
kubectl port-forward -n devops-vault svc/vault 8200:8200
```
브라우저에서 http://localhost:8200 접속

## 초기 설정

### Vault 초기화

Vault를 처음 설치한 후에는 반드시 초기화를 해야 합니다:

```bash
# Vault 초기화
kubectl exec -it -n devops-vault vault-0 -- vault operator init
```

이 명령을 실행하면 5개의 Unseal Key와 1개의 Root Token이 생성됩니다.

**중요**: 이 키들을 반드시 안전한 곳에 저장하세요!

### Vault Unsealing

Vault를 사용하기 전에 3개의 Unseal Key로 unsealing을 해야 합니다:

```bash
# 3번 반복 (서로 다른 key 사용)
kubectl exec -it -n devops-vault vault-0 -- vault operator unseal <UNSEAL_KEY_1>
kubectl exec -it -n devops-vault vault-0 -- vault operator unseal <UNSEAL_KEY_2>
kubectl exec -it -n devops-vault vault-0 -- vault operator unseal <UNSEAL_KEY_3>
```

### 로그인 정보
- Root Token: 초기화 시 생성된 Root Token 사용
- 웹 UI에서 Token 인증 선택 후 Root Token 입력

## 구성 요소

- **네임스페이스**: devops-vault
- **구성 요소**:
  - HashiCorp Vault Server (HA 모드)
  - Consul Storage Backend (선택적)
- **이미지**:
  - hashicorp/vault:1.13.3
  - hashicorp/consul:1.15.3 (Consul 사용 시)
- **포트**: 8200 (HTTP/HTTPS), 8201 (Cluster)
- **PVC**:
  - vault-data (10Gi) - Vault 데이터 저장
  - consul-data (5Gi) - Consul 데이터 저장 (Consul 사용 시)

## 문제 해결

### PVC 생성 실패
Storage Class `gp2`가 설정되어 있는지 확인:
```bash
kubectl get storageclass
```

### TLS 인증서 문제
secl.samsung.co.kr-tls Secret이 존재하는지 확인:
```bash
kubectl get secret secl.samsung.co.kr-tls -n devops-vault
```

### Pod 시작 실패
리소스 부족 또는 PVC 마운트 문제일 수 있습니다:
```bash
kubectl describe pod -n devops-vault
kubectl logs -n devops-vault -l app=vault
```

### Vault Sealed 상태
Vault가 Sealed 상태일 경우 위의 Unsealing 단계를 수행:
```bash
kubectl exec -it -n devops-vault vault-0 -- vault status
```

### 초기화 실패
Vault가 이미 초기화되어 있는 경우:
```bash
kubectl logs -n devops-vault vault-0 | grep -i "already initialized"
```

### HA 모드 문제
모든 Vault replica가 정상 작동하는지 확인:
```bash
kubectl get pods -n devops-vault -l app=vault
kubectl exec -it -n devops-vault vault-0 -- vault operator raft list-peers
```