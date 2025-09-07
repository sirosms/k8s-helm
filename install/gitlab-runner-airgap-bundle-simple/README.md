# GitLab Runner 17.6.0 폐쇄망 설치 번들

GitLab 17.6.2와 호환되는 GitLab Runner 17.6.0을 폐쇄망 환경에서 설치하기 위한 번들입니다.

## 📋 구성 요소

```
gitlab-runner-airgap-bundle-simple/
├── charts/                     # Helm 차트
│   └── gitlab-runner/          # GitLab Runner 차트 (v0.71.0)
├── images/                     # Docker 이미지 (tar 파일)
├── values/                     # Helm values 파일
│   └── gitlab-runner.yaml      # GitLab Runner 설정
├── download-images.sh          # 이미지 다운로드 스크립트
├── load-images.sh             # 이미지 로드 및 ECR 업로드 스크립트
├── install-gitlab-runner.sh   # GitLab Runner 설치 스크립트
├── uninstall-gitlab-runner.sh # GitLab Runner 제거 스크립트
└── README.md                  # 이 파일
```

## 🚀 설치 순서

### 1. 사전 준비사항

- Kubernetes 클러스터 (v1.20+)
- Helm 3.x
- AWS CLI (ECR 사용시)
- kubectl
- Docker (이미지 다운로드시)

### 2. 이미지 다운로드 (인터넷 연결 환경)

```bash
# 실행 권한 부여
chmod +x *.sh

# 이미지 다운로드 (AMD64 아키텍처)
./download-images.sh
```

다운로드되는 이미지:
- `gitlab/gitlab-runner:alpine-v17.6.0` - GitLab Runner 메인 이미지
- `gitlab/gitlab-runner-helper:x86_64-v17.6.0` - GitLab Runner Helper 이미지
- `ubuntu:20.04` - 기본 빌드 이미지

### 3. 이미지 로드 및 ECR 업로드 (폐쇄망 환경)

```bash
# ECR 로그인 및 이미지 업로드
./load-images.sh
```

### 4. Runner 등록 토큰 설정

GitLab에서 Runner 등록 토큰을 획득:

1. GitLab 웹 UI 접속: `https://gitlab-dev.samsungena.io`
2. **Admin Area > Runners** (관리자) 또는 **프로젝트 Settings > CI/CD > Runners**
3. **Register a runner** 클릭하여 등록 토큰 획득
4. `values/gitlab-runner.yaml` 파일 수정:

```yaml
runnerRegistrationToken: "여기에_토큰_입력"
```

### 5. ECR 인증 정보 생성

```bash
kubectl create secret docker-registry registry-local-credential \
  --docker-server=866376286331.dkr.ecr.ap-northeast-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region ap-northeast-2) \
  --namespace=devops
```

### 6. GitLab Runner 설치

```bash
./install-gitlab-runner.sh
```

## 🔧 설정 사용자화

### Runner 설정 수정

`values/gitlab-runner.yaml` 파일에서 다음 설정을 수정할 수 있습니다:

```yaml
# GitLab URL
gitlabUrl: https://gitlab-dev.samsungena.io/

# Runner 등록 토큰
runnerRegistrationToken: "your-token-here"

# 리소스 제한
resources:
  limits:
    memory: 256Mi
    cpu: 200m
  requests:
    memory: 128Mi
    cpu: 100m

# 빌드 환경 설정
runners:
  config: |
    [[runners]]
      [runners.kubernetes]
        # 기본 이미지
        image = "866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/ubuntu:20.04"
        
        # 리소스 제한
        cpu_limit = "1"
        memory_limit = "2Gi"
        cpu_request = "500m"
        memory_request = "1Gi"
```

### 추가 빌드 이미지

특정 언어나 도구가 필요한 경우 추가 이미지를 다운로드하고 ECR에 업로드:

```bash
# 예: Node.js 이미지
docker pull --platform linux/amd64 node:18
docker tag node:18 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/node:18
docker push 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/node:18
```

## 📊 상태 확인

### Runner 상태 확인

```bash
# Pod 상태
kubectl get pods -n devops -l app=gitlab-runner

# Runner 로그
kubectl logs -n devops -l app=gitlab-runner

# Helm 상태
helm status gitlab-runner -n devops
```

### GitLab UI에서 확인

1. GitLab 웹 UI 접속
2. **Admin Area > Runners** 또는 **프로젝트 Settings > CI/CD > Runners**
3. 등록된 Runner 확인 (녹색 불 표시)

## 🧪 테스트

프로젝트에 `.gitlab-ci.yml` 파일 생성:

```yaml
stages:
  - test

test-job:
  stage: test
  image: 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/ubuntu:20.04
  script:
    - echo "Hello from GitLab Runner!"
    - uname -a
    - cat /etc/os-release
```

## 🗑️ 제거

```bash
./uninstall-gitlab-runner.sh
```

## 📝 문제 해결

### 일반적인 문제들

1. **이미지를 찾을 수 없음**
   ```
   Error: ErrImagePull
   ```
   - ECR 인증 정보 확인
   - 이미지가 ECR에 정상 업로드되었는지 확인

2. **Runner가 등록되지 않음**
   ```
   ERROR: Registering runner... failed
   ```
   - `runnerRegistrationToken` 값 확인
   - GitLab URL 접근 가능성 확인
   - 네트워크 정책 확인

3. **권한 문제**
   ```
   Error: pods is forbidden
   ```
   - ServiceAccount 및 RBAC 설정 확인
   - 네임스페이스 권한 확인

### 로그 확인

```bash
# Runner 상세 로그
kubectl logs -n devops -l app=gitlab-runner -f

# Pod 상세 정보
kubectl describe pods -n devops -l app=gitlab-runner

# Events 확인
kubectl get events -n devops --sort-by='.lastTimestamp'
```

## 🔗 관련 문서

- [GitLab Runner Documentation](https://docs.gitlab.com/runner/)
- [GitLab Runner Helm Chart](https://docs.gitlab.com/runner/install/kubernetes.html)
- [GitLab CI/CD Configuration](https://docs.gitlab.com/ee/ci/)

## 📋 버전 정보

- **GitLab Runner**: 17.6.0
- **Helm Chart**: 0.71.0
- **호환 GitLab**: 17.6.x
- **Kubernetes**: 1.20+