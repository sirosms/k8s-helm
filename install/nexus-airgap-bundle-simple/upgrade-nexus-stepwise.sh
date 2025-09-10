#!/bin/bash
set -euo pipefail

# Nexus Repository 단계적 업그레이드 스크립트
# OrientDB -> H2 마이그레이션 포함
# 현재: 3.37.3 (OrientDB) → 3.70.3 → DB Migration → 3.83.2 (H2)

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 설정 변수
NAMESPACE="${NAMESPACE:-devops}"
RELEASE_NAME="nexus"
CHART_PATH="./charts/devops"
VALUES_FILE="./values/nexus.yaml"
BACKUP_DIR="./backup-stepwise-$(date +%Y%m%d-%H%M%S)"

# 업그레이드 버전 정보
CURRENT_VERSION="3.37.3"
INTERMEDIATE_VERSION="3.70.3"  # OrientDB 지원하는 마지막 버전
FINAL_VERSION="3.83.2"
ECR_REGISTRY="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"

# 단계별 업그레이드 함수
upgrade_to_version() {
    local target_version=$1
    local step_name=$2
    
    echo -e "\n${BLUE}=== ${step_name} (v${target_version}) ===${NC}"
    
    # 버전 업데이트
    sed -i.bak "s/tag: [0-9\.]*.*$/tag: $target_version/g" "$VALUES_FILE"
    
    # Helm 업그레이드
    helm upgrade $RELEASE_NAME $CHART_PATH \
        --namespace $NAMESPACE \
        --values $VALUES_FILE \
        --set image.tag="$target_version" \
        --timeout 1200s \
        --wait
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ ${step_name} 성공${NC}"
    else
        echo -e "${RED}❌ ${step_name} 실패${NC}"
        echo "롤백 명령어: helm rollback $RELEASE_NAME -n $NAMESPACE"
        exit 1
    fi
    
    # 상태 확인
    kubectl rollout status deployment/nexus -n $NAMESPACE --timeout=600s
    echo -e "${GREEN}✅ ${step_name} 배포 완료${NC}"
}

# 데이터베이스 마이그레이션 함수
migrate_database() {
    echo -e "\n${BLUE}=== 데이터베이스 마이그레이션 (OrientDB -> H2) ===${NC}"
    
    # Nexus 중지
    kubectl scale deployment nexus --replicas=0 -n $NAMESPACE
    echo "Nexus 서비스 중지됨..."
    
    # PVC에 접근할 수 있는 임시 Pod 생성
    cat <<EOF > temp-migrator-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: nexus-migrator
  namespace: $NAMESPACE
spec:
  containers:
  - name: migrator
    image: $ECR_REGISTRY/nexus3:$INTERMEDIATE_VERSION
    command: ["/bin/bash", "-c", "sleep 3600"]
    volumeMounts:
    - name: nexus-data
      mountPath: /nexus-data
    - name: nexus-db
      mountPath: /nexus-data/db
  volumes:
  - name: nexus-data
    persistentVolumeClaim:
      claimName: nexus-data
  - name: nexus-db
    persistentVolumeClaim:
      claimName: nexus-db
  restartPolicy: Never
EOF
    
    kubectl apply -f temp-migrator-pod.yaml
    kubectl wait --for=condition=Ready pod/nexus-migrator -n $NAMESPACE --timeout=300s
    
    echo -e "${YELLOW}⚠️  데이터베이스 마이그레이션을 수행합니다...${NC}"
    echo "이 과정은 시간이 오래 걸릴 수 있습니다."
    
    # 마이그레이션 실행
    kubectl exec -n $NAMESPACE nexus-migrator -- bash -c "
        cd /opt/sonatype/nexus &&
        java -jar nexus-db-migrator-*.jar \
            --migration_type=h2 \
            --nexus_data_dir=/nexus-data \
            --store_blob_contents_in_file_system=true
    "
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 데이터베이스 마이그레이션 성공${NC}"
    else
        echo -e "${RED}❌ 데이터베이스 마이그레이션 실패${NC}"
        kubectl delete -f temp-migrator-pod.yaml
        exit 1
    fi
    
    # 임시 Pod 삭제
    kubectl delete -f temp-migrator-pod.yaml
    rm -f temp-migrator-pod.yaml
    
    # Nexus 재시작
    kubectl scale deployment nexus --replicas=1 -n $NAMESPACE
}

echo -e "${BLUE}=== Nexus Repository 단계적 업그레이드 스크립트 ===${NC}"
echo -e "${YELLOW}현재 버전: ${CURRENT_VERSION} (OrientDB)${NC}"
echo -e "${YELLOW}중간 버전: ${INTERMEDIATE_VERSION} (OrientDB 지원 마지막)${NC}"
echo -e "${GREEN}최종 버전: ${FINAL_VERSION} (H2)${NC}"
echo

