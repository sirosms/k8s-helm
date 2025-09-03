#!/bin/bash

# RDS PostgreSQL에 Vault 데이터베이스 및 사용자 생성

set -e

# RDS 연결 정보
RDS_HOST="gitlab-dev-postgres.c8thupqwxcj4.ap-northeast-2.rds.amazonaws.com"
RDS_PORT="5432"
MASTER_DB="postgres"
MASTER_USER="gitlab"

# Vault DB 정보
VAULT_DB="vault"
VAULT_USER="vault"
VAULT_PASSWORD="epqmdhqtm1@"

echo "=== RDS PostgreSQL에 Vault 사용자 생성 ===="

# 마스터 사용자 비밀번호 입력
echo "RDS 마스터 사용자($MASTER_USER) 비밀번호를 입력하세요:"
read -s MASTER_PASSWORD

echo "RDS 연결 테스트..."
PGPASSWORD=$MASTER_PASSWORD psql -h $RDS_HOST -p $RDS_PORT -U $MASTER_USER -d $MASTER_DB -c "\l" > /dev/null

echo "데이터베이스 및 사용자 생성 중..."

# 데이터베이스 존재 확인 및 생성
if PGPASSWORD=$MASTER_PASSWORD psql -h $RDS_HOST -p $RDS_PORT -U $MASTER_USER -d $MASTER_DB -lqt | cut -d \| -f 1 | grep -qw $VAULT_DB; then
    echo "데이터베이스 '$VAULT_DB' 이미 존재"
else
    echo "데이터베이스 '$VAULT_DB' 생성 중..."
    PGPASSWORD=$MASTER_PASSWORD createdb -h $RDS_HOST -p $RDS_PORT -U $MASTER_USER $VAULT_DB
fi

# 사용자 존재 확인 및 생성
if PGPASSWORD=$MASTER_PASSWORD psql -h $RDS_HOST -p $RDS_PORT -U $MASTER_USER -d $MASTER_DB -tAc "SELECT 1 FROM pg_roles WHERE rolname='$VAULT_USER'" | grep -q 1; then
    echo "사용자 '$VAULT_USER' 이미 존재"
else
    echo "사용자 '$VAULT_USER' 생성 중..."
    PGPASSWORD=$MASTER_PASSWORD psql -h $RDS_HOST -p $RDS_PORT -U $MASTER_USER -d $MASTER_DB -c "CREATE USER $VAULT_USER WITH PASSWORD '$VAULT_PASSWORD';"
fi

# 권한 부여
echo "권한 부여 중..."
PGPASSWORD=$MASTER_PASSWORD psql -h $RDS_HOST -p $RDS_PORT -U $MASTER_USER -d $MASTER_DB -c "GRANT ALL PRIVILEGES ON DATABASE $VAULT_DB TO $VAULT_USER;"

# Vault 데이터베이스에 연결하여 스키마 권한 부여
PGPASSWORD=$MASTER_PASSWORD psql -h $RDS_HOST -p $RDS_PORT -U $MASTER_USER -d $VAULT_DB -c "
GRANT ALL ON SCHEMA public TO $VAULT_USER;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $VAULT_USER;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $VAULT_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $VAULT_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $VAULT_USER;
"

echo
echo "=== 설정 완료 ==="
echo "데이터베이스: $VAULT_DB"
echo "사용자: $VAULT_USER"
echo "호스트: $RDS_HOST"
echo "포트: $RDS_PORT"

# 연결 테스트
echo
echo "연결 테스트 중..."
if PGPASSWORD=$VAULT_PASSWORD psql -h $RDS_HOST -p $RDS_PORT -U $VAULT_USER -d $VAULT_DB -c "SELECT version();" > /dev/null; then
    echo "✅ Vault 사용자로 데이터베이스 연결 성공!"
else
    echo "❌ 데이터베이스 연결 실패"
    exit 1
fi

echo
echo "연결 문자열:"
echo "vault:vaultpassword@@$RDS_HOST:$RDS_PORT/$VAULT_DB?sslmode=disable"