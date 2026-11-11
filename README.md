# Meridian Payments — Google Cloud evaluation

**Status: source implementation in progress; not deployed/tested.** Terraform defines a custom VPC, private PostgreSQL Cloud SQL, Cloud Run HTTP API, GCS state bucket and Secret Manager. The `GET /health` handler performs a fresh IAM-authenticated SQL `SELECT 1` and live reads of both Secret Manager secrets. The API returns 503 on failure.

**Identity and design:** A privileged bootstrap root creates 6 distinct service accounts (Terraform deployer, API runtime, migration runtime, 3 per-developer identities) and required IAM. Normal deployer has functional roles but no Owner/Editor/project IAM Admin. The Cloud Run API uses Cloud SQL **automatic IAM database authentication** via Python Connector, not an app password. Developer-triggered migration Job is designed, **not yet implemented**. See `docs/IAM-DESIGN.md`.

**Run:** `docs/DEPLOY.md` (Windows PowerShell); requires existing GCP project, billing, Docker, Terraform, GCS bucket name, actual candidate name/image SHA. Do not commit keys or Terraform state. Terraform-generated DB password and synthetic provider token are stored in Terraform state (PoC limitation).

**AI / review:** ChatGPT GPT-6 helped draft architecture and implementation; code percentage not yet measured. Complete the verbatim `AI-LOG.md` before submission, with 3 genuine AI correction references, time spent and uncompleted work. `CLARIFICATIONS.md` was committed alone first and remains unchanged. **Two-secret requirement:** a real password for a separate built-in DB user and a synthetic API token are both stored/read through Secret Manager; the API still uses IAM SQL login rather than the password. The proposed `db_secret_reader` group is documented but NOT implemented (requires Cloud Identity/Workspace directory). GitHub Actions PR validation and an OIDC-backed plan workflow are present, not yet executed. See `docs/SECRETS-DESIGN.md`.

**With more time:** implement migration job and PostgreSQL GRANTs, WIF CI, production secret seeding, HA/DR, network hardening, monitoring and automated validation.
