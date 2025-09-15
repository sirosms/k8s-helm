#!/bin/bash

# EKS Node Group User Data Script
# This script configures the node to join the EKS cluster

set -o xtrace

# Update system packages
yum update -y

# Install additional packages
yum install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Configure containerd
cat <<EOF > /etc/containerd/config.toml
version = 2
[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    sandbox_image = "602401143452.dkr.ecr.us-west-2.amazonaws.com/eks/pause:3.5"
    [plugins."io.containerd.grpc.v1.cri".containerd]
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            SystemdCgroup = true
EOF

# Restart containerd
systemctl restart containerd

# Bootstrap the node to the EKS cluster
/etc/eks/bootstrap.sh ${cluster_name} --apiserver-endpoint ${endpoint} --b64-cluster-ca ${certificate_authority}

# Configure kubelet
cat <<EOF > /etc/kubernetes/kubelet/kubelet-config.json
{
  "kind": "KubeletConfiguration",
  "apiVersion": "kubelet.config.k8s.io/v1beta1",
  "address": "0.0.0.0",
  "port": 10250,
  "readOnlyPort": 0,
  "cgroupDriver": "systemd",
  "hairpinMode": "hairpin-veth",
  "serializeImagePulls": false,
  "featureGates": {
    "RotateKubeletServerCertificate": true
  },
  "clusterDomain": "cluster.local",
  "clusterDNS": ["172.20.0.10"]
}
EOF

# Restart kubelet
systemctl restart kubelet

# Install additional tools
curl -o /usr/local/bin/kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.31.0/2024-09-12/bin/linux/amd64/kubectl
chmod +x /usr/local/bin/kubectl

# Configure log rotation for containers
cat <<EOF > /etc/logrotate.d/docker-containers
/var/lib/docker/containers/*/*.log {
  rotate 5
  daily
  compress
  size=10M
  missingok
  delaycompress
  copytruncate
}
EOF