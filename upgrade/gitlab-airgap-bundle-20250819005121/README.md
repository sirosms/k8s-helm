# GitLab 폐쇄망 설치 가이드

## 개요
이 번들은 GitLab Community Edition 15.8.0을 폐쇄망 환경에서 설치하기 위한 모든 구성 요소를 포함합니다.

## 포함된 구성 요소
- GitLab CE 15.8.0 Helm 차트
- 필요한 컨테이너 이미지들
- 오프라인 설치용 설정 파일 (gitlab.yaml 기반)
- 자동 설치 스크립트
- PVC 템플릿

## 사전 준비사항

### 1. 외부 PostgreSQL 데이터베이스 준비
GitLab이 사용할 PostgreSQL 데이터베이스를 준비해야 합니다:

```sql
-- PostgreSQL에 데이터베이스와 사용자 생성
CREATE DATABASE gitlab;
CREATE USER gitlab WITH PASSWORD 'your_password';
GRANT ALL PRIVILEGES ON DATABASE gitlab TO gitlab;
```

### 2. Persistent Volume 준비
GitLab은 다음 3개의 PVC를 필요로 합니다:

```bash
# PVC 생성
kubectl apply -f pvc/gitlab-pvc.yaml
```

### 3. 클러스터 환경
- Kubernetes 클러스터 (v1.19+)
- Helm 3.x
- kubectl 접근 권한

## 설치 방법

### 1단계: 번들 압축 해제
```bash
tar -xf gitlab-airgap-bundle-XXXXXXXX.tar
cd gitlab-airgap-bundle-XXXXXXXX/
```

### 2단계: 컨테이너 이미지 로드
내부 레지스트리에 이미지들을 로드합니다:

```bash
# 각 이미지를 내부 레지스트리에 로드
for image in images/*.tar; do
    docker load -i "$image"
done

# 내부 레지스트리에 태그 및 푸시
# (실제 레지스트리 주소로 변경 필요)
docker tag registry.gitlab.com/gitlab-org/build/cng/gitlab-webservice-ce:v15.8.0 registry.local:5000/gitlab-org/build/cng/gitlab-webservice-ce:v15.8.0
docker tag registry.gitlab.com/gitlab-org/gitlab-runner:alpine-v16.11.0 registry.local:5000/gitlab-org/gitlab-runner:alpine-v16.11.0
docker tag registry.gitlab.com/gitlab-org/build/cng/kubectl:1.24.7 registry.local:5000/gitlab-org/build/cng/kubectl:1.24.7
docker tag registry.gitlab.com/gitlab-org/cloud-native/mirror/images/busybox:latest registry.local:5000/gitlab-org/cloud-native/mirror/images/busybox:latest
docker tag docker.io/bitnami/redis:6.0.9-debian-10-r0 registry.local:5000/bitnami/redis:6.0.9-debian-10-r0
docker tag minio/minio:RELEASE.2017-12-28T01-21-00Z registry.local:5000/minio/minio:RELEASE.2017-12-28T01-21-00Z
docker tag minio/mc:RELEASE.2018-07-13T00-53-22Z registry.local:5000/minio/mc:RELEASE.2018-07-13T00-53-22Z

docker push registry.local:5000/gitlab-org/build/cng/gitlab-webservice-ce:v15.8.0
docker push registry.local:5000/gitlab-org/gitlab-runner:alpine-v16.11.0
docker push registry.local:5000/gitlab-org/build/cng/kubectl:1.24.7
docker push registry.local:5000/gitlab-org/cloud-native/mirror/images/busybox:latest
docker push registry.local:5000/bitnami/redis:6.0.9-debian-10-r0
docker push registry.local:5000/minio/minio:RELEASE.2017-12-28T01-21-00Z
docker push registry.local:5000/minio/mc:RELEASE.2018-07-13T00-53-22Z
```

### 3단계: 설정 파일 수정
`values/values-offline-example.yaml` 파일에서 내부 레지스트리 주소를 수정합니다:

```yaml
image:
  repository: registry.local:5000/gitlab/gitlab-webservice-ce  # 여기를 실제 레지스트리 주소로 변경
  tag: "15.8.0"
  pullPolicy: IfNotPresent

global:
  imageRegistry: "registry.local:5000"  # 여기를 실제 레지스트리 주소로 변경
```

### 4단계: PVC 생성
```bash
kubectl apply -f pvc/gitlab-pvc.yaml
```

