# EKS Terraform POC — Learning Notes
> Date: July 5, 2026
> Goal: Understand how EKS works end-to-end, and how a browser request reaches a Pod and returns.

---

## 1. Project Files Created

```
eks-poc/
  provider.tf   -> AWS provider + version config
  vpc.tf        -> VPC module (networking)
  eks.tf        -> EKS module (cluster + node group)
```

### provider.tf
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = "ap-south-1"
}
```

### vpc.tf (using official Terraform AWS VPC module)
```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"
  name    = "banaras"
  cidr    = "10.0.0.0/16"
  azs     = ["ap-south-1a", "ap-south-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.3.0/24", "10.0.4.0/24"]
  enable_nat_gateway   = true
  enable_vpn_gateway   = true
  enable_dns_hostnames = true
}
```

### eks.tf (using official Terraform AWS EKS module)
```hcl
module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 20.0"
  cluster_name    = "banaras-Dairy-EKS"
  cluster_version = "1.30"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets
  control_plane_subnet_ids       = module.vpc.public_subnets
  cluster_endpoint_public_access = true

  eks_managed_node_groups = {
    general_node_group = {
      desired_capacity = 2
      max_capacity     = 3
      min_capacity     = 1
      instance_types   = ["t3.medium"]
      capacity_type    = "SPOT"
    }
  }
}
```

**Key learning: Module vs Raw Resource**
- Raw resources (writing every `aws_vpc`, `aws_subnet`, `aws_iam_role` manually) = good for understanding *what* gets created, but slow and error-prone (spent 4 hours on this, kept failing).
- Terraform modules (`terraform-aws-modules/vpc/aws`, `terraform-aws-modules/eks/aws`) = pre-built, tested by community, much faster and more reliable. Created full EKS cluster + VPC in under 10 minutes with modules vs repeated failures with raw resources.
- Trade-off: with modules you don't see every single resource being created directly in your own code, but `terraform plan` output still shows everything happening under the hood.

---

## 2. Real-World Analogy — EKS as a Society (Apartment Complex)

| AWS Concept | Real-world equivalent |
|---|---|
| VPC | The plot of land |
| Public Subnet | Building visible from the main road |
| Private Subnet | Buildings inside, hidden from outside |
| Internet Gateway | Main road connecting society to the city |
| NAT Gateway | Society's back gate — residents can go out, but outsiders can't come in through it |
| EKS Cluster (Control Plane) | Society's Management Office — the "brain" deciding what runs where |
| Node Group (EC2 instances) | Actual watchmen/staff who do the physical work |
| Pods | Individual flats where families (containers) live |

---

## 3. What Got Created (terraform apply result)

```
Apply complete! Resources: 57 added, 0 changed, 0 destroyed.

Cluster creation time: 7m 30s
Node Group join time:  1m 48s
```

Key resources created:
- `aws_eks_cluster` — the control plane (management office)
- `aws_eks_node_group` — the worker EC2 instances (watchmen)
- `aws_cloudwatch_log_group` — logs every important event (society diary)
- `aws_iam_openid_connect_provider` (OIDC) — allows Pods to get AWS permissions without hardcoded keys
- KMS key — encrypts secrets (locker key)
- Security Groups — gate rules (who can enter/exit)

---

## 4. THE MAIN GOAL — Browser URL to Pod and Back

This is the complete request flow, step by step:

```
Step 1:  User types URL in browser -> https://your-alb-url.com/

Step 2:  DNS resolves to ALB (Application Load Balancer)
         ALB lives in the PUBLIC subnet (visible from internet)

Step 3:  ALB receives HTTPS request on port 443
         ALB terminates SSL (decrypts HTTPS -> HTTP)

Step 4:  ALB forwards request to a Target Group
         Target Group = list of healthy Pod IPs

Step 5:  Traffic enters the EKS cluster
         Ingress Controller (nginx / ALB Controller) reads Ingress rules:
         "which Service should handle this path?"

Step 6:  Ingress -> Service (ClusterIP)
         Service = internal load balancer
         Picks ONE healthy Pod using Selector labels

Step 7:  Service -> Pod
         Pod runs the FastAPI/React container
         Pod lives in the PRIVATE subnet (hidden from internet)

Step 8:  Pod processes the request
         FastAPI reads the request, runs the logic, builds HTML/JSON response

Step 9:  Response travels back the same path:
         Pod -> Service -> Ingress -> ALB -> Internet -> Browser

