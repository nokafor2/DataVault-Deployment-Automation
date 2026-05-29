# DataVault Deployment Automation Platform

**DataVault Technologies — GitOps Remediation Platform Guide**

*Kubernetes · ArgoCD · Terraform · GitHub Actions*

---

## 1. Project Structure

```
datavault-gitops/
  app/
    main.py              (FastAPI app - provided)
    requirements.txt
    Dockerfile           (container image)
  k8s/
    deployment.yaml      (2 replicas, probes)
    service.yaml         (NodePort 30080)
    configmap.yaml       (APP_ENV, LOG_LEVEL)
    secret.yaml          (API_KEY base64)
    hpa.yaml             (2-5 pods, CPU 70%)
  terraform/
    main.tf              (ECR + EC2 k3s)
    variables.tf
    outputs.tf
    backend.tf           (S3 remote state)
    user_data.sh         (k3s, metrics-server, ArgoCD)
  argocd/
    application.yaml     (ArgoCD watches k8s/)
  .github/workflows/
    ci.yml               (test, build, ECR, manifest)
  tests/
```

---

## 2. End-to-End Flow

The platform follows a linear pipeline from developer push to running pods:

1. **Developer** pushes code to GitHub
2. **GitHub Actions** runs tests, builds Docker image, pushes to ECR, updates `k8s/deployment.yaml`, commits back to Git (audit trail)
3. **Git** remains the single source of truth for both application code and Kubernetes manifests
4. **ArgoCD** detects manifest changes and syncs the k3s cluster
5. **Kubernetes** runs 2+ replicas with probes, HPA, and self-healing
6. **Clients** reach the API via NodePort `http://<EC2-IP>:30080`

### Flow Diagram

```
Developer Push
      ↓
GitHub Actions: pytest → docker build → ECR push → update deployment.yaml → git commit
      ↓
Git Repository (audit trail)
      ↓
ArgoCD watches k8s/ → sync cluster to Git state
      ↓
k3s Cluster: Deployment (2 replicas) → Service (NodePort 30080) → HPA
```

**Infrastructure (Terraform):** ECR stores images · EC2 t3.small runs k3s + ArgoCD + app workloads

---

## 3. Layer by Layer

### 3.1 Application (`app/`)

The FastAPI app exposes:

| Endpoint | Role |
|----------|------|
| `/health` | **Liveness** — if it fails, Kubernetes restarts the pod |
| `/ready` | **Readiness** — if it fails, the Service stops sending traffic |
| `/api/*` | Business API (requires `x-api-key` from Secret) |

The **Dockerfile** packages `main.py` on Python 3.11 and runs `uvicorn` on port **8000**.

---

### 3.2 Kubernetes Manifests (`k8s/`)

| File | Purpose | Connects to |
|------|---------|-------------|
| **configmap.yaml** | Non-sensitive env: `APP_ENV`, `LOG_LEVEL` | Injected into pods via `envFrom` |
| **secret.yaml** | `API_KEY` (base64) | Same — app authentication |
| **deployment.yaml** | 2 replicas, rolling updates, probes, ECR image | Pulls from ECR; reads ConfigMap + Secret |
| **service.yaml** | NodePort **30080** → pod port **8000** | Access: `http://<EC2-IP>:30080` |
| **hpa.yaml** | Min 2, max 5 pods at **70% CPU** | Requires metrics-server (installed in `user_data.sh`) |

**Self-healing:** If a pod dies, the Deployment controller creates a new one. Liveness failures trigger restarts. Readiness keeps unhealthy pods out of traffic during rollouts.

---

### 3.3 Terraform (`terraform/`)

| Resource | Purpose |
|----------|---------|
| **ECR** (`datavault-api`) | Private store for images built by CI |
| **EC2 t3.small** | Runs **k3s** (Kubernetes) + **ArgoCD** |
| **IAM role** | Lets the node pull from ECR |
| **Security group** | SSH (22), API (30080), ArgoCD UI (30081) |
| **S3 backend** | Versioned, shared Terraform state |

**`user_data.sh` on first boot:**

1. Installs **k3s**
2. Installs **metrics-server** (for HPA)
3. Creates **`ecr-pull-secret`** for k3s/containerd ECR pulls (refreshed every 6 hours; see `k8s/ecr-refresh-cronjob.yaml`)
4. Installs **ArgoCD**