### 5단계: 설치 실행
대화형 설치 스크립트를 실행합니다:

```bash
./install-gitlab.sh
```

스크립트 실행 시 다음 정보를 입력해야 합니다:
- PostgreSQL 호스트, 포트, 데이터베이스명, 사용자명, 패스워드
- GitLab 외부 URL

### 6단계: 접속 확인
```bash
# 포트 포워딩으로 접속 테스트
kubectl port-forward -n gitlab svc/gitlab 8443:443

# 브라우저에서 https://localhost:8443 접속
# 초기 로그인: root / Passw0rd!
```

## 수동 설치 방법
자동 스크립트 대신 수동으로 설치하려면:

```bash
# 네임스페이스 생성
kubectl create namespace gitlab

# PostgreSQL Secret 생성
kubectl create secret generic gitlab-postgres-secret \
  --from-literal=db-password="your_password" \
  --namespace gitlab

# 내부 레지스트리 인증 Secret 생성 (필요시)
kubectl create secret docker-registry registry-local-credential \
  --docker-server=registry.local:5000 \
  --docker-username=<username> \
  --docker-password=<password> \
  --namespace gitlab

# Helm 설치
helm upgrade --install gitlab ./charts/gitlab-9.2.1.tgz \
  --namespace gitlab \
  --values ./values/values-offline-example.yaml \
  --set env.open.EXTERNAL_URL="https://gitlab.example.com" \
  --set env.open.DB_HOST="postgres.example.com" \
  --set env.open.DB_PORT="5432" \
  --set env.open.DB_DATABASE="gitlab" \
  --set env.open.DB_USERNAME="gitlab" \
  --set env.secret.DB_PASSWORD="your_password" \
  --timeout 900s
```

## 주요 설정 사항

### GitLab 기본 설정
- **초기 root 패스워드**: `Passw0rd!`
- **시간대**: `Asia/Seoul`
- **외부 PostgreSQL 사용** (내장 PostgreSQL 비활성화)
- **내장 Redis 사용**
- **Container Registry 비활성화**

### 보안 설정
- 기본 그룹 생성 권한 비활성화
- 모니터링 도구 비활성화 (폐쇄망 환경 고려)
- OmniAuth 비활성화

### 스토리지
- `/var/opt/gitlab`: GitLab 데이터 (PVC: gitlab-opt)
- `/etc/gitlab`: GitLab 설정 (PVC: gitlab-etc)
- `/var/log/gitlab`: GitLab 로그 (PVC: gitlab-log)

## 트러블슈팅

### 1. Pod가 시작되지 않는 경우
```bash
kubectl describe pod -n gitlab
kubectl logs -n gitlab deployment/gitlab
```

### 2. 데이터베이스 연결 오류
- PostgreSQL 호스트, 포트, 자격 증명 확인
- 네트워크 연결성 확인
- 데이터베이스가 존재하는지 확인

### 3. 이미지 Pull 오류
- 내부 레지스트리 주소가 올바른지 확인
- 이미지가 올바르게 푸시되었는지 확인
- imagePullSecrets 설정 확인

### 4. PVC 관련 오류
- PVC가 올바르게 생성되었는지 확인
- StorageClass가 사용 가능한지 확인
- PV가 바인딩되었는지 확인

### 5. SSL/TLS 인증서 문제
- TLS Secret이 올바르게 생성되었는지 확인
- 인증서 파일 경로 확인
- Ingress 설정 확인

## 기본 운영 작업

### 백업
```bash
# GitLab 데이터 백업
kubectl exec -n gitlab deployment/gitlab -- gitlab-backup create

# PVC 백업 (볼륨 스냅샷 사용)
kubectl create volumesnapshot gitlab-opt-backup --source-name=gitlab-opt -n gitlab
```

### 업그레이드
```bash
# 새 버전의 차트로 업그레이드
helm upgrade gitlab ./charts/new-gitlab-version.tgz \
  --namespace gitlab \
  --values ./values/values-offline-example.yaml
```

## 지원
- GitLab 버전: 15.8.0 (Community Edition)
- Helm 차트 버전: 9.2.1
- 최소 Kubernetes 버전: 1.19+

## 주의사항
- 이 설정은 gitlab.yaml의 실제 운영 환경 설정을 기반으로 작성되었습니다
- 폐쇄망 환경에 맞게 일부 기능(모니터링, 레지스트리 등)을 비활성화했습니다
- 운영 환경에서는 리소스 제한, 보안 설정 등을 적절히 조정해주세요