# EKS Terraform Cluster

이 프로젝트는 Terraform을 사용하여 AWS EKS 클러스터를 구축합니다.

## 요구사항

- Kubernetes: v1.31
- OS: Ubuntu 22.04.4 LTS
- Kernel: 5.15.0-94-generic
- Container Runtime: containerd 1.7.27
- Node Type: m5.large

## 사전 요구사항

- AWS CLI 설치 및 구성
- Terraform 설치 (>= 1.0)
- kubectl 설치
- 적절한 AWS IAM 권한

## 배포 방법

### 1. 자동 배포 (권장)

```bash
./deploy.sh deploy
```

### 2. 수동 배포

```bash
# 1. SSH 키 생성
ssh-keygen -t rsa -b 4096 -f eks-key -N ""

# 2. Terraform 초기화
terraform init

# 3. 계획 확인
terraform plan

# 4. 배포 실행
terraform apply

# 5. kubectl 구성
aws eks update-kubeconfig --region ap-northeast-2 --name samsung-eks-cluster
```

## 아키텍처

### 네트워킹
- VPC: 10.0.0.0/16
- Public Subnets: 10.0.101.0/24, 10.0.102.0/24, 10.0.103.0/24
- Private Subnets: 10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24
- NAT Gateway: 각 AZ별 1개
- Internet Gateway: 1개

### EKS 클러스터
- 버전: 1.31
- 노드 그룹: Private 서브넷에 배포
- 인스턴스 타입: m5.large
- 용량: 최소 1, 기본 2, 최대 4

### Add-ons
- vpc-cni
- coredns
- kube-proxy
- aws-ebs-csi-driver

## 리소스 정리

```bash
./deploy.sh destroy
```

또는

```bash
terraform destroy
```

## 출력 값

배포 완료 후 다음 정보들을 확인할 수 있습니다:

- 클러스터 엔드포인트
- VPC ID
- 서브넷 ID들
- 보안 그룹 ID
- kubeconfig 설정

## 문제 해결

### 1. AWS 권한 오류
필요한 IAM 권한이 있는지 확인하세요:
- EKS 클러스터 생성 권한
- EC2 인스턴스 관리 권한
- VPC 및 네트워킹 권한
- IAM 역할 생성 권한

### 2. kubectl 연결 오류
```bash
aws eks update-kubeconfig --region ap-northeast-2 --name samsung-eks-cluster
```

### 3. 노드 그룹 준비 대기
클러스터가 완전히 준비될 때까지 5-10분 정도 소요될 수 있습니다.

## 파일 구조

```
eks-terraform-cluster/
├── main.tf              # 메인 Terraform 구성
├── variables.tf         # 변수 정의
├── vpc.tf              # VPC 및 네트워킹 리소스
├── iam.tf              # IAM 역할 및 정책
├── eks.tf              # EKS 클러스터 및 애드온
├── node-groups.tf      # 워커 노드 그룹
├── userdata.sh         # 노드 초기화 스크립트
├── outputs.tf          # 출력 값 정의
├── deploy.sh           # 배포 스크립트
└── README.md           # 이 파일
```