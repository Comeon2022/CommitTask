# Meridian Payments — Google Cloud evaluation (PoC)

**Status — 2026-11-11:** Deployed and exercised in Google Cloud project `commitask01` (project number `238671625358`), region `europe-west1`. This is a **PoC**, not a production-hardened payment system.

## Demonstrated result

- Cloud Run API: `meridian-poc-api`; public smoke test: [GET /health](https://meridian-poc-api-egkkxtz23a-ew.a.run.app/health).
- The live endpoint has returned HTTP 200 with `db: ok`, `secret: ok`, and the actual Git source commit (`8d89261fff66faada4df9a49e25daa8d225d7961` in the last recorded successful test). Verify the current commit when reviewing; the image may have changed since this record.
- PostgreSQL 16 on Cloud SQL: `meridian-poc-postgres`, **private IP only** (`10.128.0.3` at verification), automatic IAM database authentication. The health probe performs a fresh `SELECT 1`.
- Secret Manager: two **synthetic/PoC** secrets are read during the health check. The database-password secret is not used for the API's IAM-authenticated SQL login.
- Network: custom `meridian-poc-vpc`, `meridian-poc-subnet` (`10.42.0.0/24`), Private Google Access and private-ranges-only egress. The state bucket is in the EU multi-region; application resources are in `europe-west1`.
- Image deployment uses an **immutable Artifact Registry digest**, not a mutable `latest` tag.

## GitHub Actions / deployment

1. A reviewed push to `main` starts [`docker-build.yml`](.github/workflows/docker-build.yml): a dedicated builder SA uses GitHub OIDC Workload Identity Federation and repository-scoped Artifact Registry Writer. It embeds `github.sha` in the image and uploads the resulting SHA/digest manifest.
2. [`cloudrun-deploy.yml`](.github/workflows/cloudrun-deploy.yml) runs after the successful build, verifies the upstream SHA and manifest, then deploys that **digest** to the existing Cloud Run service. It uses a **different** WIF provider and service account with Cloud Run Developer on the specific service, service-account User on the API runtime identity, and Artifact Registry Reader on the repository.
3. Deployment is accepted only after `/health` returns HTTP 200 and the expected SHA, `db=ok`, `secret=ok`. Both workflows were observed successful on 2026-11-11. No GitHub Actions job runs `terraform apply`.
4. GitHub Ruleset `protect main` is active and requires pull requests, blocks branch deletion and force pushes, and lists no bypass actors. **It currently targets all branches** (`~ALL`), not just `main`; narrow it to `main` to permit normal feature-branch pushes.

See [CI/CD design](docs/CI-CD.md) and [IAM design](docs/IAM-DESIGN.md).

## Terraform ownership

- `terraform/bootstrap`: privileged human-run root — identity, WIF trust, Artifact Registry, project IAM and the versioned EU GCS state bucket. Current bootstrap security hardening is tracked by [PR #1](https://github.com/Comeon2022/CommitTask/pull/1).
- `terraform/poc`: application VPC, networking, private Cloud SQL, Secret Manager, runtime Cloud Run and resource IAM. Its image field is intentionally excluded from Terraform drift reconciliation because immutable image releases are owned by the CI/CD deploy workflow.
- **Security of Terraform State:** Generated secret payloads remain readable in Terraform state, an explicit PoC limitation. Bootstrap Terraform now controls four legacy GCS bucket roles with **zero members**, retains repository-scoped state access for the deployer/plan SAs, and grants the named bootstrap operator bucket-scoped Storage Admin. The live bucket IAM check on 2026-11-11 confirmed that the four legacy roles were absent. The temporary recovery grant at the project scope must be removed via Terraform and verified with a clean plan.
- `roles/editor` for the unused Compute Engine default service account is removed by an authoritative Terraform role binding in bootstrap; verify that the project IAM policy remains empty for this role.

**Never commit** `terraform.tfvars`, saved `*.tfplan`, state, Google tokens or credentials. Apply bootstrap using the privileged operator, and apply PoC changes only with the approved deployer identity. See [deployment steps](docs/DEPLOY.md).

## Remaining limitations / verification

- The intended developer-triggered Cloud Run migration Job and corresponding PostgreSQL DDL grants are **not implemented**. Developer and migration SAs are architecture scaffolding, not a tested migration path.
- The proposed `db_secret_reader` Google Group was **not created**. Real secrets should eventually be provisioned outside ordinary Terraform state.
- `meridian-poc-api` is publicly invokable for this isolated demonstration. Production would need stronger ingress/API protection, monitoring, HA/DR, workload observability and security reviews.
- The independent PoC Terraform plan previously showed a Cloud Run in-place metadata/scaling diff introduced by `gcloud run services update` (not an image rollback). Do not claim complete PoC drift convergence until rechecked.
- Final confirmation of temporary project-wide Storage Admin revocation, no remaining default Editor grant, the merged PR, and `terraform plan` convergence is still required after the current security cleanup.

## Submission materials

- [Identity / least privilege](docs/IAM-DESIGN.md)
- [CI/CD and release process](docs/CI-CD.md)
- [Secrets design](docs/SECRETS-DESIGN.md)
- [Region design](docs/REGION-DESIGN.md)
- [Original clarifications](CLARIFICATIONS.md)
- [AI usage and verification log](AI-LOG.md)
