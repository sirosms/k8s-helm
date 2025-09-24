# SonarQube 설치

이 스크립트는 Kubernetes 클러스터에 SonarQube를 설치합니다.

## 사전 요구사항

1. **Kubernetes 클러스터**
   - kubectl 명령어 설정 완료
   - Helm 3.x 설치

2. **Storage Class**
   - `gp2` Storage Class 설정 완료

3. **TLS 인증서**
   - `secl.samsung.co.kr-tls` Secret이 devops-sonarqube 네임스페이스에 존재

## 설치 순서

### 1. 이미지 로드

먼저 SonarQube 이미지를 로드합니다:

```bash
./02_load_images.sh
```

### 2. SonarQube 설치

설치 스크립트를 실행합니다:

```bash
./03_install_sonarqube.sh
```

스크립트 실행 중 다음 정보를 입력해야 합니다:
- SonarQube 외부 URL (기본값: https://sonarqube-dev.secl.samsung.co.kr)
- 관리자 사용자명 (기본값: admin)
- 관리자 비밀번호

## 설치 확인

설치 완료 후 다음 명령으로 상태를 확인할 수 있습니다:

```bash
kubectl get pods -n devops-sonarqube
kubectl get svc -n devops-sonarqube
kubectl get ingress -n devops-sonarqube
```

## 접속 방법

### 1. Ingress를 통한 접속

브라우저에서 설정한 URL로 접속:
- https://sonarqube-dev.secl.samsung.co.kr

### 2. Port Forward를 통한 접속

```bash
kubectl port-forward -n devops-sonarqube svc/sonarqube 9000:9000
```
브라우저에서 http://localhost:9000 접속

## 초기 설정

### 관리자 로그인

기본 관리자 계정으로 로그인:
- 사용자명: admin
- 비밀번호: admin

**중요**: 첫 로그인 후 반드시 비밀번호를 변경해야 합니다.

### 관리자 비밀번호 확인 (설치 스크립트에서 설정한 경우)

```bash
kubectl get secret sonarqube-admin -n devops-sonarqube -o jsonpath='{.data.admin-password}' | base64 -d
```

## 구성 요소

- **네임스페이스**: devops-sonarqube
- **구성 요소**:
  - SonarQube Server
  - PostgreSQL Database
- **이미지**:
  - sonarqube:10.4.1-community
  - postgres:13-alpine
- **포트**: 9000 (HTTP)
- **PVC**:
  - sonarqube-data (20Gi) - SonarQube 데이터 저장
  - postgresql-data (10Gi) - PostgreSQL 데이터 저장

## 문제 해결

### PVC 생성 실패
Storage Class `gp2`가 설정되어 있는지 확인:
```bash
kubectl get storageclass
```

### TLS 인증서 문제
secl.samsung.co.kr-tls Secret이 존재하는지 확인:
```bash
kubectl get secret secl.samsung.co.kr-tls -n devops-sonarqube
```

### Pod 시작 실패
리소스 부족 또는 PVC 마운트 문제일 수 있습니다:
```bash
kubectl describe pod -n devops-sonarqube
kubectl logs -n devops-sonarqube -l app=sonarqube
```

### 데이터베이스 연결 문제
PostgreSQL 연결 상태 확인:
```bash
kubectl logs -n devops-sonarqube -l app=postgresql
kubectl exec -it -n devops-sonarqube <postgresql-pod-name> -- psql -U sonarqube -d sonarqube
```

### SonarQube 시작 시간
SonarQube는 시작하는데 시간이 걸릴 수 있습니다 (5-10분):
```bash
kubectl logs -f -n devops-sonarqube -l app=sonarqube
```

### 메모리 부족 문제
SonarQube는 최소 2GB RAM이 필요합니다:
```bash
kubectl top pods -n devops-sonarqube
```