Step 10: Browser renders the HTML page
```

**Why Pods are in Private Subnet (security logic):**
- Public subnet = society's main gate (ALB stands here, faces the road)
- Private subnet = inside the buildings (Pods live here, hidden)
- Nobody can directly knock on a Pod's door. Everyone must go through: ALB (gate) -> Ingress (reception) -> Service (floor manager) -> Pod (flat)

---

## 5. Connecting kubectl to the Cluster

```bash
aws eks update-kubeconfig --region ap-south-1 --name banaras-Dairy-EKS
```

**What this command does:**
- `aws eks update-kubeconfig` = "teach me how to talk to this cluster"
- `--region ap-south-1` = which region the cluster is in
- `--name banaras-Dairy-EKS` = which cluster to connect to

**What happens behind the scenes:**
1. AWS fetches the cluster's connection info (endpoint URL + certificate)
2. That info gets written into `~/.kube/config`
3. From then on, every `kubectl` command automatically reads `~/.kube/config` to know who to talk to

**Analogy:** The kubeconfig file is like your Society Management Office's phone number + gate pass. The IAM permission (ID card) was already valid — you just saved the phone number.

---

## 6. What is the Certificate in kubeconfig?

- This is the **Certificate Authority (CA) certificate** for the EKS API server.
- The EKS API server runs over HTTPS (like any secure website).
- `kubectl` needs to verify: "Is this really my cluster, not a fake server?"
- This certificate gets saved in `~/.kube/config` so kubectl can trust the connection.
- **Analogy:** Like a society's official stamp — verifies a letter really came from the official office, not a fake one.

---

## 7. IAM User vs IAM Role — Important Distinction

Ran: `aws sts get-caller-identity`
```json
{
    "UserId": "AIDA4NFQXVNPBNIUAAFTW",
    "Account": "852921658206",
    "Arn": "arn:aws:iam::852921658206:user/banaras-dairy-deploy"
}
```

**Key insight:** The ARN says `user/banaras-dairy-deploy`, NOT a role.
- If an IAM Role were attached to the EC2 instance, the ARN would look like:
  `assumed-role/some-role-name/instance-id`
- Since it says `user/...`, this means: IAM User access keys were manually configured on this EC2 (via `aws configure`), stored in `~/.aws/credentials`. This is NOT an EC2 Instance Profile / IAM Role.

**Security best practice (for interviews):**
- Best practice = Attach an IAM Role to EC2 via Instance Profile -> no static keys, automatic credential rotation.
- Current POC setup = IAM User with long-lived access keys -> works for a quick POC, but not production-grade.

**Interview answer to use:**
> "For this POC I used IAM user credentials for speed, but production best practice is an EC2 Instance Profile with an IAM Role — no static keys, automatic credential rotation."

---

## 8. How to Create a Proper IAM Role + Instance Profile for EC2 (reference steps)

### Step 1: Create trust policy (who can assume this role)
```bash
cat > trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
```
Meaning: "Allow the EC2 service to wear this role."

### Step 2: Create the IAM Role
```bash
aws iam create-role \
  --role-name banaras-eks-ec2-role \
  --assume-role-policy-document file://trust-policy.json
```

### Step 3: Attach permissions (Admin used here for POC simplicity)
```bash
aws iam attach-role-policy \
  --role-name banaras-eks-ec2-role \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

### Step 4: Create Instance Profile (wrapper to let EC2 wear the Role)
```bash
aws iam create-instance-profile \
  --instance-profile-name banaras-eks-instance-profile

aws iam add-role-to-instance-profile \
  --instance-profile-name banaras-eks-instance-profile \
  --role-name banaras-eks-ec2-role
```

### Step 5: Attach the Instance Profile to the running EC2 instance
```bash
aws ec2 associate-iam-instance-profile \
  --instance-id <YOUR_EC2_INSTANCE_ID> \
  --iam-instance-profile Name=banaras-eks-instance-profile
```

To find the instance ID by IP:
```bash
aws ec2 describe-instances \
  --filters "Name=ip-address,Values=13.207.230.242" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text
```

---

## 9. Common Errors Faced (and fixes)

| Error | Cause | Fix |
|---|---|---|
| `dial tcp: lookup eks.ap-south-1.amazonaws.com: no such host` | Local machine's network/DNS had intermittent issues reaching AWS APIs | Moved the entire Terraform run to an EC2 instance (better AWS connectivity, same VPC/region) |
| `You may not specify all protocols and specific ports` (Security Group egress rule) | Used `ip_protocol = "-1"` (all protocols) together with specific `from_port`/`to_port` | When using `-1` (all protocols), do NOT specify port ranges — remove `from_port`/`to_port` |
| `Reference to undeclared module` | `vpc.tf` file missing or not synced properly before `terraform plan` | Re-verify file exists with `ls -la` and `cat vpc.tf`, then re-run `terraform init` |
| Raw resource EKS node group failing after ~30 min | Hand-written IAM roles / networking wiring likely had a subtle issue (needs deeper investigation) | Switched to official Terraform modules (`terraform-aws-modules/vpc/aws`, `terraform-aws-modules/eks/aws`) — succeeded in under 10 minutes |

---

## 10. Next Steps (to continue this POC)

1. `kubectl get nodes` — verify worker nodes joined the cluster
2. Deploy the Banaras Dairy app as a Deployment + Service
3. Install an Ingress Controller (e.g., AWS Load Balancer Controller)
4. Create an Ingress resource to expose the app via ALB
5. Test: hit the ALB URL in browser -> confirm response comes back from the Pod
6. Document final working URL and screenshot for interview reference
7. Run `terraform destroy` after testing to avoid ongoing AWS charges
