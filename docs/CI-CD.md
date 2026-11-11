# CI/CD security decision — 2026-11-11

**Status:** Remediated in GitHub source; no GCP bootstrap, CI execution or Terraform plan has been validated.

## Active pull-request workflow

`.github/workflows/terraform-pr.yml` now runs **credential-free**:
- `terraform fmt -check -recursive`
- `terraform init -backend=false` and `terraform validate` on bootstrap and PoC
- Repository token has only `contents: read`. No OIDC, secret access, deployer impersonation, plan or apply.

**Why:** A PR author who can change the workflow could insert an `apply` or arbitrary cloud commands. The old workflow made its `plan` job run as a full-write infrastructure deployer. A GitHub Environment is not a substitute for separating that identity from untrusted PR code. This risk is especially important in the public repository.

## Workload Identity Federation source

`terraform/bootstrap/github_oidc.tf` now declares three parameters:
- `github_repository_full_name`
- `github_repository_id`
- `github_owner_id`

The provider checks immutable repository/owner IDs plus repository name, `refs/heads/main`, and `workflow_dispatch`. It **does not** have any `roles/iam.workloadIdentityUser` binding to the full-write deployer or another SA. A provider without an impersonation grant cannot, by itself, deploy infrastructure.

Repository identities are supplied in `terraform/bootstrap/terraform.tfvars.example`. The names/IDs must be checked again if the repository is transferred. Do not take identity or trust parameters from an untrusted PR.

## Terraform plan / apply during evaluation

Until a separate plan-only identity and protected workflow are implemented, run plans locally as an authorized operator impersonating the deployer SA as documented in `docs/DEPLOY.md`. For first deployment, manually inspect `terraform plan` and `terraform apply`. No service-account JSON keys are used.

The long-term CI split should be:
1. Untrusted PRs: static checks only.
2. Approved read-only plan from trusted code: dedicated `terraform-plan` SA, carefully scoped to the required read APIs and state access.
3. Deploy from protected default branch/environment: separate deployer SA, limited to reviewed code and gated approval.

**Security caveat:** Our state currently contains Terraform-generated secrets; even a read-only plan SA with state-object read access may be able to extract them. Solve secret-value seeding before allowing arbitrary developers to view real plans or state.

## Release image / SHA consistency

`scripts/prepare-release.ps1` reads the checked-out `git rev-parse --short=7 HEAD`, builds with an OCI revision label, pushes to Artifact Registry, resolves the immutable image digest from Docker, and generates a saved Terraform plan setting both `deployed_commit` and `container_image` together. It intentionally does **not** auto-apply. Plans and source commits must be reviewed.

The Terraform variables still exist for explicit auditability; the script reduces human drift rather than cryptographically attesting that the container contents match a commit. Production should use controlled, reproducible builds, provenance/signatures and deployment by digest.

## Known limitations

- The GitHub Actions validation job has not been executed successfully.
- GCP/GitHub Workload Identity Federation has not been applied; no CI cloud privileges are active from this Terraform source.
- The container image has not been built or pushed.
- `scripts/prepare-release.ps1` requires PowerShell, Docker, Git, gcloud and Terraform and must be tested in the operator's workstation.
- GitHub environments, branch protections and optional plan-only CI identity require a separate setup before enabling privileged automation.
- The verbatim `AI-LOG.md` is still incomplete.

References: https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions ; https://docs.cloud.google.com/iam/docs/best-practices-for-using-workload-identity-federation
