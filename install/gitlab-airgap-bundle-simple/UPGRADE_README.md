# GitLab 업그레이드 가이드 (폐쇄망 환경)

## 현재 상황
- **현재 버전**: GitLab CE 15.8.0-ce.0
- **목표 버전**: GitLab CE 17.6.2-ce.0 (최신 안정화)
- **업그레이드 방식**: 단계적 업그레이드 (GitLab 공식 가이드 준수)

## 업그레이드 경로
GitLab 공식 업그레이드 경로에 따라 다음과 같이 단계적으로 진행:

1. **15.8.0** → **15.11.13** (15.x 마지막 마이너 버전)
2. **15.11.13** → **16.3.7** (16.x 첫 LTS 버전)
3. **16.3.7** → **16.7.8** (16.x 최신 마이너)
4. **16.7.8** → **17.3.7** (17.x LTS 버전)
5. **17.3.7** → **17.6.2** (최신 안정화 버전)

## 업그레이드 절차

### 1. 사전 준비
```bash
# 백업 실행 (필수!)
./backup-before-upgrade.sh
```

### 2. ECR에 업그레이드 이미지 푸시
```bash
# 인터넷 연결된 환경에서 실행
./push-upgrade-images.sh
```

### 3. 실제 업그레이드 실행
```bash
# 폐쇄망 환경에서 실행
./upgrade-gitlab.sh
```

## 스크립트 설명

### `backup-before-upgrade.sh`
- GitLab 설정 및 리소스 백업
- 데이터베이스 백업 가이드 제공
- PVC 백업 스크립트 생성
- 롤백 계획 문서 생성

### `push-upgrade-images.sh`
- 업그레이드에 필요한 모든 GitLab 이미지를 ECR에 푸시
- 인터넷 연결된 환경에서 실행 필요
- 각 버전별 이미지 다운로드 및 ECR 업로드

### `upgrade-gitlab.sh`
- 단계적 업그레이드 자동 실행
- 각 단계별 상태 확인 및 대기
- Health check 및 오류 처리
- 폐쇄망 환경에서 실행

## 주의사항

### ⚠️ 업그레이드 전 필수 작업
1. **데이터베이스 백업**: PostgreSQL 덤프 생성
2. **PVC 백업**: EBS 스냅샷 또는 데이터 복사
3. **설정 백업**: Helm values 및 Kubernetes 리소스
4. **점검 시간 확보**: 업그레이드는 2-4시간 소요 예상

### 🔧 업그레이드 중 고려사항
- 각 단계별로 2분씩 대기 시간 포함
- Pod Ready 상태까지 최대 20분 대기
- 데이터베이스 마이그레이션 자동 실행
- 업그레이드 실패 시 자동 중단

### 📋 업그레이드 후 확인사항
1. GitLab 웹 UI 접속 확인
2. 기존 프로젝트 및 사용자 데이터 확인
3. CI/CD 파이프라인 동작 확인
4. 통합 기능 (DB, 스토리지) 정상 작동 확인

## 롤백 절차
문제 발생 시 생성된 백업을 사용하여 롤백:

```bash
# 1. Helm 롤백
helm rollback gitlab -n devops

# 2. 데이터베이스 복원 (필요시)
psql -h gitlab-dev-postgres.c8thupqwxcj4.ap-northeast-2.rds.amazonaws.com \
     -U gitlab -d gitlabhq_production < backup-[timestamp]/gitlab-database-backup.sql

# 3. PVC 복원 (필요시)
# 방법 1: EBS 스냅샷에서 복원
aws ec2 describe-snapshots --owner-ids self --filters "Name=tag:Name,Values=gitlab-backup-*"
aws ec2 create-volume --snapshot-id snap-xxxxxxxxx --size 50 --volume-type gp2
# 새 볼륨을 PVC에 연결

# 방법 2: 백업된 데이터에서 복원
kubectl run restore-opt --image=866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/ubuntu:20.04 \
  --restart=Never --rm -i -n devops \
  --overrides='{"spec":{"volumes":[{"name":"backup","persistentVolumeClaim":{"claimName":"gitlab-backup-pvc"}},{"name":"target","persistentVolumeClaim":{"claimName":"gitlab-opt-dev"}}],"containers":[{"name":"restore","image":"866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/ubuntu:20.04","command":["bash","-c","cd /target && tar xzf /backup/gitlab-opt-backup.tar.gz"],"volumeMounts":[{"name":"backup","mountPath":"/backup"},{"name":"target","mountPath":"/target"}]}]}}' \
  --wait
```

## 업그레이드 소요 시간 예상
- **전체 소요 시간**: 2-4시간
- **각 단계별**: 20-40분 (버전별 차이)
- **데이터베이스 마이그레이션**: 데이터 크기에 따라 가변

## 문제 해결

