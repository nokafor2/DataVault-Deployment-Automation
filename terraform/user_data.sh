#!/bin/bash
# EC2 first-boot script — runs once when the k3s instance launches.
# Installs: Docker, k3s, metrics-server (HPA), ECR credentials, ArgoCD.
# Template variables injected by Terraform templatefile(): ${aws_region}, ${ecr_registry}, ${project_name}

# Before long bootstrap: ensure console EC2 Instance Connect and Session Manager work
yum install -y ec2-instance-connect amazon-ssm-agent
systemctl enable --now amazon-ssm-agent
systemctl restart sshd

set -euxo pipefail

yum update -y
yum install -y docker git jq aws-cli

systemctl enable docker
systemctl start docker

# k3s: lightweight Kubernetes — kubeconfig readable without sudo for bootstrap scripts
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
alias kubectl='/usr/local/bin/k3s kubectl'

# metrics-server: required for HPA CPU metrics (kubectl top, HPA controller)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# k3s uses self-signed kubelet certs — insecure TLS flag needed for metrics-server on single node
kubectl patch deployment metrics-server -n kube-system --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' || true

# ECR pull secret for k3s/containerd (docker login does NOT auth containerd image pulls)
cat >/usr/local/bin/ecr-refresh-k8s-secret.sh <<'ECRSCRIPT'
#!/bin/bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
AWS_REGION="${aws_region}"
ECR_REGISTRY="${ecr_registry}"
TOKEN="$(aws ecr get-login-password --region "$AWS_REGION")"
kubectl create secret docker-registry ecr-pull-secret \
  --namespace=default \
  --docker-server="$ECR_REGISTRY" \
  --docker-username=AWS \
  --docker-password="$TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
ECRSCRIPT
chmod +x /usr/local/bin/ecr-refresh-k8s-secret.sh
/usr/local/bin/ecr-refresh-k8s-secret.sh

# Host cron backup until Argo CD syncs ecr-refresh-cronjob.yaml (tokens expire after ~12h)
echo "0 */6 * * * root /usr/local/bin/ecr-refresh-k8s-secret.sh" >> /etc/crontab

# ArgoCD: GitOps controller — watches Git repo and syncs k8s/ manifests
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Expose ArgoCD UI on host port 30081 (get admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort","ports":[{"port":443,"targetPort":8080,"nodePort":30081}]}}' || true

echo "k3s and ArgoCD bootstrap complete for ${project_name}"
