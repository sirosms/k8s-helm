# Mattermost 설치

이 스크립트는 Kubernetes 클러스터에 Mattermost를 설치합니다.

## 사전 요구사항

1. **Kubernetes 클러스터**
   - kubectl 명령어 설정 완료
   - Helm 3.x 설치

2. **Storage Class**
   - `nfs-client-sc` Storage Class 설정 완료

3. **TLS 인증서**
   - `samsungena.io-tls` Secret이 default 네임스페이스에 존재
   - Reflector가 설치되어 있어야 자동으로 devops 네임스페이스로 복사됨

## 설치 순서

### 1. 이미지 로드

먼저 Mattermost 이미지를 로드합니다:

```bash
./02_load_images.sh
```

### 2. Mattermost 설치

설치 스크립트를 실행합니다:

```bash
./03_install_mattermost.sh
```

스크립트 실행 중 다음 정보를 입력해야 합니다:
- Mattermost 외부 URL (기본값: https://mattermost-dev.secl.samsung.co.kr)
- 관리자 이메일 (기본값: admin@samsung.co.kr)

## 설치 확인

설치 완료 후 다음 명령으로 상태를 확인할 수 있습니다:

```bash
kubectl get pods -n devops-mattermost
kubectl get svc -n devops-mattermost
kubectl get ingress -n devops-mattermost
```

## 접속 방법

### 1. Ingress를 통한 접속

브라우저에서 설정한 URL로 접속:
- https://mattermost-dev.secl.samsung.co.kr

### 2. Port Forward를 통한 접속

```bash
kubectl port-forward -n devops-mattermost svc/mattermost 8065:8065
```
브라우저에서 http://localhost:8065 접속

## 초기 설정

### 관리자 계정 생성

웹 브라우저에서 접속한 후 초기 관리자 계정을 생성합니다:
1. "Create a team" 선택
2. 팀 이름과 URL 입력
3. 관리자 계정 정보 입력

### 로그인 정보
- 사용자명: 설정 시 입력한 사용자명
- 비밀번호: 설정 시 입력한 비밀번호

## 구성 요소

- **네임스페이스**: devops-mattermost
- **구성 요소**:
  - Mattermost Team Edition
  - PostgreSQL Database
  - MinIO (File Storage)
- **이미지**:
  - mattermost/mattermost-team-edition:7.8.0
  - postgres:13-alpine
  - minio/minio:RELEASE.2023-04-07T05-28-58Z
- **포트**: 8065 (HTTP)

## 문제 해결

### PVC 생성 실패
Storage Class `gp2`가 설정되어 있는지 확인:
```bash
kubectl get storageclass
```

### TLS 인증서 문제
secl.samsung.co.kr-tls Secret이 존재하는지 확인:
```bash
kubectl get secret secl.samsung.co.kr-tls -n devops-mattermost
```

### Pod 시작 실패
리소스 부족 또는 PVC 마운트 문제일 수 있습니다:
```bash
kubectl describe pod -n devops-mattermost
kubectl logs -n devops-mattermost -l app=mattermost
```

### 데이터베이스 연결 문제
PostgreSQL 연결 상태 확인:
```bash
kubectl logs -n devops-mattermost -l app=postgresql
kubectl exec -it -n devops-mattermost <postgresql-pod-name> -- psql -U mattermost -d mattermost
```