### 이미지 Pull 실패
```bash
# ECR 로그인 재시도
aws ecr get-login-password --region ap-northeast-2 | \
docker login --username AWS --password-stdin 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com
```

### Pod 시작 실패
```bash
# 로그 확인
kubectl logs -n devops -l app=gitlab --tail=100

# 리소스 상태 확인
kubectl describe pod -n devops -l app=gitlab
```

### 데이터베이스 연결 문제
1. RDS 보안 그룹 설정 확인
2. 데이터베이스 자격증명 확인
3. 네트워크 연결 상태 점검

### PVC 백업 및 복구 상세 가이드

#### PVC 백업 생성
```bash
# 1. 백업용 PVC 생성
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: gitlab-backup-pvc
  namespace: devops
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: gp2
  resources:
    requests:
      storage: 100Gi
EOF

# 2. PVC 데이터 백업 실행
./backup-before-upgrade.sh  # 자동으로 PVC 백업 수행
```

#### PVC 복구 방법

**방법 1: EBS 스냅샷을 사용한 복구 (권장)**
```bash
# 1. 현재 EBS 볼륨 스냅샷 생성
VOLUME_ID=$(kubectl get pv $(kubectl get pvc gitlab-opt-dev -n devops -o jsonpath='{.spec.volumeName}') -o jsonpath='{.spec.awsElasticBlockStore.volumeID}' | cut -d'/' -f4)
aws ec2 create-snapshot --volume-id $VOLUME_ID --description "GitLab upgrade backup $(date)"

# 2. 복구시 스냅샷에서 볼륨 생성
aws ec2 create-volume --snapshot-id snap-xxxxxxxxx --size 50 --volume-type gp2 --availability-zone ap-northeast-2a

# 3. PVC 재생성 (필요시)
kubectl delete pvc gitlab-opt-dev -n devops
kubectl apply -f pvc/gitlab-opt-dev.yaml
```

**방법 2: 백업 데이터를 사용한 복구**
```bash
# GitLab opt 데이터 복구
kubectl run restore-opt --image=866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/ubuntu:20.04 \
  --restart=Never --rm -n devops \
  --overrides='{"spec":{"volumes":[{"name":"backup","persistentVolumeClaim":{"claimName":"gitlab-backup-pvc"}},{"name":"target","persistentVolumeClaim":{"claimName":"gitlab-opt-dev"}}],"containers":[{"name":"restore","image":"866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/ubuntu:20.04","command":["bash","-c","cd /target && rm -rf * && tar xzf /backup/gitlab-opt-backup.tar.gz && echo Restore completed"],"volumeMounts":[{"name":"backup","mountPath":"/backup"},{"name":"target","mountPath":"/target"}]}]}}' \
  --wait

# GitLab etc 데이터 복구  
kubectl run restore-etc --image=866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/ubuntu:20.04 \
  --restart=Never --rm -n devops \
  --overrides='{"spec":{"volumes":[{"name":"backup","persistentVolumeClaim":{"claimName":"gitlab-backup-pvc"}},{"name":"target","persistentVolumeClaim":{"claimName":"gitlab-etc-dev"}}],"containers":[{"name":"restore","image":"866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/ubuntu:20.04","command":["bash","-c","cd /target && rm -rf * && tar xzf /backup/gitlab-etc-backup.tar.gz && echo Restore completed"],"volumeMounts":[{"name":"backup","mountPath":"/backup"},{"name":"target","mountPath":"/target"}]}]}}' \
  --wait

# GitLab log 데이터 복구
kubectl run restore-log --image=866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/ubuntu:20.04 \
  --restart=Never --rm -n devops \
  --overrides='{"spec":{"volumes":[{"name":"backup","persistentVolumeClaim":{"claimName":"gitlab-backup-pvc"}},{"name":"target","persistentVolumeClaim":{"claimName":"gitlab-log-dev"}}],"containers":[{"name":"restore","image":"866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/ubuntu:20.04","command":["bash","-c","cd /target && rm -rf * && tar xzf /backup/gitlab-log-backup.tar.gz && echo Restore completed"],"volumeMounts":[{"name":"backup","mountPath":"/backup"},{"name":"target","mountPath":"/target"}]}]}}' \
  --wait
```

#### 복구 후 검증
```bash
# PVC 상태 확인
kubectl get pvc -n devops

# GitLab Pod 재시작
kubectl rollout restart deployment gitlab -n devops

# GitLab 서비스 상태 확인
kubectl get pods -n devops -l app=gitlab
kubectl logs -n devops -l app=gitlab --tail=50
```

## 지원
- 업그레이드 과정에서 문제 발생 시 백업 파일 보관
- 각 단계별 로그 기록 유지
- 롤백 계획 문서 참조: `backup-[timestamp]/rollback-plan.md`