# Banaras Dairy — EKS Infrastructure (Terraform + Kubernetes)

A hands-on POC: taking a full-stack app (React + FastAPI + Postgres, originally
running as Docker Compose on a single EC2 instance) and deploying it onto a
production-pattern **AWS EKS** cluster — provisioned entirely with Terraform,
exposed via the **AWS Load Balancer Controller** (real ALB, not just a bare
Service), with secrets in **SSM Parameter Store** and remote Terraform state
in **S3 + DynamoDB**.

Built to answer one interview question that I once fumbled: *"If a user hits
a URL in the browser, walk me through exactly how that request reaches a Pod
in EKS."* This repo is that answer, made real.

## Architecture

```
Browser
  │  HTTP
  ▼
ALB (internet-facing, created by AWS Load Balancer Controller
     from a Kubernetes Ingress object)
  │  target-type=ip → direct to Pod IP (AWS VPC CNI gives Pods real VPC IPs)
  ▼
Frontend Pod (nginx serving React SPA)
  │  reverse-proxies /api/* → Service "api" (ClusterIP, DNAT via kube-proxy)
  ▼
Backend Pod (FastAPI)
  │  → Service "postgres" (ClusterIP, DNAT via kube-proxy)
  ▼
Postgres Pod
```

- **VPC:** 2 public + 2 private subnets across 2 AZs (`terraform-aws-modules/vpc`)
- **EKS:** managed node group, ON_DEMAND t3.medium, `terraform-aws-modules/eks`
- **Ingress:** AWS Load Balancer Controller (Helm) → real ALB, not NGINX-in-cluster
- **Secrets:** SSM Parameter Store (SecureString) — not hardcoded, not in git
- **State:** S3 (versioned, encrypted, private) + DynamoDB (locking)

## Repo layout

```
eks-poc/
├── provider.tf, vpc.tf, eks.tf          # core infra
├── alb_controller_iam.tf(.json)         # IAM policy for the ALB Controller
├── secrets.tf, variables.tf             # SSM Parameter Store wiring
├── outputs.tf
├── k8s/                                 # postgres, backend, frontend, ingress
├── scripts/
│   ├── bootstrap_backend.sh             # ONE-TIME: create S3 bucket + DynamoDB table
│   ├── deploy.sh                        # daily: terraform apply + full app deploy
│   └── teardown.sh                      # daily: safe teardown (ALB first, then VPC)
└── docs/                                # learning notes from building this
```

## One-time setup

```bash
aws configure                                   # IAM user/role with sufficient perms
cd eks-poc
./scripts/bootstrap_backend.sh                  # creates S3 + DynamoDB, writes backend.hcl
cp secrets.auto.tfvars.example secrets.auto.tfvars
# edit secrets.auto.tfvars with real DB password + GHCR token
```

## Daily usage

```bash
bash scripts/deploy.sh      # spin everything up, prints the ALB URL at the end
# ... use the app ...
bash scripts/teardown.sh    # tear everything down (deletes Ingress/ALB FIRST, then VPC)
```

Running `deploy.sh` + `teardown.sh` daily (instead of leaving the cluster up)
keeps this a **$0-ish POC** — the EKS control plane bills ~$0.10/hr regardless
of whether it's idle, so the cheapest state is "doesn't exist" when not in use.

## Why some things are deliberately simplified (POC shortcuts)

- **IAM on the node role, not IRSA** — the ALB Controller gets its permissions
  via the EC2 node's IAM role (all Pods on the node share it) instead of a
  scoped-down IRSA role. Simpler for a POC; wrong for prod (bigger blast
  radius). Tracked as a follow-up in `docs/EKS_POC_Learning_Plan.md`.
- **No TLS on the ALB** — HTTP only, no ACM cert, no Route 53 domain. Adding
  HTTPS needs a real domain for ACM's DNS validation, which is out of scope
  for a throwaway POC cluster with a rotating ALB DNS name.
- **Postgres as a bare Deployment + emptyDir** — data is lost on pod restart.
  Fine for demoing the request flow; would be a StatefulSet + EBS-backed PVC
  (or RDS) in anything real.

## Full write-up

See `eks-poc/docs/eks_terraform_learn.md` for the detailed, blow-by-blow
learning log (every error hit and how it was diagnosed/fixed — state locks,
IAM drift, silent wrong Terraform module attribute names, the `PUBLIC_HOSTNAME`
env-export bug, SNAT/DNAT at each network hop, etc).
