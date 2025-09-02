-- Mattermost 데이터베이스 및 사용자 생성
-- RDS PostgreSQL에서 실행

-- 데이터베이스 생성
CREATE DATABASE mattermost;

-- 사용자 생성
CREATE USER mattermost WITH PASSWORD 'epqmdhqtm1@';

-- 권한 부여
GRANT ALL PRIVILEGES ON DATABASE mattermost TO mattermost;

-- 스키마 권한 부여 (연결 후 실행)
\c mattermost;
GRANT ALL ON SCHEMA public TO mattermost;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO mattermost;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO mattermost;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO mattermost;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO mattermost;

-- 연결 확인
\du mattermost;
\l mattermost;