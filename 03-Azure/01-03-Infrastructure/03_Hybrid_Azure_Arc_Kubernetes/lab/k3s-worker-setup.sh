#!/bin/bash
set -euo pipefail

# Wait for master to be ready (give it some time to start up)
sleep 60

# Update system
apt-get update
apt-get upgrade -y

# Install required packages
apt-get install -y curl wget apt-transport-https ca-certificates gnupg lsb-release

# Install Docker (required for some workloads)
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

# Add mhadmin to docker group
usermod -aG docker mhadmin

# Install K3s agent (worker node)
export INSTALL_K3S_VERSION=${k3s_version}
export K3S_TOKEN=${cluster_token}
export K3S_URL=https://${master_ip}:6443

# Wait for master to be accessible
echo "Waiting for K3s master at $${K3S_URL}..."
while ! curl -k -s $${K3S_URL}/ping > /dev/null 2>&1; do
  echo "Master not ready yet, waiting..."
  sleep 10
done

# Get external IP reliably
EXTERNAL_IP=$(curl -s --max-time 10 https://ipinfo.io/ip 2>/dev/null || curl -s --max-time 10 http://checkip.amazonaws.com 2>/dev/null || echo "")

# Install K3s agent
if [ -n "$EXTERNAL_IP" ] && [[ "$EXTERNAL_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    curl -sfL https://get.k3s.io | sh -s - agent \
      --server $${K3S_URL} \
      --token $${K3S_TOKEN} \
      --node-external-ip "$EXTERNAL_IP"
else
    # Fallback without external IP if detection fails
    curl -sfL https://get.k3s.io | sh -s - agent \
      --server $${K3S_URL} \
      --token $${K3S_TOKEN}
fi

# Enable and start K3s agent
systemctl enable k3s-agent
systemctl start k3s-agent

echo "K3s worker node setup completed!"