After `terraform apply`, use outputs (`ecr_repository_url`, `k3s_public_ip`) to update `k8s/deployment.yaml` image URI and configure CI secrets.

---

### 3.4 GitHub Actions (`.github/workflows/ci.yml`)

On push to `main`:

1. **test** — `pytest tests/`
2. **build-and-deploy** — build image from `app/`, push to ECR with tag `github.sha`
3. **Update** `k8s/deployment.yaml` with new image + `GIT_COMMIT`
4. **Commit & push** — that commit is the **FCA audit record** (who, what, when)

ArgoCD sees the manifest change and rolls out the new version automatically.

---

### 3.5 ArgoCD (`argocd/application.yaml`)

Applied **once** on the cluster:

```bash
kubectl apply -f argocd/application.yaml
```

ArgoCD watches your GitHub repo's `k8s/` folder. When Git and the cluster differ, it syncs the cluster to match Git.

| Old (Valentine's Day) | New (GitOps) |
|------------------------|--------------|
| SSH + manual restart | Git commit → ArgoCD sync |
| No rollback | `git revert` → ArgoCD redeploys previous version |
| No audit trail | Git log + ArgoCD sync history |

---

## 4. How Each Problem Is Solved

| Valentine's Day Problem | Solution in This Repo |
|-------------------------|------------------------|
| Manual SSH deploys | CI + ArgoCD — no SSH for app deploys |
| No rollback | `git revert` + ArgoCD sync |
| No deployment audit trail | Every deploy = Git commit (author, SHA, message) |
| No self-healing | Kubernetes restarts failed pods; liveness on `/health` |
| Config drift between servers | One declarative `k8s/` set for the whole cluster |
| Knowledge in one engineer's head | Everything in Git + Terraform |

---

## 5. Setup Order (chronological)

Follow these steps **in order**. Steps **1–4** provision AWS. Steps **5–8** connect GitHub, CI, and the cluster.

> **You are here if steps 1–4 are done:** start at **step 5** (create GitHub repo), then **6 → 7 → 8**.

### At a glance

| Step | Where | What |
|------|--------|------|
| **1** | Local / AWS | Bootstrap Terraform state (`terraform/bootstrap/`) |
| **2** | Local | `terraform apply` → ECR + EC2 (k3s + ArgoCD) |
| **3** | EC2 (SSH) | Verify cluster: `kubectl get nodes` |
| **4** | Local (Git) | Fix `k8s/deployment.yaml` image (AWS account ID) |
| **5** | GitHub | **Create repository** and push your project |
| **6** | GitHub + AWS | Add CI secrets (IAM user for ECR push) |
| **7** | GitHub | Push to `main` → CI builds image and pushes to ECR |
| **8** | EC2 (SSH) | Deploy to cluster (ArgoCD and/or `kubectl apply`) |

After step 8, routine deploys are: **push to `main` → CI → ArgoCD sync** (no SSH).

---

### Phase 1 — Infrastructure (steps 1–4) ✓

<details>
<summary>Steps 1–4 (reference — you have likely completed these)</summary>

**Step 1 — Terraform state bucket**

```powershell
cd terraform/bootstrap
terraform init
terraform apply
terraform output -raw backend_hcl > ../backend.hcl
```

**Step 2 — Main infrastructure**

```powershell
cd ..
terraform init -backend-config=backend.hcl
terraform apply
```

Note outputs: `k3s_public_ip`, `ecr_repository_url`, `aws_account_id`.

**Step 3 — Verify k3s on EC2**

SSH to the node (`.pem` or Session Manager). Wait for `user_data` to finish (10–20 min on first boot):

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes          # STATUS should be Ready
kubectl get pods -A        # argocd namespace should appear when bootstrap completes
sudo tail -f /var/log/cloud-init-output.log   # until you see bootstrap complete
```

**Step 4 — Fix deployment image (on your PC, in Git)**

Replace `000000000000` in `k8s/deployment.yaml` with your account ID:

```powershell
cd terraform
terraform output aws_account_id
```

Example image line:

```yaml
image: 791778419317.dkr.ecr.eu-west-2.amazonaws.com/datavault-api:latest
```

Do **not** deploy yet — commit this in **step 5** when you push to GitHub.

</details>

---

### Phase 2 — GitHub and CI (steps 5–7)

#### Step 5 — Create your GitHub repository and push code

**When:** After step 4, **before** ArgoCD or CI. ArgoCD and GitHub Actions both need a remote repo.

1. On GitHub: **New repository** (e.g. `datavault-gitops`), **private** recommended.
2. Do **not** add a README/license if you already have a local repo (avoids merge conflicts).
3. On your PC, from the project root:

```powershell
git init
git add .
git commit -m "Initial DataVault GitOps platform"
git branch -M main
git remote add origin https://github.com/YOUR_GITHUB_USER/datavault-gitops.git
git push -u origin main
```

4. Edit `argocd/application.yaml` — replace the placeholder repo URL:

```yaml
repoURL: https://github.com/YOUR_GITHUB_USER/datavault-gitops.git
```

5. Commit and push:

```powershell
git add argocd/application.yaml k8s/deployment.yaml
git commit -m "Configure ArgoCD repo URL and ECR image"
git push
```

**Check:** GitHub shows `app/`, `k8s/`, `terraform/`, `.github/workflows/ci.yml`, and `argocd/application.yaml`.

---

#### Step 6 — GitHub Actions secrets (AWS credentials for CI)

**When:** After the repo exists, **before** step 7. CI cannot push to ECR without these.

1. In AWS IAM, create a user (e.g. `datavault-github-actions`) with programmatic access.
2. Attach a policy that allows ECR push to your repo (minimum: `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:PutImage`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload` on `datavault-api`).
3. In GitHub: **Settings → Secrets and variables → Actions → New repository secret**
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`

**Check:** Secrets exist; region in `.github/workflows/ci.yml` is `eu-west-2` (matches Terraform).

---

#### Step 7 — First CI run (build image and push to ECR)

**When:** Immediately after step 6. Pods need an image in ECR before they can start.

1. Trigger CI by pushing to `main` (even a small commit):

```powershell
git commit --allow-empty -m "Trigger first CI build"
git push
```

2. In GitHub: **Actions** tab → wait for **DataVault CI** to finish (test + build-and-deploy).
3. In AWS: **ECR → datavault-api** → confirm an image tag (`latest` and a commit SHA).
4. CI may commit an updated `k8s/deployment.yaml` with the SHA tag — pull on your PC:

```powershell
git pull
```

**Check:** ECR has images; Actions workflow is green.

**If CI fails:** open the failed job log (tests, AWS auth, or ECR permissions).

---

### Phase 3 — Deploy to the cluster (step 8)

**When:** After step 7 (image in ECR). All commands below run **on the EC2 instance** (SSH), unless noted.

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

Clone the **same** repo you pushed in step 5:

```bash
git clone https://github.com/YOUR_GITHUB_USER/datavault-gitops.git
cd datavault-gitops
```

Choose **one** path (GitOps is recommended after first boot).

---

#### Path A — GitOps (recommended): ArgoCD applies `k8s/`

1. Register the Application (once):

```bash
kubectl apply -f argocd/application.yaml
kubectl get applications -n argocd
```

2. Wait for sync (1–3 minutes):

```bash
kubectl get pods
kubectl get application datavault-api -n argocd
```

3. In ArgoCD UI (optional): `http://<EC2_PUBLIC_IP>:30081`  
   Admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