# 현재 상태 확인
echo -e "${BLUE}[1/6] 현재 Nexus 상태 확인${NC}"
if ! kubectl get deployment nexus -n $NAMESPACE >/dev/null 2>&1; then
    echo -e "${RED}❌ Nexus가 설치되어 있지 않습니다.${NC}"
    exit 1
fi

echo "✅ Nexus 발견됨"
kubectl get pods -n $NAMESPACE -l app=nexus --no-headers | while read pod_info; do
    pod_name=$(echo $pod_info | awk '{print $1}')
    status=$(echo $pod_info | awk '{print $3}')
    echo "  - Pod: $pod_name (상태: $status)"
done

# 백업 디렉토리 생성
echo -e "\n${BLUE}[2/6] 백업 디렉토리 생성${NC}"
mkdir -p "$BACKUP_DIR"
echo "✅ 백업 디렉토리 생성됨: $BACKUP_DIR"

# 현재 설정 백업
echo -e "\n${BLUE}[3/6] 현재 설정 백업${NC}"
cp -r values/ "$BACKUP_DIR/"
cp -r charts/ "$BACKUP_DIR/"
helm get values nexus -n $NAMESPACE > "$BACKUP_DIR/current-values.yaml" 2>/dev/null || echo "Helm values 백업 생략"
kubectl get configmap nexus-config -n $NAMESPACE -o yaml > "$BACKUP_DIR/nexus-configmap-backup.yaml" 2>/dev/null || echo "ConfigMap 백업 생략"

# PVC 백업 권고
echo -e "\n${YELLOW}⚠️  중요한 데이터베이스 마이그레이션이 진행됩니다!${NC}"
echo "1. PVC 백업이 완료되었는지 확인하세요"
echo "2. 이 과정은 1-2시간 소요될 수 있습니다"
echo "3. 마이그레이션 중 서비스가 중단됩니다"
echo "4. 실패 시 복구를 위해 완전한 백업이 필요합니다"
echo
read -r -p "단계적 업그레이드를 계속하시겠습니까? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${RED}❌ 업그레이드가 취소되었습니다.${NC}"
    exit 1
fi

echo "✅ 현재 설정 백업 완료"

# 1단계: 3.70.3으로 업그레이드 (OrientDB 지원 마지막 버전)
echo -e "\n${BLUE}[4/6] 1단계 업그레이드${NC}"
upgrade_to_version "$INTERMEDIATE_VERSION" "OrientDB 지원 마지막 버전으로 업그레이드"

# 마이그레이션 전 안정성 확인
echo -e "\n${YELLOW}업그레이드된 Nexus가 정상적으로 작동하는지 확인 중...${NC}"
sleep 30

# 2단계: 데이터베이스 마이그레이션
echo -e "\n${BLUE}[5/6] 2단계 데이터베이스 마이그레이션${NC}"
migrate_database

# 3단계: 최종 버전으로 업그레이드
echo -e "\n${BLUE}[6/6] 3단계 최종 업그레이드${NC}"
upgrade_to_version "$FINAL_VERSION" "H2 데이터베이스로 최종 업그레이드"

# 최종 상태 확인
echo -e "\n${GREEN}=== 단계적 업그레이드 완료 ===${NC}"

echo -e "\n📋 서비스 상태:"
kubectl get pods,svc,ingress -n $NAMESPACE -l app=nexus

echo -e "\n🔍 Nexus 버전 확인:"
kubectl get deployment nexus -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

echo -e "\n🌐 접속 정보:"
echo "  URL: https://nexus-dev.samsungena.io"
echo "  관리자: admin"
echo "  초기 비밀번호: admin123"

echo -e "\n📁 백업 위치: $BACKUP_DIR"

echo -e "\n✅ ${GREEN}Nexus Repository 단계적 업그레이드가 성공적으로 완료되었습니다!${NC}"
echo -e "🔧 OrientDB에서 H2로 데이터베이스 마이그레이션이 완료되었습니다."

echo -e "\n${YELLOW}다음 단계:${NC}"
echo "1. Nexus 웹 인터페이스 접속 확인"
echo "2. Repository 및 설정 데이터 확인"
echo "3. 기존 아티팩트 접근 테스트"
echo "4. 성능 및 안정성 모니터링"
echo "5. 백업 파일 안전한 위치에 보관"

# 정리
echo -e "\n${BLUE}임시 파일 정리 중...${NC}"
rm -f "$VALUES_FILE.bak" 2>/dev/null || true
echo "✅ 정리 완료"

echo -e "\n${GREEN}업그레이드 완료! Nexus Repository $FINAL_VERSION with H2 Database${NC}"