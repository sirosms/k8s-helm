# Keycloak 설치

이 스크립트는 Kubernetes 클러스터에 Keycloak을 설치합니다.

## 사전 요구사항

1. **Kubernetes 클러스터**
   - kubectl 명령어 설정 완료
   - Helm 3.x 설치

2. **Storage Class**
   - `gp2` Storage Class 설정 완료

3. **TLS 인증서**
   - `secl.samsung.co.kr-tls` Secret이 devops-keycloak 네임스페이스에 존재

## 설치 순서

### 1. 이미지 로드

먼저 Keycloak 이미지를 로드합니다:

```bash
./02_load_images.sh
```

### 2. Keycloak 설치

설치 스크립트를 실행합니다:

```bash
./03_install_keycloak.sh
```

스크립트 실행 중 다음 정보를 입력해야 합니다:
- Keycloak 외부 URL (기본값: https://keycloak-dev.secl.samsung.co.kr)
- 관리자 사용자명 (기본값: admin)
- 관리자 비밀번호

## 설치 확인

설치 완료 후 다음 명령으로 상태를 확인할 수 있습니다:

```bash
kubectl get pods -n devops-keycloak
kubectl get svc -n devops-keycloak
kubectl get ingress -n devops-keycloak
```

## 접속 방법

### 1. Ingress를 통한 접속

브라우저에서 설정한 URL로 접속:
- https://keycloak-dev.secl.samsung.co.kr

### 2. Port Forward를 통한 접속

```bash
kubectl port-forward -n devops-keycloak svc/keycloak 8080:8080
```
브라우저에서 http://localhost:8080 접속

## 초기 설정

### 관리자 콘솔 접속

웹 브라우저에서 `/admin` 경로로 접속:
- URL: https://keycloak-dev.secl.samsung.co.kr/admin

### 로그인 정보
- 사용자명: 설치 시 설정한 관리자 사용자명 (기본값: admin)
- 비밀번호: 설치 시 설정한 관리자 비밀번호

### 비밀번호 확인 (설치 스크립트에서 설정한 경우)

```bash
kubectl get secret keycloak-admin -n devops-keycloak -o jsonpath='{.data.admin-password}' | base64 -d
```

## 구성 요소

- **네임스페이스**: devops-keycloak
- **구성 요소**:
  - Keycloak Server
  - PostgreSQL Database (내장)
- **이미지**:
  - quay.io/keycloak/keycloak:19.0.3
  - postgres:13-alpine
- **포트**: 8080 (HTTP)

## 문제 해결

### PVC 생성 실패
Storage Class `gp2`가 설정되어 있는지 확인:
```bash
kubectl get storageclass
```

### TLS 인증서 문제
secl.samsung.co.kr-tls Secret이 존재하는지 확인:
```bash
kubectl get secret secl.samsung.co.kr-tls -n devops-keycloak
```

### Pod 시작 실패
리소스 부족 또는 PVC 마운트 문제일 수 있습니다:
```bash
kubectl describe pod -n devops-keycloak
kubectl logs -n devops-keycloak -l app=keycloak
```

### 데이터베이스 연결 문제
PostgreSQL 연결 상태 확인:
```bash
kubectl logs -n devops-keycloak -l app=postgresql
kubectl exec -it -n devops-keycloak <postgresql-pod-name> -- psql -U keycloak -d keycloak
```

### 관리자 계정 문제
관리자 계정 생성 상태 확인:
```bash
kubectl logs -n devops-keycloak -l app=keycloak | grep -i admin
```