# AI assistance and human verification log

**Candidate:** Lior Karu  
**Project:** Meridian Payments — Google Cloud PoC  
**Date:** 2026-11-11

## Use of AI

ChatGPT (GPT-6) was used interactively as a design and coding assistant for Terraform, IAM/WIF trust separation, Cloud Run application code, GitHub Actions CI/CD, debugging and documentation. No reliable measured percentage of generated code is available; do **not** treat the AI contribution as a precise percentage. The candidate executed real infrastructure changes, inspected Terraform plans, reviewed GitHub runs and supplied live command output for verification.

This is a reconstruction of evidenced decisions and corrections, not a verbatim transcript. Actual chat records can be provided separately if requested.

## Three concrete AI corrections with operator evidence

1. **Cloud SQL probe row shape.** The initial Python health code expected the query result to equal `(1,)`. In the tested `pg8000` environment, `SELECT 1` returned `[1]`. The implementation was corrected to check the first scalar column. Subsequently `/health` reported `db: ok`.
2. **Cloud Run v1/v2 CLI mismatch.** A suggested `gcloud run services describe --v2` command failed with `unrecognized arguments: --v2`. The operator used the supported `--format=json | ConvertFrom-Json` v1 `spec.template.metadata.annotations` path instead. It showed `minScale=0`, revision `maxScale=2`, concurrency `80`, digest-pinned image and private-ranges-only egress.
3. **State IAM privilege lockout.** The AI initially recommended removing legacy GCS convenience bindings before ensuring explicit operator bucket IAM rights. Following a partial change, Terraform refresh failed with `403 storage.buckets.getIamPolicy`. The operator recovered via a **temporary project Storage Admin Terraform grant**, created and applied **permanent bucket-scoped Storage Admin** through Terraform, and successfully completed all four legacy binding removals. A live policy check showed exactly operator Storage Admin, deployer Object Admin, plan Object Viewer. Cleanup of the project-level recovery grant was planned as `0 add, 0 change, 1 destroy`; post-cleanup apply evidence remained outstanding at documentation time.

## Additional verification

- CI builder and CI deploy workflows completed successfully in GitHub Actions with separate WIF identities and a digest-based deployment.
- Public Cloud Run `/health` returned HTTP 200 with commit SHA, `db=ok` and `secret=ok` for commit `8d89261fff66faada4df9a49e25daa8d225d7961` at last recorded success.
- Cloud Run service IAM displayed `roles/run.developer` for the CI deploy SA and `roles/run.invoker` for `allUsers`.
- Private-IP Cloud SQL and the GCS state bucket IAM were examined with Google Cloud CLI.
- GitHub `protect main` Ruleset was inspected; it is active with no bypass actors, but initially applied to all branches.

## Unfinished or deliberately out of scope

- Developer-triggered Cloud Run migration Job and PostgreSQL DDL permissions.
- Production API access controls, HA/DR, secret seeding outside Terraform state, and advanced monitoring.
- Independent verification of `gcp-plan` Environment restrictions.
- Final post-cleanup project IAM inspection; Bootstrap no-change plan and PoC metadata/scaling drift resolution.
- Merging PR #1 and finalizing the complete repository on `main`.

## Time accounting

The conversation spans several hours on 2026-11-11; it includes pauses between operator actions. **Exact active hands-on minutes were not independently measured** and should not be presented as an exact duration.
