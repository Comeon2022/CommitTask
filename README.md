# Meridian Payments — Google Cloud evaluation

**Status: implementation in progress; not deployed.** Infrastructure as code for a minimal Cloud Run HTTP API + Cloud SQL PostgreSQL (private IP) using a custom VPC/Direct VPC egress. Secret Manager stores a database password and synthetic third-party token. The application has a dedicated runtime service account and exposes `GET /health` with real per-request checks. GCS backend is bootstrapped with Terraform.

**Architecture choices:** Cloud Run for minimal stateless API operations, private Cloud SQL via Private Services Access, custom VPC rather than default VPC, no static GitHub JSON service-account keys. Developer-triggered Cloud Run migration Job is **proposed but not implemented**, subject to Meridian approval; see `docs/DEVELOPER-MIGRATIONS.md`.

**Run:** Follow `docs/DEPLOY.md`. Requires existing billing-enabled GCP project, GCS bucket name, Docker and Terraform. All project-specific inputs are Terraform variables; no real project is configured. Cloud SQL and state storage incur costs. The synthetic secret payloads exist in Terraform state; do not expose state.

**AI use:** ChatGPT (GPT-6) was used to review requirements and draft code/documentation; exact generated-code proportion not yet measured. **AI-LOG.md is not yet complete** and must be populated with the verbatim conversation transcript before submission. Do not fabricate AI rejection examples; identify at least three genuine corrections with transcript pointers before final handover.

**Time / validation:** Time total not yet recorded. Infrastructure and API have not been validated with Terraform or deployed. Before submitting, add measured effort, tested URL, three actual AI corrections, and what would change with more time (high availability, production-grade secret rotation, authenticated migration deployment, CI/CD and monitoring).
