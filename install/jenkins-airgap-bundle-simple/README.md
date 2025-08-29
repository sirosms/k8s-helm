# Jenkins 폐쇄망 설치 번들

이 번들은 폐쇄망 환경에서 Jenkins를 Kubernetes에 설치하기 위한 패키지입니다.

## 디렉토리 구조

```
jenkins-airgap-bundle-simple/
├── charts/                    # Helm 차트
│   └── jenkins/
├── images/                   # Docker 이미지 (.tar 파일)
├── meta/                     # 메타데이터
│   └── images.txt           # 이미지 리스트
├── values/                   # 설정 파일
│   └── jenkins.yaml         # Jenkins 설정
├── pvc/                      # PVC 정의
│   └── jenkins-pvc.yaml     # Jenkins 영구 볼륨
├── install-jenkins.sh        # 설치 스크립트
├── push-to-ecr.sh           # ECR 푸시 스크립트
└── README.md                # 이 파일
```

## 필요 조건

- Kubernetes 클러스터
- Helm 3.x
- kubectl CLI
- Docker (이미지 로드용)

## 설치 방법

### 1. PVC 생성

```bash
kubectl apply -f pvc/jenkins-pvc.yaml
```

### 2. Jenkins 설치

```bash
./install-jenkins.sh
```

설치 스크립트 실행 시 다음 정보를 입력해야 합니다:
- Jenkins 외부 URL (기본값: https://jenkins-dev.samsungena.io)
- 관리자 이메일 (기본값: admin@samsungena.io)

### 3. 설치 확인

```bash
kubectl get pods -n devops
kubectl get svc -n devops
```

## 포트 포워딩으로 접속

```bash
kubectl port-forward -n devops svc/jenkins 8080:8080
```

브라우저에서 http://localhost:8080 접속

## 이미지 관리

### Docker 이미지 저장
```bash
docker save 866376286331.dkr.ecr.ap-northeast-2.amazonaws.com/devops-service/jenkins-master:v1.20220310 -o images/jenkins-master-v1.20220310.tar
```

### ECR에 이미지 푸시 (필요시)
```bash
./push-to-ecr.sh
```

## 설정 커스터마이징

`values/jenkins.yaml` 파일을 수정하여 설정을 변경할 수 있습니다:

- 리소스 할당량
- 이미지 레지스트리
- Ingress 설정
- ConfigMap 설정

## 주요 설정

- **기본 관리자 계정**: 초기 설치 후 관리자 계정으로 로그인
- **포트**: 8080 (HTTP), 50000 (Agent)
- **영구 스토리지**: `/var/jenkins_home` (20GB)
- **네임스페이스**: devops

## 문제 해결

### Pod 상태 확인
```bash
kubectl describe pod -n devops -l app=jenkins
```

### 로그 확인
```bash
kubectl logs -n devops -l app=jenkins -f
```

### 설정 확인
```bash
kubectl get configmap -n devops jenkins-config -o yaml
```