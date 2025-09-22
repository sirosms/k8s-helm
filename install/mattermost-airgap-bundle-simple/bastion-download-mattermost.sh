#!/bin/bash

# Bastion 서버에서 Mattermost 이미지 다운로드 및 ECR 업로드

set -e

# Bastion 서버 정보
BASTION_HOST="your-bastion-server"  # 실제 bastion 서버 주소로 변경 필요
BASTION_USER="ec2-user"             # 실제 사용자명으로 변경 필요

# 원격 실행할 스크립트 생성
cat > remote-download-script.sh << 'EOF'
#!/bin/bash

set -e

# 변수 설정
MATTERMOST_VERSION="10.12.0"
ECR_REGISTRY="866376286331.dkr.ecr.ap-northeast-2.amazonaws.com"
ECR_REPO="mattermost-team-edition"
AWS_REGION="ap-northeast-2"

echo "=== Bastion에서 Mattermost $MATTERMOST_VERSION 이미지 다운로드 및 ECR 업로드 ==="

# Docker Hub에서 이미지 다운로드
echo "Docker Hub에서 Mattermost $MATTERMOST_VERSION 이미지 다운로드 중..."
docker pull mattermost/mattermost-team-edition:$MATTERMOST_VERSION

# ECR 로그인
echo "ECR 로그인 중..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

# 이미지 태깅
echo "이미지 태깅 중..."
docker tag mattermost/mattermost-team-edition:$MATTERMOST_VERSION $ECR_REGISTRY/$ECR_REPO:$MATTERMOST_VERSION

# ECR에 이미지 푸시
echo "ECR에 이미지 푸시 중..."
docker push $ECR_REGISTRY/$ECR_REPO:$MATTERMOST_VERSION

echo "✅ Mattermost $MATTERMOST_VERSION 이미지가 ECR에 성공적으로 업로드되었습니다!"
echo "ECR 이미지: $ECR_REGISTRY/$ECR_REPO:$MATTERMOST_VERSION"

# 다운로드된 이미지 확인
echo "다운로드된 이미지 확인:"
docker images | grep mattermost
EOF

# 스크립트 실행 권한 부여
chmod +x remote-download-script.sh

echo "=== Bastion 서버에 스크립트 복사 및 실행 ==="
echo "다음 명령어를 사용하여 bastion 서버에서 실행하세요:"
echo ""
echo "1. Bastion 서버에 스크립트 복사:"
echo "   scp remote-download-script.sh $BASTION_USER@$BASTION_HOST:~/"
echo ""
echo "2. Bastion 서버에 접속:"
echo "   ssh $BASTION_USER@$BASTION_HOST"
echo ""
echo "3. 스크립트 실행:"
echo "   chmod +x remote-download-script.sh"
echo "   ./remote-download-script.sh"
echo ""
echo "또는 한 번에 실행:"
echo "   ssh $BASTION_USER@$BASTION_HOST 'bash -s' < remote-download-script.sh"