4. **Verify API:**

```bash
curl -s http://localhost:30080/health
# Or from your PC: http://<EC2_PUBLIC_IP>:30080/health
```

ArgoCD will keep the cluster aligned with Git; you usually **do not** run `kubectl apply -f k8s/` again.

---

#### Path B — Manual first deploy: `kubectl apply` then ArgoCD

Use this if you want workloads running **before** wiring ArgoCD.

1. On EC2, from the cloned repo:

```bash
kubectl apply -f k8s/
kubectl get pods -w
```

2. Confirm pods are **Running** (not `ImagePullBackOff` — if they are, finish step 7 first).

3. Then register ArgoCD (step 8 Path A, command 1) so future changes come from Git.

---

### Step 8 verification checklist

| Check | Command / URL |
|--------|----------------|
| Nodes ready | `kubectl get nodes` |
| App pods running | `kubectl get pods` |
| Service | `kubectl get svc` |
| Health | `curl http://<EC2_IP>:30080/health` |
| ArgoCD app synced | `kubectl get application -n argocd` |
| HPA | `kubectl get hpa` |

---

### What happens after setup (ongoing)

1. You change `app/` and push to `main`.
2. GitHub Actions: test → build → push to ECR → update `k8s/deployment.yaml` → commit to Git.
3. ArgoCD detects the manifest change and rolls out new pods.

