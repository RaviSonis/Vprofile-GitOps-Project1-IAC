# Vprofile-GitOps-Project-IAC 

Infrastructure-as-code (IaC) for the **VProfile** project using **Terraform**, **AWS**, **EKS**, and **GitHub Actions** in a simple GitOps flow with two branches:

- **stage** → validate changes (plan only)
- **main** → promote/merge to apply and provision infrastructure

> This repo holds all cloud infrastructure (VPC + EKS). The workload build/deploy automation lives in the sibling repo **`vprofile-action`** (handled later).

---

## TL;DR — What I did

1. **Created an AWS IAM user** and added its keys as GitHub repository secrets:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
2. **Created an S3 bucket** for Terraform remote state and added the bucket name as a secret in this repo:
   - `BUCKET_TF_STATE`
3. **Created an ECR registry** and stored its URI in **`vprofile-action`** as the `REGISTRY` secret (for app images).
4. **Updated Terraform files** in `terraform/` and pushed commits.
5. Added the workflow **`.github/workflows/terraform.yml`**.
6. Cloned the repo locally, checked out **main**, and **merged** from **stage → main**.
7. The GitHub Action detected the push and **applied** Terraform to create the AWS infrastructure (VPC, EKS, etc.).

---

## Repository structure

```
.
├─ .github/
│  └─ workflows/
│     └─ terraform.yml        # CI pipeline that plans on stage and applies on main
├─ terraform/
│  ├─ main.tf                 # Providers and cluster name local
│  ├─ vpc.tf                  # VPC, subnets, NAT, tags for EKS
│  ├─ eks-cluster.tf          # EKS cluster + managed node groups
│  ├─ variables.tf            # region, clusterName
│  ├─ outputs.tf              # cluster endpoint, sg id, etc.
│  └─ terraform.tf            # required providers + S3 backend
└─ README.md
```

---

## Branch & GitOps model

- **stage**: open PRs or push to `terraform/**` → workflow runs **fmt/validate/plan** to verify changes.
- **main**: merging PRs (stage → main) or pushing to `terraform/**` triggers **`terraform apply`**.
- The result is a simple GitOps promotion: test in **stage**, promote to **main** to provision.

> NOTE: The provided workflow is wired to run on pushes/PRs affecting `terraform/**` paths.

---

## Required secrets (this repo)

Set these in **Settings → Secrets and variables → Actions** of **`iac-vprofile`**:

| Secret | Used for |
|---|---|
| `AWS_ACCESS_KEY_ID` | AWS auth for Terraform and kubectl (EKS auth via awscli) |
| `AWS_SECRET_ACCESS_KEY` | Pair with the access key id |
| `BUCKET_TF_STATE` | Name of the S3 bucket storing Terraform remote state |

**Optional (if you parameterize more later):** `AWS_REGION`, `EKS_CLUSTER`.

> In the current code, `variables.tf` defaults to `us-east-1`, and the cluster name defaults to `vprofile-eks`.

### IAM permissions
The IAM user must be allowed to manage at least: **S3 (state)**, **VPC/EC2**, **EKS**, and supporting services (e.g., **IAM** roles used by EKS/node groups). Grant the minimal set your organization requires.

---

## Terraform design (what this code creates)

- **Region**: default **`us-east-1`** (`var.region`)
- **Cluster name**: default **`vprofile-eks`** (`var.clusterName`)
- **VPC** (`terraform-aws-modules/vpc`):
  - CIDR: `172.20.0.0/16`
  - 3× public subnets: `172.20.4.0/24`, `172.20.5.0/24`, `172.20.6.0/24`
  - 3× private subnets: `172.20.1.0/24`, `172.20.2.0/24`, `172.20.3.0/24`
  - Single NAT Gateway, DNS hostnames enabled
  - Subnet tags for EKS load balancers (public/internal)
- **EKS** (`terraform-aws-modules/eks`):
  - Example version shown: **1.31**
  - Public endpoint enabled
  - Managed node groups (defaults from the module; customize as needed)
- **Outputs**: cluster name, endpoint, region, and cluster security group id

> The code references popular community modules to keep things concise and battle‑tested.

---

## Remote state backend (S3)

The Terraform backend is configured in `terraform/terraform.tf`. Update it to use your state bucket.

```hcl
backend "s3" {
  bucket = "<YOUR‑BUCKET‑NAME>"   # e.g., value of BUCKET_TF_STATE
  key    = "terraform.tfstate"
  region = "us-east-1"
}
```

> In code of this repo you may see a placeholder (e.g., `myactionbucket`). Replace it with your actual bucket to avoid creating local state.

---

## GitHub Actions — `terraform.yml` (high level)

The workflow:

1. Checks out code
2. Configures AWS credentials
3. Sets up Terraform (e.g., `1.6.3`)
4. **On PR / stage pushes:** runs `fmt`, `validate`, and `plan`
5. **On main pushes:** runs `apply` using the saved plan
6. After a successful apply on main:
   - Updates kubeconfig for the new cluster: `aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER"`
   - Installs an **Ingress-NGINX** controller for AWS via `kubectl apply` against the published manifest

Minimal trigger configuration (conceptual):

```yaml
on:
  push:
    branches: [main, stage]
    paths: ["terraform/**"]
  pull_request:
    branches: [main]
    paths: ["terraform/**"]
```

Environment variables used by jobs:

```yaml
env:
  AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
  AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
  BUCKET_TF_STATE: ${{ secrets.BUCKET_TF_STATE }}
  AWS_REGION: us-east-1
  EKS_CLUSTER: vprofile-eks
```

> Tip: You can make the backend bucket dynamic by templating it in CI (e.g., using `sed` or a `-backend-config` file) if you don’t want to hard‑code it.

---

## How to run locally (optional)

> Local runs are useful before opening a PR. You’ll still keep the single source of truth in the remote S3 state configured above.

Prereqs: Terraform ≥ **1.6.3**, AWS CLI, kubectl.

```bash
cd terraform

# One‑time: configure AWS credentials locally
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=us-east-1

# Init + sanity checks
terraform init
terraform fmt -check
terraform validate

# Review changes
terraform plan -out planfile

# Apply (only do this if you intend to provision from your machine)
terraform apply -auto-approve -input=false -parallelism=1 planfile

# (Optional) Access the cluster once created
aws eks update-kubeconfig --region us-east-1 --name vprofile-eks
kubectl get nodes
```

---

## Day‑2: merging & promotion workflow

1. Work off **stage**. Commit Terraform changes.
2. Open a PR to **main** and ensure the plan is clean.
3. Merge to **main** → CI applies → EKS & networking are provisioned/updated.
4. (Later) The **`vprofile-action`** repo will build/push images to ECR and deploy to this cluster.

---

## Clean‑up / destroy

If you need to tear everything down:

```bash
cd terraform
terraform destroy
```

> Beware of **costs**: EKS control plane, NAT Gateway, and load balancers incur hourly charges.

---

## What’s next (second repo)

We’ll document **`vprofile-action`** next: wiring ECR (`REGISTRY`), CI/CD for the app, and deploying into this EKS cluster via GitOps.

---
## Credits

- Original app: **/hkhcoder/vprofile-project** sample (Java/Spring, MySQL, Memcached, RabbitMQ)
- Vagrant multi-VM lab & documentation: your implementation (this repo)