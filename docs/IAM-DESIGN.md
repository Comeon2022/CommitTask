# IAM Design — Meridian Payments PoC

**Status (2026-11-11):** Infrastructure and CI/CD identities deployed and verified. Final cleanup verification is noted below.

## Identity separation

| Identity | Scope and purpose |
| --- | --- |
| `meridian-poc-deployer` | Terraform-managed functional infrastructure privileges, not project Owner/Editor or project IAM Admin |
| `meridian-poc-api` | Cloud Run runtime; Cloud SQL Client and Instance User; scoped secret reads |
| `meridian-poc-migration` | Reserved for future migrations; migration Job **not implemented** |
| `meridian-poc-dev1/dev2/dev3` | Separate developer identities; developer-triggered migration **not implemented** |
| `meridian-poc-builder` | Artifact Registry Writer on the dedicated repository; WIF `github-build` |
| `meridian-poc-ci-deploy` | Cloud Run Developer on **one existing service**, API runtime Service Account User, repository Artifact Registry Reader; WIF `github-deploy` |
| `meridian-poc-plan` | Project Viewer/Security Reviewer and state-bucket Object Viewer; manually triggered, trusted-main-only WIF plan |
| `group:gcp-hr@comm-it.cloud` | Project Viewer for assessment; no explicit secret access |

Build and deploy GitHub Actions were observed successful. Cloud Run service IAM was checked live: `meridian-poc-ci-deploy` has `roles/run.developer` at service scope, and `allUsers` has `roles/run.invoker` for the public PoC.

## Private database and secret handling

Cloud SQL PostgreSQL 16 uses a private IP only and `cloudsql.iam_authentication=on`. The Python Connector authenticates as the API runtime SA. The live `GET /health` probe returned `db=ok` after `SELECT 1`; this does not prove schema/table grants or migrations. The API reads two synthetic Secret Manager values at request time; its SQL connection uses IAM, **not** the stored password. The proposed `db_secret_reader` group was **not created**.

Terraform state contains generated PoC secret payloads. Therefore even the read-only Plan SA's state object access is security-sensitive. Restrict its GitHub Environment and do not publish state or raw plan files.

## Terraform state bucket hardening — verified

Bucket: `commitask01-tfstate-238671625358`; versioning enabled, uniform bucket-level access and public access prevention enforced.

Terraform bootstrap now manages **empty** role-authoritative bindings for `roles/storage.legacyBucketOwner`, `roles/storage.legacyBucketReader`, `roles/storage.legacyObjectOwner`, and `roles/storage.legacyObjectReader`. The operator successfully applied four additions and inspected the live bucket IAM. The resulting bindings contained **only**:

- `user:karu.lior@gmail.com` — bucket-scoped `roles/storage.admin` (permanent operator access).
- `meridian-poc-deployer` SA — bucket-scoped `roles/storage.objectAdmin`.
- `meridian-poc-plan` SA — bucket-scoped `roles/storage.objectViewer`.

No legacy projectViewer/projectEditor convenience bindings remained. Removing legacy BucketOwner before adding bucket-scoped operator Storage Admin temporarily caused `storage.buckets.getIamPolicy` denial. A temporary **project-level** Storage Admin grant was applied via Terraform for recovery. The operator subsequently added the permanent **bucket-level** grant through Terraform, restored access and prepared a `0 add, 0 change, 1 destroy` plan to remove the project-level temporary grant. **Its cleanup apply and subsequent project IAM verification were not yet observed.**

`terraform/bootstrap/security_hardening.tf` also maintains project `roles/editor` with **no members**, to remove the unused default Compute Engine SA's previous Editor grant. Verify live project IAM after cleanup. These bindings are authoritative for their specific roles; external additions will be removed by a subsequent Terraform apply.

## Remaining limitations

- Public HTTP ingress and `allUsers` Invoker are appropriate only for the isolated PoC.
- Migration job and real database schema grants are not implemented.
- Project-level infrastructure admin roles are functional predefined roles rather than production custom least-privilege roles.
- Confirm restricted `gcp-plan` GitHub Environment if the manual state-reading workflow is used.
- Check project `roles/editor` and `roles/storage.admin` after temporary cleanup; run fresh Bootstrap and PoC plans. The PoC plan previously showed an in-place Cloud Run client/scaling metadata difference after CI deployment, not a rollback of the image.
