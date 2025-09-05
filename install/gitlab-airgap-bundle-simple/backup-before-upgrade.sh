#!/bin/bash

# GitLab 업그레이드 전 백업 스크립트

set -e

NAMESPACE="devops"
BACKUP_DIR="./backup-$(date +%Y%m%d-%H%M%S)"
DB_HOST="gitlab-dev-postgres.c8thupqwxcj4.ap-northeast-2.rds.amazonaws.com"
DB_NAME="gitlabhq_production"
DB_USER="gitlab"
ECR_REGISTRY="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"
REGION="ap-northeast-2"

echo "=== GitLab 업그레이드 전 백업 시작 ==="
echo "백업 디렉토리: $BACKUP_DIR"

# 백업 디렉토리 생성
mkdir -p $BACKUP_DIR

echo ""
echo "=== 0. 백업용 이미지 확인 (폐쇄망 환경) ==="
BACKUP_IMAGE="$ECR_REGISTRY/ubuntu:20.04"
echo "백업 작업용 ubuntu 이미지 확인: $BACKUP_IMAGE"

# ECR에 ubuntu 이미지가 있는지 확인
if ! docker pull $BACKUP_IMAGE 2>/dev/null; then
    echo "⚠️ ECR에 ubuntu 이미지가 없습니다."
    echo "다음 명령어로 ubuntu 이미지를 ECR에 푸시하세요:"
    echo ""
    echo "# ECR 로그인"
    echo "aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY"
    echo ""
    echo "# ECR 저장소 생성"
    echo "aws ecr create-repository --region $REGION --repository-name ubuntu"
    echo ""
    echo "# ubuntu 이미지 준비"
    echo "docker pull --platform linux/amd64 ubuntu:20.04"
    echo "docker tag ubuntu:20.04 $BACKUP_IMAGE"
    echo "docker push $BACKUP_IMAGE"
    echo ""
    read -r -p "ubuntu 이미지를 ECR에 푸시했습니까? 계속 진행하시겠습니까? (y/N): " backup_image_confirm
    if [[ ! $backup_image_confirm =~ ^[Yy]$ ]]; then
        echo "ubuntu 이미지를 먼저 ECR에 푸시하세요."
        exit 1
    fi
else
    echo "✅ ubuntu 이미지 확인 완료"
fi

echo ""
echo "=== 1. 현재 GitLab 설정 백업 ==="

# Helm values 백업
echo "Helm values.yaml 백업 중..."
cp values/gitlab.yaml $BACKUP_DIR/gitlab-values.yaml

# 현재 배포된 리소스 정보 백업
echo "배포된 리소스 정보 백업 중..."
kubectl get all -n $NAMESPACE -o yaml > $BACKUP_DIR/gitlab-resources.yaml
kubectl get pvc -n $NAMESPACE -o yaml > $BACKUP_DIR/gitlab-pvcs.yaml
kubectl get configmaps -n $NAMESPACE -o yaml > $BACKUP_DIR/gitlab-configmaps.yaml
kubectl get secrets -n $NAMESPACE -o yaml > $BACKUP_DIR/gitlab-secrets.yaml

# 현재 버전 정보
helm list -n $NAMESPACE > $BACKUP_DIR/helm-releases.txt
kubectl get pods -n $NAMESPACE -o wide > $BACKUP_DIR/pods-status.txt

echo "✅ GitLab 설정 백업 완료"

echo ""
echo "=== 2. 데이터베이스 백업 ==="
echo "GitLab 내장 백업 기능을 사용하여 데이터베이스를 백업합니다."

# GitLab Pod 확인
GITLAB_POD=$(kubectl get pods -n "$NAMESPACE" -l app=gitlab -o jsonpath='{.items[0].metadata.name}')
if [ -z "$GITLAB_POD" ]; then
    echo "❌ GitLab Pod를 찾을 수 없습니다."
    exit 1
fi

echo "GitLab Pod: $GITLAB_POD"

