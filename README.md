# Meridian Payments — Google Cloud Architect Exercise

**Status:** Working GCP PoC in `commitask01` / `europe-west1` (2026-11-11). **Not production-ready.** [Live GET /health](https://meridian-poc-api-egkkxtz23a-ew.a.run.app/health) · [Repository](https://github.com/Comeon2022/CommitTask).

## Architecture and decisions
- **Cloud Run** for a minimal stateless HTTP API: lower operational cost/complexity than GKE or VMs. Verified live `/health`: real per-request Cloud SQL `SELECT 1` (`db=ok`), real Secret Manager reads (`secret=ok`), candidate, region and embedded deployed commit. Last evidenced SHA: `8d89261fff66faada4df9a49e25daa8d225d7961`. Check currently deployed SHA when reviewing.
- **Cloud SQL PostgreSQL 16**, private IP only, auto IAM DB authentication via API service account; dedicated custom VPC, Private Google Access and Cloud Run direct VPC egress (`private-ranges-only`). No public SQL endpoint.
- **Two PoC secrets** (database password and synthetic provider token) in Secret Manager, read by API runtime SA. SQL login uses IAM rather than this password. Secret **values are also in Terraform state**; not acceptable for production.
- **Terraform:** separate privileged `terraform/bootstrap` root and application `terraform/poc` root, GCS remote state; bucket access restricted to named operator, deployer SA, plan SA. Default Compute Editor revoked in Terraform configuration; verify project policy after cleanup.
- **CI/CD:** main push → GitHub WIF builder → immutable Artifact Registry digest → isolated WIF Cloud Run deployer → health assertions. Build and deploy workflows ran successfully. Terraform ignores CI-owned Cloud Run image changes; no GitHub Terraform auto-apply. A GitHub Ruleset enforces PR changes; at last check it also covered non-main branches.

## Run / verify
From Windows PowerShell, follow [deployment commands](docs/DEPLOY.md) for the required `terraform init → validate → plan → apply` sequence using the authorized identity. Smoke check:
```powershell
Invoke-RestMethod 'https://meridian-poc-api-egkkxtz23a-ew.a.run.app/health'
gh run list --repo Comeon2022/CommitTask --limit 5
```
Keep the live environment up through review. Do not commit secrets, state, `*.tfplan`, credentials or `terraform.tfvars`.

## AI use, corrections and time
**Tool:** ChatGPT GPT-6 (architecture, Terraform, Python API, GitHub Actions and docs). **Rough estimate:** ~80% of initial implementation text drafted with AI assistance; this is an unmeasured judgment, not a code attribution audit. Human operator directed architecture, ran plans/applies, observed failures, verified cloud outputs and approved fixes.

**Three real AI corrections/rejections:** (1) Python `pg8000` `SELECT 1` returned `[1]`, not `(1,)`; fixed scalar check. (2) Suggested `gcloud run services describe --v2` is unsupported; inspected actual v1 `spec.template` instead. (3) Removing GCS legacy IAM before granting explicit bucket admin caused `403 storage.buckets.getIamPolicy`; restored access using Terraform and a temporary project grant, then added bucket-scoped operator admin before completing legacy removal. **Exact original-chat transcript references are pending import to `AI-LOG.md`; the current summary is NOT a compliant substitute.**

**Time spent:** Active hands-on time was not separately measured. The conversation spans more than five elapsed hours; this exceeds the exercise's five-hour hard-stop window in wall-clock time, and should be disclosed rather than silently claiming compliance.

## What remains / what I would do with more time
The developer-triggered migration Job and DB schema grants are design-only. Production needs stronger public API controls, outbound policy, audit/PCI scoping, HA/DR, logging and externally seeded/rotated secrets. Final project IAM cleanup, Bootstrap no-change plan and remaining Cloud Run metadata drift need verification. See [security gaps](docs/PRODUCTION-SECURITY-GAPS.md), [assumptions](ASSUMPTIONS.md), [clarifications](CLARIFICATIONS.md), [IAM design](docs/IAM-DESIGN.md), [CI/CD design](docs/CI-CD.md). **Submission blocker:** replace [AI-LOG.md](AI-LOG.md) with complete unedited AI session transcripts, redacting credentials only.
