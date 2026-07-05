# EKS POC — Learning Plan (Future Milestones)
> Add to this list whenever a new idea comes up. Tick off when done, with date + notes.

---

## Planned Milestones

- [ ] **1. ArgoCD** — GitOps deployment for this POC
      Goal: Instead of manually running `kubectl apply`, ArgoCD watches a Git repo
      and auto-syncs the cluster state. Interview-relevant: "How do you implement GitOps?"

- [ ] **2. Secrets Management — HashiCorp Vault or AWS Secrets Manager**
      Goal: Replace manually-created `kubectl create secret` (current approach) with
      auto-synced secrets from a real secrets manager. Likely via External Secrets Operator.
      Interview-relevant: "How do you avoid hardcoding/manual secrets in Kubernetes?"

- [ ] **3. IRSA (IAM Roles for Service Accounts)**
      Goal: Let Pods assume AWS IAM roles directly (e.g., for S3 access in this app)
      without needing static AWS access keys anywhere.
      Interview-relevant: "How do Pods securely access AWS services like S3/RDS?"
      Note: ALB Controller currently uses a POC shortcut (policy on node IAM role
      directly) instead of IRSA — fix that as part of this milestone too.

- [ ] **4. Fix `frontend/docker-entrypoint.sh` to properly `export PUBLIC_HOSTNAME`**
      Goal: the script currently does `PUBLIC_HOSTNAME="${PUBLIC_HOSTNAME:-_}"` without
      `export`, so when the container's real env var is unset, `envsubst` (a separate
      child process) never sees the fallback value and substitutes empty string —
      crashed nginx with "invalid number of arguments in server_name directive" when
      run in Kubernetes without setting `PUBLIC_HOSTNAME` explicitly. Worked around for
      now by setting `PUBLIC_HOSTNAME=_` explicitly in the k8s Deployment env, but the
      image itself should be fixed (`export PUBLIC_HOSTNAME="${PUBLIC_HOSTNAME:-_}"`)
      so it's robust regardless of orchestrator (compose vs k8s vs bare docker run).
      Interview-relevant: shell scripting deep-dive — difference between a local shell
      variable and an exported env var, and why child processes only see the latter.

---

## Completed Milestones (move here once done)

_(none yet)_

---

## Notes / Learnings tied to each milestone
_(Add detailed notes here as each item gets worked on)_