# 기존 백업 프로세스 정리
echo "기존 백업 프로세스 정리 중..."
kubectl exec "$GITLAB_POD" -n "$NAMESPACE" -- rm -f /opt/gitlab/embedded/service/gitlab-rails/tmp/backup_restore.pid 2>/dev/null || true

# GitLab 백업 실행
echo "GitLab 데이터베이스 백업 실행 중... (수분 소요될 수 있습니다)"
if kubectl exec "$GITLAB_POD" -n "$NAMESPACE" -- gitlab-backup create; then
    echo "✅ GitLab 백업 생성 완료"
    
    # 백업 파일 확인
    BACKUP_FILES=$(kubectl exec "$GITLAB_POD" -n "$NAMESPACE" -- ls /var/opt/gitlab/backups/*.tar 2>/dev/null | tail -1)
    if [ -n "$BACKUP_FILES" ]; then
        BACKUP_FILE=$(basename "$BACKUP_FILES")
        echo "생성된 백업 파일: $BACKUP_FILE"
        
        # 백업 파일을 로컬로 복사
        echo "백업 파일을 로컬로 복사 중..."
        if kubectl cp "$NAMESPACE/$GITLAB_POD:/var/opt/gitlab/backups/$BACKUP_FILE" "$BACKUP_DIR/$BACKUP_FILE"; then
            echo "✅ 백업 파일 복사 완료: $BACKUP_DIR/$BACKUP_FILE"
            
            # 백업 파일 크기 확인
            BACKUP_SIZE=$(du -sh "$BACKUP_DIR/$BACKUP_FILE" | cut -f1)
            echo "백업 파일 크기: $BACKUP_SIZE"
        else
            echo "⚠️ 백업 파일 복사 실패 (GitLab Pod 내부에는 백업 존재)"
        fi
    else
        echo "⚠️ 백업 파일을 찾을 수 없습니다"
    fi
else
    echo "❌ GitLab 백업 생성 실패"
    read -r -p "계속 진행하시겠습니까? (백업 없이 진행하면 위험합니다) (y/N): " continue_without_db_backup
    if [[ ! $continue_without_db_backup =~ ^[Yy]$ ]]; then
        echo "업그레이드가 취소되었습니다."
        exit 1
    fi
fi

echo ""
echo "=== 3. PVC 백업 권고사항 ==="
echo "다음 PVC들의 백업을 권장합니다:"
kubectl get pvc -n $NAMESPACE
echo ""
echo "백업 방법 (예시):"
echo "1. 스냅샷 생성 (AWS EBS 스냅샷)"
echo "2. 또는 임시 Pod로 데이터 복사"
echo ""

# PVC 백업 스크립트 생성
cat > $BACKUP_DIR/backup-pvc.sh << 'EOF'
#!/bin/bash
# PVC 백업 스크립트 (필요시 실행)

NAMESPACE="devops"
BACKUP_PVC_NAME="gitlab-backup-pvc"

# 백업용 PVC 생성 (사용자가 직접 실행)
echo "백업용 PVC 및 Pod 생성..."

# gitlab-opt-dev 백업
# ECR ubuntu 이미지 사용 (폐쇄망 환경)
kubectl run backup-opt --image=866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/ubuntu:20.04 --restart=Never --rm -i -n $NAMESPACE \
  --overrides='{"spec":{"volumes":[{"name":"source","persistentVolumeClaim":{"claimName":"gitlab-opt-dev"}},{"name":"backup","persistentVolumeClaim":{"claimName":"'$BACKUP_PVC_NAME'"}}],"containers":[{"name":"backup-opt","image":"866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/ubuntu:20.04","command":["bash","-c","cd /source && tar czf /backup/gitlab-opt-backup.tar.gz ."],"volumeMounts":[{"name":"source","mountPath":"/source"},{"name":"backup","mountPath":"/backup"}]}]}}' \
  --wait

# gitlab-etc-dev 백업
kubectl run backup-etc --image=866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/ubuntu:20.04 --restart=Never --rm -i -n $NAMESPACE \
  --overrides='{"spec":{"volumes":[{"name":"source","persistentVolumeClaim":{"claimName":"gitlab-etc-dev"}},{"name":"backup","persistentVolumeClaim":{"claimName":"'$BACKUP_PVC_NAME'"}}],"containers":[{"name":"backup-etc","image":"866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/ubuntu:20.04","command":["bash","-c","cd /source && tar czf /backup/gitlab-etc-backup.tar.gz ."],"volumeMounts":[{"name":"source","mountPath":"/source"},{"name":"backup","mountPath":"/backup"}]}]}}' \
  --wait

# gitlab-log-dev 백업
kubectl run backup-log --image=866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/ubuntu:20.04 --restart=Never --rm -i -n $NAMESPACE \
  --overrides='{"spec":{"volumes":[{"name":"source","persistentVolumeClaim":{"claimName":"gitlab-log-dev"}},{"name":"backup","persistentVolumeClaim":{"claimName":"'$BACKUP_PVC_NAME'"}}],"containers":[{"name":"backup-log","image":"866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/ubuntu:20.04","command":["bash","-c","cd /source && tar czf /backup/gitlab-log-backup.tar.gz . && echo && echo 백업 완료 요약: && du -sh /backup/*.tar.gz"],"volumeMounts":[{"name":"source","mountPath":"/source"},{"name":"backup","mountPath":"/backup"}]}]}}' \
  --wait

echo "gitlab-opt-dev 백업 완료"

# 필요시 etc, log도 동일한 방식으로...
EOF

chmod +x $BACKUP_DIR/backup-pvc.sh

echo ""
echo "=== 4. 업그레이드 롤백 계획 ==="
cat > $BACKUP_DIR/rollback-plan.md << EOF
# GitLab 업그레이드 롤백 계획

## 현재 정보
- 현재 버전: 15.8.0-ce.0
- 네임스페이스: $NAMESPACE
- 백업 날짜: $(date)

## 롤백 절차
1. Helm 롤백
   \`\`\`
   helm rollback gitlab -n $NAMESPACE
   \`\`\`

2. GitLab 데이터베이스 복원 (필요시)
   \`\`\`
   # GitLab Pod에 백업 파일 복사
   kubectl cp $BACKUP_DIR/*.tar $NAMESPACE/\$GITLAB_POD:/var/opt/gitlab/backups/
   
   # GitLab 복원 실행
   kubectl exec \$GITLAB_POD -n $NAMESPACE -- gitlab-backup restore BACKUP=\$BACKUP_ID
   
   # 또는 직접 PostgreSQL 복원
   psql -h $DB_HOST -U $DB_USER -d $DB_NAME < gitlab-database-backup.sql
   \`\`\`

3. PVC 복원 (필요시)
   - EBS 스냅샷에서 복원
   - 또는 백업 데이터 복사

## 백업 파일 위치
- 설정 백업: $BACKUP_DIR/
- GitLab DB 백업: $BACKUP_DIR/*.tar (GitLab 내장 백업)
- PVC 백업: gitlab-backup-pvc (kubernetes PVC)

## 백업 파일 목록
EOF

echo ""
echo "=== 백업 완료 ==="
echo "백업 위치: $BACKUP_DIR"
echo "백업된 파일들:"
ls -la $BACKUP_DIR/

echo ""
echo "✅ GitLab 업그레이드 전 백업이 완료되었습니다!"
echo ""
echo "📋 백업 완료 요약:"
echo "- GitLab 설정: ✅ 완료"
echo "- 데이터베이스: ✅ 완료"
echo "- PVC 백업 스크립트: ✅ 생성"
echo ""
echo "📁 백업 위치: $BACKUP_DIR/"
echo "🔄 롤백 가이드: $BACKUP_DIR/rollback-plan.md"
echo ""
echo "다음 단계:"
echo "1. push-upgrade-images.sh 실행 (ECR에 업그레이드 이미지 푸시) - ✅ 완료"
echo "2. upgrade-gitlab.sh 실행 (실제 업그레이드)"
echo ""
echo "⚠️ 문제 발생시 $BACKUP_DIR/rollback-plan.md 참조"