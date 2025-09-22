#!/bin/bash

# RDS PostgreSQL 연결 테스트

set -e

# RDS 연결 정보
RDS_HOST="gitlab-dev-postgres.c8thupqwxcj4.ap-northeast-2.rds.amazonaws.com"
RDS_PORT="5432"
MASTER_DB="postgres"
MASTER_USER="gitlab"

echo "=== RDS PostgreSQL 연결 테스트 ==="

# 마스터 사용자 비밀번호 입력
echo "RDS 마스터 사용자($MASTER_USER) 비밀번호를 입력하세요:"
read -s MASTER_PASSWORD

echo "RDS 연결 테스트 중..."

# 연결 테스트
if PGPASSWORD=$MASTER_PASSWORD psql -h $RDS_HOST -p $RDS_PORT -U $MASTER_USER -d $MASTER_DB -c "SELECT version();" 2>/dev/null; then
    echo "✅ RDS 연결 성공!"
    echo
    echo "기존 데이터베이스 목록:"
    PGPASSWORD=$MASTER_PASSWORD psql -h $RDS_HOST -p $RDS_PORT -U $MASTER_USER -d $MASTER_DB -c "\l"
    echo
    echo "기존 사용자 목록:"
    PGPASSWORD=$MASTER_PASSWORD psql -h $RDS_HOST -p $RDS_PORT -U $MASTER_USER -d $MASTER_DB -c "\du"
else
    echo "❌ RDS 연결 실패"
    echo "비밀번호가 올바른지 확인하세요."
    exit 1
fi