# ArgoCD on Kind with GitOps Demo

This guide demonstrates how to set up a Kind Kubernetes cluster, install ArgoCD, configure it to manage itself via GitOps, and deploy a simple Traefik whoami application.

## Prerequisites

- Docker installed and running
- kubectl installed
- kind installed
- git installed
- helm installed (optional but recommended)

## 1. Create a Kind Cluster

```bash
# Create a kind configuration file
cat <<EOF > kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30080
    hostPort: 9080
    protocol: TCP
  - containerPort: 30443
    hostPort: 9443
    protocol: TCP
EOF

# Create a kind cluster using the config
kind create cluster --name argocd-demo --config kind-config.yaml

# Verify the cluster is running
kubectl cluster-info --context kind-argocd-demo
```

## 2. Install ArgoCD

```bash
# Create namespace for ArgoCD
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for all ArgoCD components to be ready
kubectl wait --for=condition=available deployment -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Expose the ArgoCD server using port-forward (for access during setup)
kubectl port-forward svc/argocd-server -n argocd 9080:443
```

## 3. Get ArgoCD Admin Password and Login

```bash
# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Use the ArgoCD CLI to login (install if needed)
# brew install argocd
argocd login localhost:9080 --username admin --password <INITIAL_PASSWORD> --insecure

# Or access ArgoCD UI via browser at https://localhost:9080
# Username: admin, Password: <INITIAL_PASSWORD>
```

## 4. Set Up the Git Repository Structure

Create a Git repository with the following structure to manage your cluster:

```
.
├── README.md
├── argocd/
│   ├── application.yaml
│   └── argocd-install.yaml
└── applications/
    └── whoami/
        ├── deployment.yaml
        ├── service.yaml
        └── ingress.yaml
```

## 5. Configure ArgoCD to Manage Itself (GitOps)

Create the ArgoCD installation manifest:

```bash
mkdir -p argocd applications/whoami
```

Create the ArgoCD self-managed installation file:

```bash
cat <<EOF > argocd/argocd-install.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/hungran/demo-argocd.git
    targetRevision: HEAD
    path: argocd
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
```

Apply this configuration to your cluster:

```bash
kubectl apply -f argocd/argocd-install.yaml -n argocd
```

## 6. Create Traefik Whoami Application Manifests

Create deployment for whoami app:

```bash
cat <<EOF > applications/whoami/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: whoami
  namespace: whoami
spec:
  replicas: 2
  selector:
    matchLabels:
      app: whoami
  template:
    metadata:
      labels:
        app: whoami
    spec:
      containers:
      - name: whoami
        image: traefik/whoami:v1.8.7
        ports:
        - containerPort: 80
          name: web
        resources:
          limits:
            memory: "128Mi"
            cpu: "100m"
EOF
```

Create service for whoami app:

```bash
cat <<EOF > applications/whoami/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: whoami
  namespace: whoami
spec:
  ports:
  - port: 80
    targetPort: web
    name: web
  selector:
    app: whoami
EOF
```

Create namespace definition:

```bash
cat <<EOF > applications/whoami/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: whoami
EOF
```

## 7. Create ArgoCD Application for Whoami

```bash
cat <<EOF > argocd/whoami-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: whoami
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/hungran/demo-argocd.git
    targetRevision: HEAD
    path: applications/whoami
  destination:
    server: https://kubernetes.default.svc
    namespace: whoami
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF
```

## 8. Push Configuration to Git Repository

```bash
# Initialize git repository (if not already done)
git init
git add .
git commit -m "Initial commit: ArgoCD and whoami application"

# Add your remote repository
git remote add origin https://github.com/hungran/demo-argocd.git
git push -u origin main
```

## 9. Apply the Applications with ArgoCD

```bash
# Apply the whoami application definition
kubectl apply -f argocd/whoami-app.yaml -n argocd

# Check the application status
argocd app get whoami
```

## 10. Access the Whoami Application

```bash
# Port-forward the service
kubectl port-forward svc/whoami -n whoami 9090:80

# Access the app at http://localhost:9090
```

## 11. Clean Up (when done)

```bash
# Delete the kind cluster
kind delete cluster --name argocd-demo
```

## Troubleshooting

- If ArgoCD can't sync applications, check that your Git repository URL is accessible from the cluster.
- Ensure that you've replaced "hungran" with your actual GitHub username in the YAML files.
- If applications get stuck in "Progressing" state, check the application logs using `kubectl logs` for the relevant pods. 