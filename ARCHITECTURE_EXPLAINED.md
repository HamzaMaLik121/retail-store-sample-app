# Retail Store Sample App - Architecture Explanation

## 📋 Table of Contents
1. [Overview](#overview)
2. [Terraform Infrastructure](#terraform-infrastructure)
3. [Helm Charts](#helm-charts)
4. [ArgoCD GitOps](#argocd-gitops)
5. [CI/CD Pipeline](#cicd-pipeline)
6. [Complete Deployment Flow](#complete-deployment-flow)

---

## 🎯 Overview

This project demonstrates a **modern cloud-native architecture** using:
- **Terraform**: Infrastructure as Code (IaC)
- **AWS EKS**: Managed Kubernetes cluster
- **Helm**: Kubernetes package manager
- **ArgoCD**: GitOps continuous delivery
- **GitHub Actions**: CI/CD automation (on production branch)

```
┌─────────────────────────────────────────────────────────────┐
│                    Deployment Pipeline                       │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  Developer → Git Push → [GitHub Actions] → ECR Images        │
│                              ↓                                │
│                         Update Manifests                      │
│                              ↓                                │
│                    [ArgoCD watches Git]                       │
│                              ↓                                │
│                    Deploys to EKS Cluster                     │
│                              ↓                                │
│              [Application Running on Kubernetes]              │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

---

## 🏗️ Terraform Infrastructure

### What Terraform Does

Terraform creates the entire AWS infrastructure from code. Located in `/terraform` directory.

### Key Files and Their Purpose

#### 1. **locals.tf** (Currently open)
```hcl
# Defines reusable values across all Terraform files
locals {
  cluster_name = "${var.cluster_name}-${random_string.suffix.result}"
  # Adds random suffix to avoid naming conflicts
  
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
  # Uses first 3 availability zones for high availability
  
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 10)]
  # Creates private subnets: 10.0.10.0/24, 10.0.11.0/24, 10.0.12.0/24
  
  public_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k)]
  # Creates public subnets: 10.0.0.0/24, 10.0.1.0/24, 10.0.2.0/24
}
```

**Purpose**: Centralizes configuration and computes derived values

#### 2. **main.tf**
Creates the core infrastructure:

**VPC Module**:
```hcl
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  
  # Creates:
  # - VPC with specified CIDR (default: 10.0.0.0/16)
  # - 3 public subnets (for load balancers)
  # - 3 private subnets (for application pods)
  # - Internet Gateway (for public internet access)
  # - NAT Gateway (for private subnet internet access)
  # - Route tables
}
```

**EKS Cluster Module**:
```hcl
module "retail_app_eks" {
  source = "terraform-aws-modules/eks/aws"
  
  # Creates:
  # - EKS Control Plane (Kubernetes API)
  # - Auto Mode enabled (AWS manages node lifecycle)
  # - IAM roles and policies
  # - Security groups
  # - Encryption keys (KMS)
}
```

**EKS Auto Mode**: AWS automatically provisions, scales, and manages worker nodes. No need to manage node groups manually!

#### 3. **addons.tf**
Installs essential Kubernetes add-ons:

```hcl
module "eks_addons" {
  # NGINX Ingress Controller
  # - Routes external traffic to services
  # - Creates AWS Network Load Balancer
  # - Handles SSL termination
  
  # Cert Manager
  # - Automates SSL certificate management
  # - Integrates with Let's Encrypt
}
```

**What these add-ons do**:
- **NGINX Ingress**: Acts as the entry point for all HTTP/HTTPS traffic
- **Cert Manager**: Automatically provisions and renews SSL certificates

#### 4. **argocd.tf**
Installs and configures ArgoCD:

```hcl
resource "helm_release" "argocd" {
  # Installs ArgoCD using Helm chart
  # - Creates argocd namespace
  # - Deploys ArgoCD server, controller, repo-server
  # - Sets up with insecure mode for easier local access
}

resource "kubectl_manifest" "argocd_projects" {
  # Applies ArgoCD Project configuration
  # Defines permissions and source repositories
}

resource "kubectl_manifest" "argocd_apps" {
  # Applies ArgoCD Application manifests
  # Tells ArgoCD what applications to deploy
}
```

### Infrastructure Components Diagram

```
┌─────────────────────────────────────────────────────────┐
│                        AWS Cloud                         │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  ┌─────────────────────────────────────────────────┐   │
│  │              VPC (10.0.0.0/16)                  │   │
│  │                                                  │   │
│  │  ┌──────────────┐  ┌──────────────┐           │   │
│  │  │ Public Subnet│  │ Public Subnet│  ...      │   │
│  │  │  10.0.0.0/24 │  │  10.0.1.0/24 │           │   │
│  │  │              │  │              │           │   │
│  │  │  [NLB/ALB]   │  │  [NAT GW]    │           │   │
│  │  └──────────────┘  └──────────────┘           │   │
│  │                                                  │   │
│  │  ┌──────────────┐  ┌──────────────┐           │   │
│  │  │Private Subnet│  │Private Subnet│  ...      │   │
│  │  │ 10.0.10.0/24 │  │ 10.0.11.0/24 │           │   │
│  │  │              │  │              │           │   │
│  │  │ [EKS Pods]   │  │ [EKS Pods]   │           │   │
│  │  │ - UI         │  │ - Catalog    │           │   │
│  │  │ - Cart       │  │ - Orders     │           │   │
│  │  │ - Checkout   │  │ - ArgoCD     │           │   │
│  │  └──────────────┘  └──────────────┘           │   │
│  │                                                  │   │
│  └─────────────────────────────────────────────────┘   │
│                                                           │
│  ┌─────────────────────────────────────────────────┐   │
│  │         EKS Control Plane                       │   │
│  │  (Managed by AWS)                               │   │
│  │  - API Server                                   │   │
│  │  - Scheduler                                    │   │
│  │  - Controller Manager                           │   │
│  └─────────────────────────────────────────────────┘   │
│                                                           │
└─────────────────────────────────────────────────────────┘
```

---

## 📦 Helm Charts

### What is Helm?

Helm is a **package manager for Kubernetes**. Think of it like `npm` for Node.js or `apt` for Ubuntu, but for Kubernetes applications.

### Helm Chart Structure

Each microservice has its own Helm chart in `src/<service>/chart/`:

```
src/ui/chart/
├── Chart.yaml           # Chart metadata (name, version)
├── values.yaml          # Default configuration values
└── templates/           # Kubernetes manifest templates
    ├── deployment.yaml  # Pod specifications
    ├── service.yaml     # Service definitions
    ├── ingress.yaml     # Routing rules
    └── configmap.yaml   # Configuration data
```

### Example: UI Service Helm Chart

**values.yaml**:
```yaml
image:
  repository: public.ecr.aws/aws-containers/retail-store-sample-ui
  tag: v1.2.2
  
replicas: 1

service:
  type: ClusterIP
  port: 8080

ingress:
  enabled: true
  path: /
```

**How it works**:
1. Helm reads `values.yaml` configuration
2. Substitutes values into template files
3. Generates complete Kubernetes manifests
4. Applies them to the cluster

### Why Use Helm?

- **Reusability**: Same chart, different environments (dev, staging, prod)
- **Templating**: One template, many configurations
- **Versioning**: Track changes and rollback easily
- **Packaging**: Bundle all related Kubernetes resources together

---

## 🔄 ArgoCD GitOps

### What is ArgoCD?

ArgoCD is a **declarative GitOps continuous delivery tool** for Kubernetes. It continuously monitors your Git repository and automatically syncs changes to your cluster.

### GitOps Principle

```
Git Repository (Source of Truth)
        ↓
    ArgoCD watches
        ↓
    Detects changes
        ↓
    Automatically deploys
        ↓
    Kubernetes Cluster
```

### ArgoCD Configuration

Located in `/argocd` directory:

#### 1. **Project Definition** (`argocd/projects/retail-store-project.yaml`)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: retail-store
spec:
  sourceRepos:
    - 'https://github.com/LondheShubham153/retail-store-sample-app'
  
  destinations:
    - namespace: retail-store
      server: https://kubernetes.default.svc
  
  # Defines what Kubernetes resources can be deployed
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace
  
  namespaceResourceWhitelist:
    - group: 'apps'
      kind: Deployment
    - group: ''
      kind: Service
    # ... more resource types
```

**Purpose**: Security boundary that defines:
- Which Git repositories can be used
- Which Kubernetes namespaces can be deployed to
- What types of resources can be created

#### 2. **Application Definitions** (`argocd/applications/*.yaml`)

Example: `retail-store-ui.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-store-ui
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "2"  # Deploy order
spec:
  project: retail-store
  
  source:
    repoURL: https://github.com/LondheShubham153/retail-store-sample-app
    targetRevision: main
    path: src/ui/chart           # Points to Helm chart
    helm:
      valueFiles:
        - values.yaml
  
  destination:
    server: https://kubernetes.default.svc
    namespace: retail-store
  
  syncPolicy:
    automated:
      prune: true      # Delete resources removed from Git
      selfHeal: true   # Automatically fix drift from desired state
    syncOptions:
      - CreateNamespace=true
```

**What this does**:
1. ArgoCD monitors `src/ui/chart` in the Git repository
2. When changes are detected, ArgoCD:
   - Pulls the latest Helm chart
   - Renders templates with values
   - Applies to Kubernetes cluster
3. If someone manually changes the deployment, ArgoCD reverts it (self-heal)

### ArgoCD Sync Waves

```
Wave 0: Infrastructure (databases, caches)
  ↓
Wave 1: Backend services (catalog, cart, orders)
  ↓
Wave 2: Frontend services (ui, checkout)
  ↓
Wave 3: Monitoring and ingress
```

This ensures services deploy in the correct order.

### How ArgoCD Works

```
┌──────────────────────────────────────────────────────┐
│                                                        │
│  Git Repository (Desired State)                       │
│  └── src/ui/chart/values.yaml                         │
│      image: v1.2.3                                    │
│                                                        │
└────────────────┬───────────────────────────────────────┘
                 │
                 │ ArgoCD polls every 3 minutes
                 ↓
┌──────────────────────────────────────────────────────┐
│                                                        │
│  ArgoCD Controller                                    │
│  - Compares Git with Cluster                          │
│  - Detects differences                                │
│  - Applies changes                                    │
│                                                        │
└────────────────┬───────────────────────────────────────┘
                 │
                 │ kubectl apply
                 ↓
┌──────────────────────────────────────────────────────┐
│                                                        │
│  Kubernetes Cluster (Actual State)                    │
│  └── Deployment/retail-store-ui                       │
│      image: v1.2.3 ✓                                  │
│                                                        │
└──────────────────────────────────────────────────────┘
```

---

## 🚀 CI/CD Pipeline

### Where is CI/CD?

**Important**: The CI/CD pipeline (GitHub Actions) is **NOT in the main branch**. 

Based on the README, there are two deployment strategies:

### 1. **Main Branch (Public Application)**
- No CI/CD pipeline
- Uses **public ECR images** with stable versions (v1.2.2)
- Manual deployment control
- Great for demos and learning

### 2. **Production/GitOps Branch**
- Full **GitHub Actions** CI/CD pipeline
- Uses **private ECR** with automated builds
- Image tags based on Git commit hashes
- Automatic deployment on code changes

### Typical CI/CD Flow (Production Branch)

```yaml
# .github/workflows/build-and-push.yml (on production branch)

name: Build and Push to ECR

on:
  push:
    branches: [production]
    paths:
      - 'src/**'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      1. Checkout code
      2. Configure AWS credentials
      3. Login to Amazon ECR
      4. Build Docker image
      5. Tag with commit SHA
      6. Push to ECR
      7. Update Helm values with new image tag
      8. Commit and push updated values
      
  # ArgoCD detects the values.yaml change
  # ArgoCD automatically deploys new version
```

### CI/CD Pipeline Diagram

```
┌─────────────────────────────────────────────────────────┐
│  Developer                                               │
│  └── git push origin production                         │
└────────────────┬────────────────────────────────────────┘
                 │
                 ↓
┌─────────────────────────────────────────────────────────┐
│  GitHub Actions (CI Pipeline)                            │
│  ├── Build Docker image                                  │
│  ├── Run tests                                           │
│  ├── Tag with commit SHA (abc1234)                       │
│  ├── Push to Amazon ECR                                  │
│  └── Update values.yaml with new tag                     │
└────────────────┬────────────────────────────────────────┘
                 │
                 ↓
┌─────────────────────────────────────────────────────────┐
│  Git Repository Updated                                  │
│  src/ui/chart/values.yaml                                │
│  image:                                                  │
│    repository: 123456.dkr.ecr.region.amazonaws.com/ui    │
│    tag: abc1234  ← NEW                                   │
└────────────────┬────────────────────────────────────────┘
                 │
                 ↓
┌─────────────────────────────────────────────────────────┐
│  ArgoCD (CD Pipeline)                                    │
│  ├── Detects values.yaml change                          │
│  ├── Pulls new Helm chart                                │
│  ├── Renders Kubernetes manifests                        │
│  └── Deploys to EKS cluster                              │
└────────────────┬────────────────────────────────────────┘
                 │
                 ↓
┌─────────────────────────────────────────────────────────┐
│  Application Running                                     │
│  └── Pod with image: abc1234                             │
└─────────────────────────────────────────────────────────┘
```

### Why Separate Branches?

- **Main branch**: Simple, uses public images, no AWS credentials needed
- **Production branch**: Full automation, private ECR, requires AWS setup

This allows users to choose their deployment complexity level.

---

## 🔁 Complete Deployment Flow

### Phase 1: Infrastructure Setup (One Time)

```
1. Run: terraform init
   └── Downloads required providers (AWS, Kubernetes, Helm)

2. Run: terraform apply
   ├── Creates VPC with subnets
   ├── Creates EKS cluster
   ├── Installs NGINX Ingress
   ├── Installs Cert Manager
   ├── Installs ArgoCD via Helm
   ├── Applies ArgoCD Project
   └── Applies ArgoCD Applications

3. ArgoCD takes over
   ├── Reads application manifests
   ├── Pulls Helm charts from Git
   ├── Deploys all microservices
   └── Creates namespace: retail-store

4. NGINX Ingress provisions AWS NLB
   └── External IP for accessing the application
```

### Phase 2: Day 2 Operations (Ongoing)

**Scenario: Update UI service**

```
1. Developer changes code in src/ui/

2. Developer pushes to Git
   └── git push origin main (or production)

3. IF production branch:
   ├── GitHub Actions triggers
   ├── Builds new Docker image
   ├── Pushes to ECR with new tag
   └── Updates src/ui/chart/values.yaml

4. ArgoCD detects change
   ├── Compares Git vs Cluster
   ├── Identifies drift
   └── Syncs new version

5. Kubernetes performs rolling update
   ├── Creates new pods with new image
   ├── Waits for readiness
   ├── Terminates old pods
   └── Zero downtime deployment ✓
```

### Traffic Flow

```
User Browser
     ↓
Internet
     ↓
AWS Network Load Balancer
     ↓
NGINX Ingress Controller (in EKS)
     ↓ (routing based on path)
     ├─ / → UI Service
     ├─ /api/catalog → Catalog Service
     ├─ /api/cart → Cart Service
     ├─ /api/orders → Orders Service
     └─ /api/checkout → Checkout Service
```

---

## 🎓 Key Concepts Summary

### Terraform
- **Purpose**: Infrastructure as Code
- **What it creates**: VPC, EKS, IAM roles, security groups
- **When it runs**: Once during initial setup, or when infrastructure changes

### Helm
- **Purpose**: Kubernetes package manager
- **What it manages**: Application deployment configurations
- **Benefits**: Templating, versioning, reusability

### ArgoCD
- **Purpose**: GitOps continuous delivery
- **What it monitors**: Git repository for changes
- **What it does**: Automatically syncs Git state to Kubernetes cluster

### CI/CD (GitHub Actions)
- **Purpose**: Continuous Integration/Continuous Deployment
- **Where**: Production/GitOps branch only
- **What it does**: Build, test, push images, update manifests

---

## 📁 Directory Structure Explained

```
retail-store-sample-app/
├── terraform/              # Infrastructure as Code
│   ├── main.tf            # VPC and EKS cluster
│   ├── addons.tf          # NGINX, Cert Manager
│   ├── argocd.tf          # ArgoCD installation
│   ├── locals.tf          # Reusable values (OPEN FILE)
│   └── variables.tf       # Input variables
│
├── argocd/                # GitOps configuration
│   ├── projects/          # ArgoCD project definitions
│   │   └── retail-store-project.yaml
│   └── applications/      # ArgoCD app manifests
│       ├── retail-store-ui.yaml
│       ├── retail-store-catalog.yaml
│       └── ...
│
├── src/                   # Application source code
│   ├── ui/               # UI microservice
│   │   ├── chart/        # Helm chart
│   │   │   ├── values.yaml
│   │   │   └── templates/
│   │   ├── Dockerfile    # Container image definition
│   │   └── [source code]
│   │
│   ├── catalog/          # Similar structure
│   ├── cart/             # Similar structure
│   ├── orders/           # Similar structure
│   └── checkout/         # Similar structure
│
└── .github/              # CI/CD (production branch only)
    └── workflows/
        └── build-and-push.yml
```

---

## 🔧 Common Operations

### View deployed applications
```bash
kubectl get pods -n retail-store
```

### Access ArgoCD UI
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open: https://localhost:8080
```

### Get ArgoCD password
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

### Check ingress
```bash
kubectl get svc -n ingress-nginx
# Look for EXTERNAL-IP
```

### Manually sync an app in ArgoCD
```bash
argocd app sync retail-store-ui
```

---

## 🎯 Summary

This architecture implements **modern DevOps best practices**:

1. **Infrastructure as Code** (Terraform) - Repeatable, version-controlled infrastructure
2. **Containerization** (Docker) - Consistent environments
3. **Orchestration** (Kubernetes/EKS) - Automated scaling and healing
4. **GitOps** (ArgoCD) - Git as single source of truth
5. **Continuous Delivery** (GitHub Actions + ArgoCD) - Fast, reliable deployments

**The main branch** uses a simplified approach (public images, no CI/CD) that's perfect for learning and demos.

**The production branch** implements the full enterprise workflow with private registries and automated pipelines.

