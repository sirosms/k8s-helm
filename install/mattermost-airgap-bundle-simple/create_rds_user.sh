#!/bin/bash

# RDS PostgreSQL에 Mattermost 데이터베이스 및 사용자 생성

set -e

# RDS 연결 정보
RDS_HOST="gitlab-dev-postgres.c8thupqwxcj4.ap-northeast-2.rds.amazonaws.com"
RDS_PORT="5432"
MASTER_DB="postgres"
MASTER_USER="gitlab"

# Mattermost DB 정보
MATTERMOST_DB="mattermost"
MATTERMOST_USER="mattermost"
MATTERMOST_PASSWORD="epqmdhqtm1@"

echo "=== RDS PostgreSQL에 Mattermost 사용자 생성 ===="

# 마스터 사용자 비밀번호 입력
echo "RDS 마스터 사용자($MASTER_USER) 비밀번호를 입력하세요:"
echo "비밀번호가 변경된 경우 새로운 비밀번호를 사용하세요:"
read -s MASTER_PASSWORD

echo "RDS 연결 테스트..."
PGPASSWORD=$MASTER_PASSWORD psql -h $RDS_HOST -p $RDS_PORT -U $MASTER_USER -d $MASTER_DB -c "\l" > /dev/null

echo "데이터베이스 및 사용자 생성 중..."

# 데이터베이스 존재 확인 및 생성
if PGPASSWORD=$MASTER_PASSWORD psql -h $RDS_HOST -p $RDS_PORT -U $MASTER_USER -d $TER_DB -lqt | cut -d \| -f 1 | grep -qw $MATTERMOST_DB; then
    echo "데이터베이스 '$MATTERMOST_DB' 이미 존재"
else
    echo "데이터베이스 '$MATTERMOST_DB' 생성 중..."
    PGPASSWORD=$MASTER_PASSWORD createdb -h $RDS_HOST -p $RDS_PORT -U $MASTER_USER $MATTERMOST_DB
fi

# 사용자 존재 확인 및 생성
if PGPASSWORD=$MASTER_PASSWORD psql -h $RDS_HOST -p $RDS_PORT -U $MASTER_USER -d $MASTER_DB -tAc "SELECT 1 FROM pg_roles WHERE rolname='$MATTERMOST_USER'" | grep -q 1; then
    echo "사용자 '$MATTERMOST_USER' 이미 존재"
else
    echo "사용자 '$MATTERMOST_USER' 생성 중..."
    PGPASSWORD=$MASTER_PASSWORD psql -h $RDS_HOST -p $RDS_PORT -U $MASTER_USER -d $MASTER_DB -c "CREATE USER $MATTERMOST_USER WITH PASSWORD '$MATTERMOST_PASSWORD';"
fi

# 권한 부여
echo "권한 부여 중..."
PGPASSWORD=$MASTER_PASSWORD psql -h $RDS_HOST -p $RDS_PORT -U $MASTER_USER -d $MASTER_DB -c "GRANT ALL PRIVILEGES ON DATABASE $MATTERMOST_DB TO $MATTERMOST_USER;"

# Mattermost 데이터베이스에 연결하여 스키마 권한 부여
PGPASSWORD=$MASTER_PASSWORD psql -h $RDS_HOST -p $RDS_PORT -U $MASTER_USER -d $MATTERMOST_DB -c "
GRANT ALL ON SCHEMA public TO $MATTERMOST_USER;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $MATTERMOST_USER;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $MATTERMOST_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $MATTERMOST_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $MATTERMOST_USER;
"

echo
echo "=== 설정 완료 ==="
echo "데이터베이스: $MATTERMOST_DB"
echo "사용자: $MATTERMOST_USER"
echo "호스트: $RDS_HOST"
echo "포트: $RDS_PORT"

# 연결 테스트
echo
echo "연결 테스트 중..."
if PGPASSWORD=$MATTERMOST_PASSWORD psql -h $RDS_HOST -p $RDS_PORT -U $MATTERMOST_USER -d $MATTERMOST_DB -c "SELECT version();" > /dev/null; then
    echo "✅ Mattermost 사용자로 데이터베이스 연결 성공!"
else
    echo "❌ 데이터베이스 연결 실패"
    exit 1
fi

echo
echo "연결 문자열:"
echo "mattermost:epqmdhqtm1@@$RDS_HOST:$RDS_PORT/$MATTERMOST_DB?sslmode=disable&connect_timeout=10"