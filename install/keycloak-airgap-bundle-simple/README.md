# Nexus Repository Manager 설치

이 스크립트는 Kubernetes 클러스터에 Nexus Repository Manager를 설치합니다.

## 사전 요구사항

1. **Kubernetes 클러스터**
   - kubectl 명령어 설정 완료
   - Helm 3.x 설치

2. **Storage Class**
   - `nfs-client-sc` Storage Class 설정 완료

3. **TLS 인증서**
   - `samsungena.io-tls` Secret이 default 네임스페이스에 존재
   - Reflector가 설치되어 있어야 자동으로 devops 네임스페이스로 복사됨

## 설치 순서

### 1. PVC 생성

먼저 Nexus용 PVC를 생성합니다:

```bash
kubectl apply -f pvc/nexus-pvc.yaml
```

### 2. Nexus 설치

설치 스크립트를 실행합니다:

```bash
./install-nexus.sh
```

스크립트 실행 중 다음 정보를 입력해야 합니다:
- Nexus 외부 URL (기본값: https://nexus.samsungena.io)
- 관리자 이메일 (기본값: admin@samsungena.io)

## 설치 확인

설치 완료 후 다음 명령으로 상태를 확인할 수 있습니다:

```bash
kubectl get pods -n devops
kubectl get svc -n devops
kubectl get ingress -n devops
```

## 접속 방법

### 1. Ingress를 통한 접속

브라우저에서 설정한 URL로 접속:
- https://nexus.samsungena.io

### 2. Port Forward를 통한 접속

```bash
kubectl port-forward -n devops svc/nexus 8081:8081
```
브라우저에서 http://localhost:8081 접속

## 초기 설정

### 관리자 비밀번호 확인

```bash
kubectl exec -n devops $(kubectl get pod -n devops -l app=nexus -o jsonpath='{.items[0].metadata.name}') -- cat /nexus-data/admin.password
```

### 로그인 정보
- 사용자명: admin
- 비밀번호: 위 명령으로 확인된 초기 비밀번호

## 구성 요소

- **네임스페이스**: devops
- **PVC**: 
  - nexus-data (20Gi) - Nexus 데이터 저장
  - nexus-db (10Gi) - Nexus DB 저장
- **이미지**: sonatype/nexus3:3.37.3
- **포트**: 8081 (HTTP), 8181 (Docker Registry)

## 문제 해결

### PVC 생성 실패
Storage Class `nfs-client-sc`가 설정되어 있는지 확인:
```bash
kubectl get storageclass
```

### TLS 인증서 문제
Reflector가 설치되어 있고 samsungena.io-tls Secret이 존재하는지 확인:
```bash
kubectl get secret samsungena.io-tls -n default
kubectl get secret samsungena.io-tls -n devops
```

### Pod 시작 실패
리소스 부족 또는 PVC 마운트 문제일 수 있습니다:
```bash
kubectl describe pod -n devops -l app=nexus
kubectl logs -n devops -l app=nexus
```