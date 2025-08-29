#!/bin/bash
set -euo pipefail

# 설치 변수
NAMESPACE="devops"
RELEASE_NAME="jenkins"
CHART_PATH="./charts/jenkins"
VALUES_FILE="./values/jenkins.yaml"

echo "=== Jenkins Simple 설치 스크립트 ==="

# Jenkins 설정 입력
echo "Jenkins 설정을 입력하세요:"
read -r -p "Jenkins 외부 URL [https://jenkins-dev.samsungena.io]: " JENKINS_URL
JENKINS_URL=${JENKINS_URL:-https://jenkins-dev.samsungena.io}

read -r -p "관리자 이메일 [admin@samsungena.io]: " ADMIN_EMAIL
ADMIN_EMAIL=${ADMIN_EMAIL:-admin@samsungena.io}

echo
echo "입력된 설정:"
echo "  Jenkins URL: $JENKINS_URL"
echo "  관리자 이메일: $ADMIN_EMAIL"
echo

# PVC 생성 확인
echo "💡 Jenkins용 PVC가 미리 생성되어 있는지 확인하세요:"
echo "   - jenkins-home-dev"
echo
read -r -p "PVC가 준비되어 있습니까? (y/N): " pvc_ready
if [[ ! "$pvc_ready" =~ ^[Yy]$ ]]; then
    echo "❌ PVC를 먼저 생성한 후 다시 실행해주세요."
    echo "   kubectl apply -f pvc/jenkins-pvc.yaml"
    exit 1
fi

# 네임스페이스 생성
echo "[1/3] 네임스페이스 생성"
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Helm 차트 패키징 (필요한 경우)
echo "[2/3] Helm 차트 패키징"
if [ ! -f "jenkins-0.1.0.tgz" ]; then
    helm package ${CHART_PATH} .
fi

# Helm 설치
echo "[3/3] Jenkins 설치"
helm upgrade --install ${RELEASE_NAME} ${CHART_PATH} \
  --namespace ${NAMESPACE} \
  --values ${VALUES_FILE} \
  --set ingress.host="$(echo $JENKINS_URL | sed 's|https\?://||')" \
  --set configMap."jenkins.model.JenkinsLocationConfiguration.xml"="<?xml version='1.1' encoding='UTF-8'?><jenkins.model.JenkinsLocationConfiguration><adminAddress>$ADMIN_EMAIL</adminAddress><jenkinsUrl>$JENKINS_URL</jenkinsUrl></jenkins.model.JenkinsLocationConfiguration>" \
  --set configMap."config.xml"="<?xml version='1.1' encoding='UTF-8'?><hudson><disabledAdministrativeMonitors><string>jenkins.security.apitoken.ApiTokenPropertyDisabledDefaultAdministrativeMonitor</string><string>jenkins.security.apitoken.ApiTokenPropertyEnabledNewLegacyAdministrativeMonitor</string><string>jenkins.security.csrf.CSRFAdministrativeMonitor</string><string>hudson.diagnosis.ReverseProxySetupMonitor</string><string>jenkins.diagnostics.SecurityIsOffMonitor</string><string>jenkins.security.QueueItemAuthenticatorMonitor</string></disabledAdministrativeMonitors><version>2.319.3</version><installStateName>RESTART</installStateName><numExecutors>0</numExecutors><mode>NORMAL</mode><useSecurity>true</useSecurity><authorizationStrategy class=\"hudson.security.ProjectMatrixAuthorizationStrategy\"><permission>hudson.model.Hudson.Administer:$ADMIN_EMAIL</permission><permission>hudson.model.Hudson.Read:authenticated</permission></authorizationStrategy><securityRealm class=\"hudson.security.HudsonPrivateSecurityRealm\"><disableSignup>false</disableSignup><enableCaptcha>false</enableCaptcha></securityRealm><disableRememberMe>false</disableRememberMe><projectNamingStrategy class=\"jenkins.model.ProjectNamingStrategy\$DefaultProjectNamingStrategy\"/><workspaceDir>\${JENKINS_HOME}/workspace/\${ITEM_FULLNAME}</workspaceDir><buildsDir>\${ITEM_ROOTDIR}/builds</buildsDir><markupFormatter class=\"hudson.markup.EscapedMarkupFormatter\"/><viewsTabBar class=\"hudson.views.DefaultViewsTabBar\"/><myViewsTabBar class=\"hudson.views.DefaultMyViewsTabBar\"/><quietPeriod>5</quietPeriod><scmCheckoutRetryCount>0</scmCheckoutRetryCount><views><hudson.model.AllView><owner class=\"hudson\" reference=\"../../..\"/><name>all</name><filterExecutors>false</filterExecutors><filterQueue>false</filterQueue><properties class=\"hudson.model.View\$PropertyList\"/></hudson.model.AllView></views><primaryView>all</primaryView><slaveAgentPort>50000</slaveAgentPort><label></label><nodeProperties/><globalNodeProperties/><noUsageStatistics>true</noUsageStatistics><crumbIssuer class=\"hudson.security.csrf.DefaultCrumbIssuer\"><excludeClientIPFromCrumb>true</excludeClientIPFromCrumb></crumbIssuer></hudson>" \
  --timeout 900s

echo
echo "설치 상태 확인:"
kubectl get pods -n ${NAMESPACE}
kubectl get svc -n ${NAMESPACE}

echo
echo "✅ Jenkins 설치 완료!"
echo "📝 초기 관리자 계정으로 로그인하세요"
echo "🌐 접속 URL: $JENKINS_URL"
echo
echo "포트 포워딩으로 접속 테스트:"
echo "kubectl port-forward -n ${NAMESPACE} svc/${RELEASE_NAME} 8080:8080"
echo "브라우저에서 http://localhost:8080 접속"