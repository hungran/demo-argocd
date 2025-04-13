#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to handle errors
handle_error() {
  echo -e "${RED}Error occurred during setup. Check the error message above.${NC}"
  exit 1
}

# Set error trap
trap 'handle_error' ERR

echo -e "${BLUE}Creating Kind cluster...${NC}"
kind delete cluster --name argocd-demo 2>/dev/null || true
kind create cluster --name argocd-demo --config kind-config.yaml || { echo -e "${RED}Failed to create Kind cluster!${NC}"; exit 1; }

echo -e "${BLUE}Verifying cluster is running...${NC}"
kubectl cluster-info --context kind-argocd-demo || { echo -e "${RED}Cluster not accessible!${NC}"; exit 1; }

echo -e "${BLUE}Waiting for all cluster components to be ready...${NC}"
echo -e "${BLUE}This may take a minute...${NC}"
kubectl wait --for=condition=Ready --namespace kube-system --all pods --timeout=300s || { 
  echo -e "${YELLOW}Some pods are not yet ready, but we'll proceed anyway...${NC}"
}

echo -e "${BLUE}Creating ArgoCD namespace...${NC}"
kubectl create namespace argocd || { echo -e "${YELLOW}Namespace may already exist, continuing...${NC}"; }

echo -e "${BLUE}Installing ArgoCD...${NC}"
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml || { echo -e "${RED}Failed to install ArgoCD!${NC}"; exit 1; }

echo -e "${BLUE}Waiting for ArgoCD components to be ready...${NC}"
echo -e "${BLUE}This may take a few minutes...${NC}"
for i in {1..3}; do
  echo -e "${BLUE}Attempt $i of 3...${NC}"
  kubectl wait --for=condition=available deployment -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s && break || {
    if [[ $i -lt 3 ]]; then
      echo -e "${YELLOW}Still waiting for ArgoCD server to be ready... Retrying in 30 seconds.${NC}"
      sleep 30
    else
      echo -e "${YELLOW}ArgoCD server not fully ready yet, but we'll proceed. You may need to wait longer before accessing it.${NC}"
    fi
  }
done

echo -e "${GREEN}ArgoCD installation completed!${NC}"

# Get the ArgoCD password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
if [[ -n "$ARGOCD_PASSWORD" ]]; then
  echo -e "${GREEN}ArgoCD Initial Admin Password: ${ARGOCD_PASSWORD}${NC}"
else
  echo -e "${YELLOW}Could not retrieve ArgoCD password yet. You may need to wait longer and run:${NC}"
  echo "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
fi

echo -e "${BLUE}Setting up ArgoCD to manage itself...${NC}"
# Replace placeholder with actual repository URL
read -p "Enter your GitHub username: " GITHUB_USERNAME
if [[ -n "$GITHUB_USERNAME" ]]; then
  sed -i '' "s|YOUR_USERNAME|$GITHUB_USERNAME|g" argocd/argocd-install.yaml
  sed -i '' "s|YOUR_USERNAME|$GITHUB_USERNAME|g" argocd/whoami-app.yaml

  echo -e "${BLUE}Applying ArgoCD self-management configuration...${NC}"
  kubectl apply -f argocd/argocd-install.yaml -n argocd || echo -e "${YELLOW}Failed to apply ArgoCD configuration. Make sure your Git repository is accessible.${NC}"

  echo -e "${BLUE}Applying Whoami application configuration...${NC}"
  kubectl apply -f argocd/whoami-app.yaml -n argocd || echo -e "${YELLOW}Failed to apply Whoami application configuration. Check your Git repository.${NC}"
else
  echo -e "${YELLOW}No GitHub username provided. Skipping GitOps setup.${NC}"
fi

echo -e "${GREEN}Setup completed!${NC}"
echo -e "${BLUE}To access ArgoCD UI, run:${NC}"
echo "kubectl port-forward svc/argocd-server -n argocd 9080:443"
echo -e "${BLUE}Then open:${NC} https://localhost:9080"
echo -e "${BLUE}Username:${NC} admin"
echo -e "${BLUE}Password:${NC} $ARGOCD_PASSWORD"

echo -e "${BLUE}To access Whoami app, run:${NC}"
echo "kubectl port-forward svc/whoami -n whoami 9090:80"
echo -e "${BLUE}Then open:${NC} http://localhost:9090" 