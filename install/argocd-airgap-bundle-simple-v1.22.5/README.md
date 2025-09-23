# ArgoCD Airgap Bundle Simple

ArgoCD v3.1.3 (Chart v8.3.4) 폐쇄망 설치를 위한 번들입니다.

## 📁 구조

```
argocd-airgap-bundle-simple/
├── charts/           # ArgoCD Helm 차트
├── images/          # Docker 이미지 tar 파일들
├── values/          # Helm values 파일들
├── ssl-certs/       # SSL 인증서들 (필요시)
├── download-images.sh    # 이미지 다운로드 스크립트
├── load-images.sh       # 이미지 로드 스크립트  
├── push-to-ecr.sh       # ECR 푸시 스크립트
├── install-argocd.sh    # ArgoCD 설치 스크립트
└── README.md
```

## 🚀 사용법

### 1. 이미지 다운로드 (인터넷 연결 환경)

```bash
chmod +x *.sh
./download-images.sh
```

### 2. 폐쇄망으로 파일 전송

전체 폴더를 폐쇄망 환경으로 복사합니다.

### 3. 이미지 로드 (폐쇄망 환경)

```bash
./load-images.sh
```

### 4. ECR에 푸시 (선택사항)

```bash
./push-to-ecr.sh
```

### 5. ArgoCD 설치

```bash
./install-argocd.sh
```

## 📦 포함된 이미지들

- `quay.io/argoproj/argocd:v3.1.3` - ArgoCD 메인 이미지
- `ecr-public.aws.com/docker/library/redis:7.2.8-alpine` - Redis
- `ghcr.io/dexidp/dex:v2.44.0` - Dex (OIDC)

## 🔧 설정

### 기본 설정
- **네임스페이스**: `devops-argocd`
- **릴리즈명**: `argocd`
- **차트 버전**: `8.3.4`
- **애플리케이션 버전**: `v3.1.3`

### 접속 정보
```bash
# 관리자 비밀번호 확인
kubectl get secret argocd-initial-admin-secret -n devops-argocd -o jsonpath='{.data.password}' | base64 -d

# 포트 포워딩
kubectl port-forward svc/argocd-server -n devops-argocd 8080:80

# 웹 UI 접속
# http://localhost:8080
# Username: admin
```

## 🛠️ 커스터마이징

`values/argocd.yaml` 파일을 수정하여 설정을 변경할 수 있습니다.

주요 설정 항목:
- Ingress 설정
- TLS/SSL 설정
- 리소스 제한
- HA 구성

## 📋 요구사항

- Kubernetes 1.20+
- Helm 3.0+
- Docker (이미지 작업용)
- AWS CLI (ECR 사용시)

## 🔍 트러블슈팅

### 이미지 Pull 오류
```bash
kubectl get pods -n devops-argocd
kubectl describe pod <pod-name> -n devops-argocd
```

### 서비스 상태 확인
```bash
kubectl get all -n devops-argocd
```

### 로그 확인
```bash
kubectl logs -f deployment/argocd-server -n devops-argocd
```