No SSH required for normal application deploys.

---

### Common issues (steps 5–8)

| Symptom | Likely cause | Fix |
|---------|----------------|-----|
| `ImagePullBackOff` / ECR **403 Forbidden** | Missing ECR auth for k3s (not Docker) | Ensure `ecr-pull-secret` exists: `kubectl get secret ecr-pull-secret`; sync `k8s/` or run `/usr/local/bin/ecr-refresh-k8s-secret.sh` on EC2 |
| `ImagePullBackOff` | No image in ECR yet | Complete step 7; confirm ECR has `datavault-api` image |
| ArgoCD **Unknown** / sync failed | Wrong `repoURL` or private repo without credentials | Fix `argocd/application.yaml`; for private repos configure ArgoCD repo credentials |
| CI **Access Denied** on ECR | Missing/wrong GitHub secrets | Re-check step 6 IAM policy and secrets |
| `kubectl` not found on EC2 | kubeconfig not set | `export KUBECONFIG=/etc/rancher/k3s/k3s.yaml` |
| API not reachable on :30080 | Pods not ready or security group | `kubectl get pods`; SG allows 30080 |
| ArgoCD UI not loading | Still bootstrapping | Wait for `user_data`; check `kubectl get pods -n argocd` |

---

## 6. Demo Scenarios

Use these during your Week 2 presentation to Priya Mehta and the Tier 1 bank compliance representative.

| Demo | Command / Action |
|------|------------------|
| **Self-healing** | `kubectl delete pod <name>` → new pod appears within ~30 seconds |
| **Rollback** | Deploy broken version → `git revert <commit>` → push → ArgoCD rolls back |
| **Audit trail** | `git log k8s/deployment.yaml` — shows who deployed what and when |
| **HPA scaling** | Generate CPU load → `kubectl get hpa` shows replica count increasing |
| **Teardown** | `terraform destroy` — removes EC2 and ECR from AWS |

### Presentation Talking Points

- **The Git log IS the audit trail** — show commit author, message, timestamp, and PR approval
- **Contrast with old process:** "This used to take 40 minutes and required SSH into three servers. It now takes minutes and requires a Git push."
- **Self-healing:** Compare to 2 hours 33 minutes on Valentine's Day — kill a pod live and time the recovery

---

## 7. Placeholders You Must Fill In

Before going live, replace these placeholders:

| Location | When | What to change |
|----------|------|----------------|
| **`terraform/bootstrap/`** | Step 1 | Run bootstrap; generate `terraform/backend.hcl` |
| **`terraform/terraform.tfvars`** | Step 2 | `ssh_key_name` for EC2 SSH |
| **`k8s/deployment.yaml`** | Step 4 | AWS account ID in ECR image URI |
| **`argocd/application.yaml`** | Step 5 | Your real GitHub `repoURL` |
| **GitHub repository** | Step 5 | Create repo and push project |
| **GitHub repo secrets** | Step 6 | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` |

---

## 8. Architecture Summary

| Tool | What It Does | Why DataVault Needs It |
|------|--------------|------------------------|
| **k3s** | Lightweight Kubernetes on a single EC2 instance | Self-healing, scaling, rollbacks — replaces 3 bare-metal servers |
| **ArgoCD** | GitOps — syncs cluster to Git | Every deployment and rollback is a Git commit (FCA audit trail) |
| **Kubernetes manifests** | Declarative desired state | What is in Git is what runs in production — no config drift |
| **HPA** | Auto-scales pods on CPU | Handles end-of-month compliance report spikes |
| **Probes** | Liveness + readiness health checks | Crashed pods restart; unready pods get no traffic |
| **GitHub Actions** | CI: test, build, push, update manifest | Automates build; triggers the GitOps loop |
| **Terraform** | Provisions ECR + EC2 | Reproducible infrastructure anyone can recreate |
| **Amazon ECR** | Private container registry | Secure image storage; cluster pulls during deploy |

---

*Document generated for DataVault Technologies — Amdari Internship Programme*

*Confidential — Platform Engineering Remediation (90-day plan)*
