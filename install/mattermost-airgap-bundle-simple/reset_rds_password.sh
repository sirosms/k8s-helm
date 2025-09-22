#!/bin/bash

# RDS PostgreSQL 마스터 사용자 비밀번호 재설정

set -e

# RDS 인스턴스 정보
RDS_INSTANCE_ID="gitlab-dev-postgres"
MASTER_USER="gitlab"

echo "=== RDS 마스터 사용자 비밀번호 재설정 ==="
echo "RDS 인스턴스: $RDS_INSTANCE_ID"
echo "마스터 사용자: $MASTER_USER"
echo

# 새 비밀번호 입력
echo "새로운 마스터 비밀번호를 입력하세요:"
read -s NEW_PASSWORD

echo "비밀번호 확인을 위해 다시 입력하세요:"
read -s CONFIRM_PASSWORD

if [ "$NEW_PASSWORD" != "$CONFIRM_PASSWORD" ]; then
    echo "❌ 비밀번호가 일치하지 않습니다."
    exit 1
fi

echo
echo "RDS 마스터 사용자 비밀번호를 재설정하는 중..."

# RDS 마스터 사용자 비밀번호 재설정
aws rds modify-db-instance \
    --db-instance-identifier $RDS_INSTANCE_ID \
    --master-user-password "$NEW_PASSWORD" \
    --apply-immediately \
    --region ap-northeast-2

echo "✅ 비밀번호 재설정 요청 완료"
echo
echo "⚠️  비밀번호 변경이 적용되는 데 몇 분이 걸릴 수 있습니다."
echo "RDS 인스턴스 상태를 확인하세요:"
echo "aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --region ap-northeast-2 --query 'DBInstances[0].DBInstanceStatus'"
echo
echo "변경 완료 후 연결 테스트:"
echo "./test_rds_connection.sh"